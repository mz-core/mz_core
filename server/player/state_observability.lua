MZPlayerStateObservability = MZPlayerStateObservability or {}

local sequence = 0
local recentEvents = {}
local alerts = {}
local alertOrder = {}
local playerStates = {}

local COUNTERS = {
  players_loaded = 0,
  players_alive = 0,
  players_downed = 0,
  players_dead = 0,
  players_respawning = 0,
  state_transitions_total = 0,
  state_transition_rejections_total = 0,
  state_syncs_total = 0,
  state_resync_requests_total = 0,
  vital_reports_total = 0,
  vital_report_rejections_total = 0,
  persistence_pending_total = 0,
  persistence_failures_total = 0,
  status_ticks_total = 0,
  critical_damage_total = 0,
  consumables_total = 0,
  consumable_rollbacks_total = 0,
  medical_treatments_started = 0,
  medical_treatments_completed = 0,
  medical_treatments_cancelled = 0,
  medical_respawns_started = 0,
  medical_respawns_completed = 0,
  medical_respawns_aborted = 0,
  medical_rollbacks_pending = 0
}

local EVENT_METRICS = {
  player_state_transition = 'state_transitions_total',
  player_state_transition_rejected = 'state_transition_rejections_total',
  player_state_persistence_pending = 'persistence_pending_total',
  player_state_persistence_failed = 'persistence_failures_total',
  status_critical_damage = 'critical_damage_total',
  status_consumable_completed = 'consumables_total',
  status_consumable_rollback = 'consumable_rollbacks_total',
  medical_treatment_started = 'medical_treatments_started',
  medical_treatment_completed = 'medical_treatments_completed',
  medical_treatment_cancelled = 'medical_treatments_cancelled',
  medical_respawn_started = 'medical_respawns_started',
  medical_respawn_completed = 'medical_respawns_completed',
  medical_respawn_aborted = 'medical_respawns_aborted',
  medical_item_rollback_pending = 'medical_rollbacks_pending'
}

local ALLOWED_EVENTS = {
  player_state_normalized = true,
  player_state_transition = true,
  player_state_transition_rejected = true,
  player_state_persistence_pending = true,
  player_state_persistence_failed = true,
  player_state_reconciled = true,
  player_state_divergence = true,
  player_state_stale_session = true,
  player_state_invalid_payload = true,
  player_state_rate_limited = true,
  status_critical_damage = true,
  status_consumable_started = true,
  status_consumable_completed = true,
  status_consumable_rollback = true,
  status_activity_rejected = true,
  medical_help_requested = true,
  medical_treatment_started = true,
  medical_treatment_cancelled = true,
  medical_treatment_completed = true,
  medical_item_commit_pending = true,
  medical_item_rollback_pending = true,
  medical_respawn_started = true,
  medical_respawn_completed = true,
  medical_respawn_aborted = true,
  medical_operation_recovered = true
}

local SENSITIVE_KEYS = {
  token = true,
  sessionToken = true,
  observationToken = true,
  metadata = true,
  identifiers = true
}

local SUSPICION_CATEGORIES = {
  not_authorized = true,
  protected_metadata = true,
  player_state_rate_limited = true,
  player_state_stale_session = true,
  player_state_invalid_payload = true,
  status_activity_rate_limited = true,
  medical_inventory_recovery_exhausted = true
}

local function cfg()
  return Config and Config.PlayerStates and Config.PlayerStates.observability or {}
end

local function nowMs()
  if type(GetGameTimer) == 'function' then return GetGameTimer() end
  return math.floor(os.clock() * 1000)
end

local function cloneSanitized(value, depth)
  depth = tonumber(depth) or 0
  if depth > 4 then return '<depth_limited>' end
  if type(value) == 'string' then return value:sub(1, 256) end
  if type(value) ~= 'table' then return value end
  local result, count = {}, 0
  for key, child in pairs(value) do
    count = count + 1
    if count > 32 then break end
    local safeKey = tostring(key):sub(1, 64)
    local outputKey = type(key) == 'number' and key or safeKey
    if SENSITIVE_KEYS[safeKey] or safeKey:lower():find('token', 1, true) then
      result[outputKey] = '<redacted>'
    else
      result[outputKey] = cloneSanitized(child, depth + 1)
    end
  end
  return result
end

local function nextAuditId()
  sequence = sequence + 1
  return ('PSO-%s-%s'):format(tostring(os.time()), tostring(sequence))
end

local function exactMember(list, value)
  for _, candidate in ipairs(type(list) == 'table' and list or {}) do
    if candidate == value then return true end
  end
  return false
end

local function reporterAllowed(resource, eventName)
  if resource == 'mz_core' then return eventName:sub(1, 13) == 'player_state_' end
  if not exactMember(cfg().reporters, resource) then return false end
  if resource == 'mz_status' then return eventName:sub(1, 7) == 'status_' end
  if resource == 'mz_medical' then return eventName:sub(1, 8) == 'medical_' end
  return false
end

local function readerAllowed(resource)
  return exactMember(cfg().readers, resource)
end

local function increment(name, amount)
  if cfg().metricsEnabled == false or COUNTERS[name] == nil then return false end
  amount = tonumber(amount) or 1
  if amount ~= amount or amount == math.huge or amount == -math.huge then return false end
  COUNTERS[name] = math.max(0, COUNTERS[name] + math.floor(amount))
  return true
end

local function appendLimited(list, value, maximum)
  list[#list + 1] = value
  while #list > maximum do table.remove(list, 1) end
end

local function persistLog(eventName, entry)
  if not (MZLogService and type(MZLogService.createDetailed) == 'function') then return false end
  local ok = pcall(MZLogService.createDetailed, 'player_state', eventName, {
    auditId = entry.auditId,
    actor = { type = 'resource', id = entry.resource or 'mz_core', source = entry.source },
    target = { type = 'player', id = entry.citizenid or ('source:%s'):format(tostring(entry.target or entry.source or 0)), citizenid = entry.citizenid },
    context = {
      source = entry.source,
      target = entry.target,
      resource = entry.resource,
      operationId = entry.operationId,
      session = entry.session,
      revision = entry.revision,
      reason = entry.reason,
      timestamp = entry.timestamp
    },
    before = { deathState = entry.previousState },
    after = { deathState = entry.nextState },
    meta = { result = entry.result, error = entry.error, evidence = entry.evidence }
  })
  return ok
end

function MZPlayerStateObservability.record(eventName, fields, invokingResource)
  if cfg().enabled == false or ALLOWED_EVENTS[eventName] ~= true then return false, 'invalid_event' end
  local resource = tostring(invokingResource or 'mz_core')
  if not reporterAllowed(resource, eventName) then return false, 'not_authorized' end
  fields = cloneSanitized(type(fields) == 'table' and fields or {})
  local entry = {
    auditId = tostring(fields.auditId or nextAuditId()):sub(1, 96),
    event = eventName,
    operationId = fields.operationId,
    source = tonumber(fields.source),
    target = tonumber(fields.target),
    citizenid = fields.citizenid,
    resource = resource,
    session = fields.session,
    revision = tonumber(fields.revision),
    previousState = fields.previousState,
    nextState = fields.nextState,
    reason = fields.reason,
    result = fields.result,
    error = fields.error,
    evidence = fields.evidence,
    timestamp = os.time()
  }
  local metric = EVENT_METRICS[eventName]
  if metric then increment(metric, 1) end
  appendLimited(recentEvents, entry, math.max(20, math.floor(tonumber(cfg().recentEventLimit) or 200)))
  persistLog(eventName, entry)
  return true, cloneSanitized(entry)
end

function MZPlayerStateObservability.increment(name, amount)
  return increment(tostring(name or ''), amount)
end

function MZPlayerStateObservability.playerLoaded(source, deathState)
  source = tonumber(source)
  if not source then return end
  local previous = playerStates[source]
  if previous then increment('players_' .. previous, -1) else increment('players_loaded', 1) end
  local state = ({ alive = true, downed = true, dead = true, respawning = true })[deathState] and deathState or 'alive'
  playerStates[source] = state
  increment('players_' .. state, 1)
end

function MZPlayerStateObservability.playerTransition(source, previousState, nextState)
  source = tonumber(source)
  if not source then return end
  local tracked = playerStates[source] or previousState
  if tracked and COUNTERS['players_' .. tracked] ~= nil then increment('players_' .. tracked, -1) end
  playerStates[source] = nextState
  if COUNTERS['players_' .. tostring(nextState)] ~= nil then increment('players_' .. tostring(nextState), 1) end
end

function MZPlayerStateObservability.playerUnloaded(source)
  source = tonumber(source)
  local state = source and playerStates[source] or nil
  if not state then return end
  increment('players_loaded', -1)
  increment('players_' .. state, -1)
  playerStates[source] = nil
end

function MZPlayerStateObservability.reportSuspicion(category, source, fields, invokingResource)
  if cfg().enabled == false then return false, 'feature_disabled' end
  local resource = tostring(invokingResource or 'mz_core')
  if resource ~= 'mz_core' and not exactMember(cfg().reporters, resource) then return false, 'not_authorized' end
  category = tostring(category or 'unknown'):gsub('[^%w_%-%.]', '_'):sub(1, 64)
  if SUSPICION_CATEGORIES[category] ~= true then return false, 'invalid_category' end
  source = tonumber(source)
  if not source or source <= 0 then return false, 'invalid_source' end
  local settings = cfg().alerts or {}
  local current = nowMs()
  local windowMs = math.max(1000, math.floor(tonumber(settings.windowMs) or 60000))
  local key = ('%s:%s'):format(source, category)
  local alert = alerts[key]
  if not alert or current - alert.windowStartedAt >= windowMs then
    alert = {
      auditId = nextAuditId(), severity = 'low', category = category, source = source,
      reason = tostring(fields and fields.reason or category):sub(1, 128), count = 0,
      window = math.floor(windowMs / 1000), firstSeenAt = os.time(), lastSeenAt = os.time(),
      windowStartedAt = current, lastLoggedAt = nil, evidence = {}
    }
    alerts[key] = alert
    alertOrder[#alertOrder + 1] = key
  end
  alert.count = alert.count + 1
  alert.lastSeenAt = os.time()
  alert.evidence = cloneSanitized(fields and fields.evidence or { error = fields and fields.error, operation = fields and fields.operation })
  local threshold = math.max(2, math.floor(tonumber(settings.threshold) or 3))
  if alert.count >= threshold then alert.severity = alert.count >= threshold * 3 and 'high' or 'medium' end
  local cooldown = math.max(1000, math.floor(tonumber(settings.cooldownMs) or 30000))
  if alert.count >= threshold and (not alert.lastLoggedAt or current - alert.lastLoggedAt >= cooldown) then
    alert.lastLoggedAt = current
    persistLog('player_state_suspicious_activity', {
      auditId = alert.auditId, source = source, resource = resource, reason = alert.reason,
      result = 'aggregated', error = category, evidence = {
        severity = alert.severity, category = category, count = alert.count,
        window = alert.window, firstSeenAt = alert.firstSeenAt, lastSeenAt = alert.lastSeenAt,
        summary = alert.evidence
      }, timestamp = os.time()
    })
  end
  local maximum = math.max(10, math.floor(tonumber(settings.recentLimit) or 100))
  while #alertOrder > maximum do alerts[table.remove(alertOrder, 1)] = nil end
  return true, cloneSanitized(alert)
end

function MZPlayerStateObservability.snapshot()
  return { metrics = cloneSanitized(COUNTERS), recentEvents = cloneSanitized(recentEvents), alerts = MZPlayerStateObservability.alertSnapshot() }
end

function MZPlayerStateObservability.alertSnapshot()
  local result = {}
  for _, key in ipairs(alertOrder) do
    local alert = alerts[key]
    if alert and alert.count >= math.max(2, math.floor(tonumber(cfg().alerts and cfg().alerts.threshold) or 3)) then
      result[#result + 1] = cloneSanitized(alert)
    end
  end
  return result
end

exports('RecordPlayerStateEvent', function(eventName, fields)
  return MZPlayerStateObservability.record(eventName, fields, GetInvokingResource())
end)

exports('ReportPlayerStateSuspicion', function(category, source, fields)
  return MZPlayerStateObservability.reportSuspicion(category, source, fields, GetInvokingResource())
end)

exports('IncrementPlayerStateMetric', function(name, amount)
  local resource = GetInvokingResource()
  if resource == 'mz_status' and name == 'status_ticks_total' then
    return MZPlayerStateObservability.increment(name, amount)
  end
  return false, 'not_authorized'
end)

exports('GetPlayerStateObservability', function()
  if not readerAllowed(GetInvokingResource()) then return false, 'not_authorized' end
  return true, MZPlayerStateObservability.snapshot()
end)

if rawget(_G, 'MZ_PLAYER_STATE_OBSERVABILITY_TESTING') == true then
  MZPlayerStateObservability._test = {
    sanitize = cloneSanitized,
    counters = COUNTERS,
    reset = function()
      recentEvents, alerts, alertOrder, playerStates = {}, {}, {}, {}
      for name in pairs(COUNTERS) do COUNTERS[name] = 0 end
    end
  }
end
