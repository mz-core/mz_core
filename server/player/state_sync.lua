MZPlayerStateSyncService = MZPlayerStateSyncService or {}

local SYNC_EVENT = 'mz_core:client:playerStateSync'
local RESYNC_EVENT = 'mz_core:server:requestPlayerStateSync'
local OBSERVATION_EVENT = 'mz_core:server:reportVitalCandidate'

local BAG_KEYS = {
  loaded = 'loaded',
  revision = 'stateRevision',
  deathState = 'deathState',
  isDead = 'isDead',
  isDowned = 'isDowned',
  isRespawning = 'isRespawning',
  inventoryBlocked = 'inventoryBlocked',
  weaponBlocked = 'weaponBlocked',
  interactionBlocked = 'interactionBlocked'
}

local ALLOWED_OBSERVATION_FIELDS = {
  sessionToken = true,
  observationToken = true,
  sequence = true,
  localRevision = true,
  observedHealth = true,
  observedArmor = true,
  observedDead = true
}

local function config()
  return Config and Config.PlayerStates or {}
end

local function clone(value)
  if type(value) ~= 'table' then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = clone(child) end
  return result
end

local function finite(value)
  return MZPlayerStateNormalizer and MZPlayerStateNormalizer.isFiniteNumber(value) == true
end

local function bagName(key)
  local prefix = tostring(config().stateBags and config().stateBags.prefix or 'mz:')
  return prefix .. tostring(BAG_KEYS[key])
end

local function rejection(source, eventName, reason)
  if MZPlayerStateObservability then
    MZPlayerStateObservability.increment('vital_report_rejections_total', eventName == OBSERVATION_EVENT and 1 or 0)
    local structured = reason == 'rate_limited' and 'player_state_rate_limited'
      or (reason == 'invalid_session' or reason == 'stale_sequence' or reason == 'stale_revision') and 'player_state_stale_session'
      or 'player_state_invalid_payload'
    MZPlayerStateObservability.reportSuspicion(structured, source, {
      reason = tostring(reason), error = tostring(reason), operation = eventName,
      evidence = { event = eventName }
    }, 'mz_core')
  end
  if MZPlayerStateService.shouldLogClientSyncRejection(source, 3000) then
    print(('[mz_core][player_state][client_event_rejected] source=%s event=%s reason=%s'):format(
      tostring(source), tostring(eventName), tostring(reason)
    ))
    if MZPlayerStateObservability then
      local structured = reason == 'rate_limited' and 'player_state_rate_limited'
        or (reason == 'invalid_session' or reason == 'stale_sequence' or reason == 'stale_revision') and 'player_state_stale_session'
        or 'player_state_invalid_payload'
      MZPlayerStateObservability.record(structured, {
        source = source, reason = tostring(reason), result = 'rejected', error = eventName
      }, 'mz_core')
    end
  end
end

local function stateBagHandle(source)
  if config().stateBags and config().stateBags.enabled == false then return nil, 'disabled' end
  if type(Player) ~= 'function' then return nil, 'player_state_unavailable' end
  local ok, player = pcall(Player, source)
  if not ok or player == nil then return nil, 'player_state_unavailable' end
  local stateOk, state = pcall(function() return player.state end)
  if not stateOk or state == nil or type(state.set) ~= 'function' then
    return nil, 'player_state_unavailable'
  end
  return state
end

local function setBag(state, key, value)
  local ok, err = pcall(state.set, state, bagName(key), value, true)
  if not ok then return false, err end
  return true
end

local function writeStateBags(source, snapshot)
  local state, stateErr = stateBagHandle(source)
  if not state then return false, stateErr end
  local deathState = tostring(snapshot.deathState or 'alive')
  local blocked = deathState ~= 'alive'
  local ordered = {
    { 'isDead', deathState == 'dead' },
    { 'isDowned', deathState == 'downed' },
    { 'isRespawning', deathState == 'respawning' },
    { 'deathState', deathState },
    { 'inventoryBlocked', blocked },
    { 'weaponBlocked', blocked },
    { 'interactionBlocked', blocked },
    { 'loaded', true },
    { 'revision', snapshot.revision }
  }
  for _, entry in ipairs(ordered) do
    local ok, err = setBag(state, entry[1], entry[2])
    if not ok then return false, err end
  end
  return true
end

function MZPlayerStateSyncService.clearStateBags(source)
  local state, stateErr = stateBagHandle(source)
  if not state then return { ok = false, code = stateErr } end
  local ordered = {
    { 'isDead', false },
    { 'isDowned', false },
    { 'isRespawning', false },
    { 'deathState', 'alive' },
    { 'inventoryBlocked', false },
    { 'weaponBlocked', false },
    { 'interactionBlocked', false },
    { 'loaded', false },
    { 'revision', 0 }
  }
  for _, entry in ipairs(ordered) do
    local ok, err = setBag(state, entry[1], entry[2])
    if not ok then
      print(('[mz_core][player_state][state_bag_clear_failed] source=%s key=%s error=%s'):format(
        tostring(source), tostring(entry[1]), tostring(err)
      ))
      return { ok = false, code = 'state_bag_failed' }
    end
  end
  return { ok = true }
end

local function buildPayload(source, reason, options)
  local stateOk, stateResult = MZPlayerStateService.getState(source)
  if not stateOk then return nil, stateResult and stateResult.code or 'state_unavailable' end
  local identityOk, identity = MZPlayerStateService.getSyncIdentity(source)
  if not identityOk then return nil, identity and identity.code or 'identity_unavailable' end
  local snapshot = stateResult.state
  local deathState = tostring(snapshot.deathState or 'alive')
  local blocked = deathState ~= 'alive'
  options = type(options) == 'table' and options or {}
  return {
    revision = snapshot.revision,
    sessionToken = identity.sessionToken,
    observationToken = identity.observationToken,
    status = clone(snapshot.status),
    death = {
      state = deathState,
      isdead = snapshot.isdead == true,
      inlaststand = snapshot.inlaststand == true,
      downedAt = snapshot.deathTimestamps and snapshot.deathTimestamps.downedAt or nil,
      downedExpiresAt = snapshot.deathTimestamps and snapshot.deathTimestamps.downedExpiresAt or nil,
      deadAt = snapshot.deathTimestamps and snapshot.deathTimestamps.deadAt or nil,
      respawnAvailableAt = snapshot.deathTimestamps and snapshot.deathTimestamps.respawnAvailableAt or nil
    },
    permissions = {
      inventoryBlocked = blocked,
      weaponBlocked = blocked,
      interactionBlocked = blocked
    },
    reason = {
      code = tostring(reason or 'state_changed'):sub(1, 64),
      serverTime = os.time()
    },
    forcePhysicalApply = options.forcePhysicalApply == true,
    sessionReset = options.sessionReset == true
  }, nil, snapshot
end

function MZPlayerStateSyncService.sync(source, reason, options)
  if config().sync and config().sync.enabled == false then
    return { ok = false, code = 'feature_disabled' }
  end
  source = tonumber(source)
  if not source or source <= 0 then return { ok = false, code = 'invalid_source' } end
  local payload, payloadErr, snapshot = buildPayload(source, reason, options)
  if not payload then return { ok = false, code = payloadErr } end

  local bagsOk, bagsErr = writeStateBags(source, snapshot)
  if not bagsOk and bagsErr ~= 'disabled' then
    print(('[mz_core][player_state][state_bag_failed] source=%s reason=%s error=%s'):format(
      tostring(source), tostring(reason), tostring(bagsErr)
    ))
  end

  TriggerClientEvent(SYNC_EVENT, source, payload)
  if MZPlayerStateObservability then MZPlayerStateObservability.increment('state_syncs_total', 1) end
  if MZPlayerHUDService and MZPlayerHUDService.syncToClient then
    local hudOk, hudErr = pcall(MZPlayerHUDService.syncToClient, source)
    if not hudOk then
      print(('[mz_core][player_state][hud_adapter_failed] source=%s error=%s'):format(
        tostring(source), tostring(hudErr)
      ))
    end
  end
  return { ok = true, revision = payload.revision, payload = clone(payload), stateBags = bagsOk }
end

local function validateObservationPayload(payload)
  if type(payload) ~= 'table' then return false, 'invalid_payload' end
  local count = 0
  for key in pairs(payload) do
    count = count + 1
    if count > 7 then return false, 'payload_too_large' end
    if ALLOWED_OBSERVATION_FIELDS[key] ~= true then return false, 'unknown_field' end
  end
  if type(payload.sessionToken) ~= 'string' or payload.sessionToken == '' or #payload.sessionToken > 96 then
    return false, 'invalid_session'
  end
  if type(payload.observationToken) ~= 'string' or payload.observationToken == '' or #payload.observationToken > 96 then
    return false, 'invalid_observation_token'
  end
  if not finite(payload.sequence) or payload.sequence < 1 or payload.sequence ~= math.floor(payload.sequence) then
    return false, 'invalid_sequence'
  end
  if not finite(payload.localRevision) or payload.localRevision < 0
    or payload.localRevision ~= math.floor(payload.localRevision) then
    return false, 'invalid_revision'
  end
  if payload.observedDead ~= nil and type(payload.observedDead) ~= 'boolean' then
    return false, 'invalid_dead_flag'
  end
  if payload.observedHealth ~= nil
    and (not finite(payload.observedHealth) or payload.observedHealth < 0 or payload.observedHealth > 200) then
    return false, 'invalid_health'
  end
  if payload.observedArmor ~= nil
    and (not finite(payload.observedArmor) or payload.observedArmor < 0 or payload.observedArmor > 100) then
    return false, 'invalid_armor'
  end
  if payload.observedHealth == nil and payload.observedArmor == nil and payload.observedDead ~= true then
    return false, 'empty_observation'
  end
  return true
end

local function serverConfirmsFatal(source)
  if type(GetPlayerPed) ~= 'function' then return false, false end
  local ok, ped = pcall(GetPlayerPed, source)
  if not ok or not ped or ped == 0 then return false, false end
  if type(DoesEntityExist) == 'function' then
    local existsOk, exists = pcall(DoesEntityExist, ped)
    if not existsOk or exists ~= true then return false, false end
  end

  local checked, dead = false, false
  if type(GetEntityHealth) == 'function' then
    local healthOk, health = pcall(GetEntityHealth, ped)
    if healthOk and type(health) == 'number' then
      checked = true
      dead = health <= 0
    end
  end
  if type(IsEntityDead) == 'function' then
    local deadOk, nativeDead = pcall(IsEntityDead, ped)
    if deadOk and type(nativeDead) == 'boolean' then
      checked = true
      dead = dead or nativeDead
    end
  end
  return checked, dead
end

RegisterNetEvent(RESYNC_EVENT, function(...)
  local sourceId = source
  if MZPlayerStateObservability then MZPlayerStateObservability.increment('state_resync_requests_total', 1) end
  local syncConfig = config().sync or {}
  local attemptOk, attemptResult = MZPlayerStateService.consumeClientEventAttempt(
    sourceId,
    'resync',
    syncConfig.resyncMaxRequestsPerWindow or 5,
    syncConfig.resyncWindowMs or 10000
  )
  if not attemptOk then
    rejection(sourceId, RESYNC_EVENT, attemptResult and attemptResult.reason or 'rate_limited')
    return
  end
  if select('#', ...) > 0 then
    rejection(sourceId, RESYNC_EVENT, 'payload_forbidden')
    return
  end
  local allowed, result = MZPlayerStateService.authorizeClientResync(sourceId)
  if not allowed then
    rejection(sourceId, RESYNC_EVENT, result and result.reason or result and result.code or 'rejected')
    return
  end
  local syncResult = MZPlayerStateSyncService.sync(sourceId, 'client_resource_resync', {
    forcePhysicalApply = true
  })
  if syncResult.ok ~= true then
    print(('[mz_core][player_state][resync_failed] source=%s code=%s'):format(
      tostring(sourceId), tostring(syncResult.code)
    ))
  end
end)

RegisterNetEvent(OBSERVATION_EVENT, function(payload)
  local sourceId = source
  if MZPlayerStateObservability then MZPlayerStateObservability.increment('vital_reports_total', 1) end
  if config().clientObservation and config().clientObservation.enabled == false then return end
  local observationConfig = config().clientObservation or {}
  local attemptOk, attemptResult = MZPlayerStateService.consumeClientEventAttempt(
    sourceId,
    'observation',
    observationConfig.maxReportsPerWindow or 10,
    observationConfig.windowMs or 10000
  )
  if not attemptOk then
    rejection(sourceId, OBSERVATION_EVENT, attemptResult and attemptResult.reason or 'rate_limited')
    return
  end
  local payloadOk, payloadErr = validateObservationPayload(payload)
  if not payloadOk then
    rejection(sourceId, OBSERVATION_EVENT, payloadErr)
    return
  end
  local envelopeOk, envelopeResult = MZPlayerStateService.validateObservationEnvelope(sourceId, payload)
  if not envelopeOk then
    rejection(sourceId, OBSERVATION_EVENT, envelopeResult and envelopeResult.reason or 'envelope_rejected')
    return
  end

  local observedHealth = payload.observedHealth ~= nil and math.floor(payload.observedHealth) or nil
  local observedArmor = payload.observedArmor ~= nil and math.floor(payload.observedArmor) or nil
  local fatal = payload.observedDead == true or (observedHealth ~= nil and observedHealth <= 0)
  if fatal then
    local checked, serverDead = serverConfirmsFatal(sourceId)
    if checked and not serverDead then
      rejection(sourceId, OBSERVATION_EVENT, 'server_ped_alive')
      return
    end
    local candidateOk, candidate = MZPlayerStateService.registerFatalCandidate(sourceId, checked and serverDead)
    if not candidateOk then
      rejection(sourceId, OBSERVATION_EVENT, candidate and candidate.code or 'fatal_candidate_rejected')
      return
    end
    if candidate.transition ~= true then
      if candidate.code == 'fatal_cooldown' then rejection(sourceId, OBSERVATION_EVENT, candidate.code) end
      return
    end

    local context = MZPlayerStateService.internalContext('fatal_damage_candidate', {
      serverConfirmed = candidate.confirmedByServer == true
    })
    local transitionOk, transitionResult
    if config().death and config().death.lastStandEnabled ~= false then
      transitionOk, transitionResult = MZPlayerStateService.markDowned(sourceId, context)
    else
      transitionOk, transitionResult = MZPlayerStateService.markDead(sourceId, context)
    end
    if not transitionOk then
      rejection(sourceId, OBSERVATION_EVENT, transitionResult and transitionResult.code or 'fatal_transition_failed')
    end
    return
  end

  local stateOk, stateResult = MZPlayerStateService.getState(sourceId)
  if not stateOk then return end
  local canonical = stateResult.state.status
  local observation = config().clientObservation or {}
  if observedHealth and canonical.health - observedHealth >= (tonumber(observation.extremeHealthReduction) or 100) then
    print(('[mz_core][player_state][extreme_health_reduction] source=%s from=%s to=%s'):format(
      tostring(sourceId), tostring(canonical.health), tostring(observedHealth)
    ))
  end
  if observedArmor and canonical.armor - observedArmor >= (tonumber(observation.extremeArmorReduction) or 75) then
    print(('[mz_core][player_state][extreme_armor_reduction] source=%s from=%s to=%s'):format(
      tostring(sourceId), tostring(canonical.armor), tostring(observedArmor)
    ))
  end

  local accepted, acceptResult = MZPlayerStateService.applyObservedVitals(sourceId, observedHealth, observedArmor)
  if not accepted then
    rejection(sourceId, OBSERVATION_EVENT, acceptResult and acceptResult.reason or acceptResult and acceptResult.code or 'vitals_rejected')
  elseif MZPlayerStateObservability and acceptResult and acceptResult.changed == true then
    MZPlayerStateObservability.record('player_state_reconciled', {
      source = sourceId, revision = acceptResult.revision, reason = 'vital_observation', result = 'changed'
    }, 'mz_core')
  end
end)

if rawget(_G, 'MZ_PLAYER_STATE_TESTING') == true then
  MZPlayerStateSyncService._test = {
    buildPayload = buildPayload,
    writeStateBags = writeStateBags,
    validateObservationPayload = validateObservationPayload,
    serverConfirmsFatal = serverConfirmsFatal,
    events = {
      sync = SYNC_EVENT,
      resync = RESYNC_EVENT,
      observation = OBSERVATION_EVENT
    }
  }
end
