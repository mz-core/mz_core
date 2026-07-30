MZLogService = {}

local SENSITIVE_KEYS = {
  ip = true,
  token = true,
  tokens = true,
  license = true,
  license2 = true,
  identifier = true,
  identifiers = true,
  password = true,
  secret = true,
  inventory = true,
  money = true
}

local function trim(value)
  if type(value) ~= 'string' then return nil end
  value = value:gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' then return nil end
  return value
end

local function limitString(value, maxLength)
  value = trim(value)
  if not value then return nil end
  maxLength = tonumber(maxLength) or 64
  if #value > maxLength then
    value = value:sub(1, maxLength)
  end
  return value
end

local function sanitizeNumber(value, fallback, minValue, maxValue)
  value = tonumber(value) or fallback
  value = math.floor(value or 0)
  if minValue and value < minValue then value = minValue end
  if maxValue and value > maxValue then value = maxValue end
  return value
end

local function isSensitiveKey(key)
  key = tostring(key or ''):lower()
  return SENSITIVE_KEYS[key] == true
end

local function cloneTable(value)
  if type(value) ~= 'table' then
    return value
  end

  local out = {}
  for k, v in pairs(value) do
    out[k] = cloneTable(v)
  end
  return out
end

local function sanitizePanelPayload(value)
  if type(value) ~= 'table' then return {} end

  local out = {}
  for k, v in pairs(value) do
    if not isSensitiveKey(k) then
      if type(v) == 'table' then
        out[k] = sanitizePanelPayload(v)
      elseif type(v) == 'string' or type(v) == 'number' or type(v) == 'boolean' then
        out[k] = v
      end
    end
  end

  return out
end

local function normalizeScalar(value, fallback)
  if value == nil then
    return fallback
  end

  local valueType = type(value)
  if valueType == 'string' then
    local trimmed = value:gsub('^%s+', ''):gsub('%s+$', '')
    if trimmed == '' then
      return fallback
    end
    return trimmed
  end

  if valueType == 'number' or valueType == 'boolean' then
    return tostring(value)
  end

  return fallback
end

local function sanitizePayload(payload)
  if type(payload) ~= 'table' then return {} end

  local out = {}
  for key, value in pairs(payload) do
    if not isSensitiveKey(key) then
      if type(value) == 'table' then
        out[key] = sanitizePayload(value)
      elseif type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean' then
        out[key] = value
      end
    end
  end

  return out
end

local function isGlobalLogViewer(source)
  if not MZOrgService or not MZOrgService.hasGlobalPermission then
    return false
  end

  return MZOrgService.hasGlobalPermission(source, (Config and Config.OwnerAce) or 'group.mz_owner') == true
    or MZOrgService.hasGlobalPermission(source, 'staff.logs.view') == true
end

local function canViewOrgLogs(source, orgCode)
  if not orgCode or not MZOrgService or not MZOrgService.canOrg then
    return false
  end

  return isGlobalLogViewer(source)
    or MZOrgService.canOrg(source, orgCode, 'logs.view') == true
end

local function sanitizeFilters(filters)
  filters = type(filters) == 'table' and filters or {}

  return {
    orgCode = limitString(filters.orgCode or filters.org_code, 48),
    category = limitString(filters.category or filters.scope, 32),
    severity = limitString(filters.severity, 24),
    action = limitString(filters.action, 96),
    actor = limitString(filters.actor or filters.actorCitizenId, 96),
    auditId = limitString(filters.auditId or filters.audit_id, 96),
    auditOnly = filters.auditOnly == true,
    search = limitString(filters.search, 80),
    dateFrom = limitString(filters.dateFrom or filters.date_from, 32),
    dateTo = limitString(filters.dateTo or filters.date_to, 32),
    limit = sanitizeNumber(filters.limit, 50, 1, 100),
    offset = sanitizeNumber(filters.offset, 0, 0, 10000)
  }
end

local function decodeLogData(value)
  if not value or value == '' then return {} end
  if MZUtils and MZUtils.jsonDecode then
    return MZUtils.jsonDecode(value, {}) or {}
  end

  local ok, decoded = pcall(json.decode, value)
  return ok and type(decoded) == 'table' and decoded or {}
end

local function firstString(...)
  for i = 1, select('#', ...) do
    local value = select(i, ...)
    if type(value) == 'string' and value ~= '' then
      return value
    end
  end

  return nil
end

local function getOrgCodeFromData(data)
  data = type(data) == 'table' and data or {}
  local context = type(data.context) == 'table' and data.context or {}
  local meta = type(data.meta) == 'table' and data.meta or {}

  return firstString(
    data.orgCode,
    data.org_code,
    data.org,
    context.org_code,
    context.orgCode,
    meta.org_code,
    meta.orgCode
  )
end

local function getActorName(actor, fallback)
  actor = type(actor) == 'table' and actor or {}
  return firstString(actor.name, actor.label, actor.id, actor.citizenid, fallback)
end

local function getCitizenId(entity)
  entity = type(entity) == 'table' and entity or {}
  return firstString(entity.citizenid, entity.citizenId)
end

local function normalizeLogRow(row)
  local data = decodeLogData(row.data_json)
  local actor = type(data.actor) == 'table' and data.actor or {}
  local target = type(data.target) == 'table' and data.target or {}
  local meta = type(data.meta) == 'table' and data.meta or {}

  return {
    id = tonumber(row.id) or row.id,
    createdAt = row.created_at,
    category = tostring(row.scope or 'core'),
    action = tostring(row.action or 'unknown'),
    severity = firstString(data.severity, meta.severity) or 'info',
    scope = row.org_code and 'org' or 'global',
    orgCode = row.org_code,
    auditId = row.audit_id,
    actorName = getActorName(actor, row.actor),
    actorCitizenId = getCitizenId(actor),
    targetName = firstString(target.name, target.label, target.id, row.target),
    targetCitizenId = getCitizenId(target),
    message = firstString(data.message, meta.message),
    reason = firstString(data.reason, meta.reason),
    meta = sanitizePanelPayload(meta)
  }
end

local function buildLogQuery(filters, scopeKind, orgCode)
  local where = {}
  local params = {}

  if scopeKind == 'org' then
    where[#where + 1] = 'org_code = ?'
    params[#params + 1] = orgCode
  else
    where[#where + 1] = 'org_code IS NULL'
  end

  if filters.category then
    where[#where + 1] = 'scope = ?'
    params[#params + 1] = filters.category
  end

  if filters.action then
    where[#where + 1] = 'action = ?'
    params[#params + 1] = filters.action
  end

  if filters.actor then
    where[#where + 1] = 'actor = ?'
    params[#params + 1] = filters.actor
  end

  if filters.auditId then
    where[#where + 1] = 'audit_id = ?'
    params[#params + 1] = filters.auditId
  elseif filters.auditOnly then
    where[#where + 1] = 'audit_id IS NOT NULL'
  end

  if filters.search then
    local search = ('%%%s%%'):format(filters.search)
    where[#where + 1] = '(scope LIKE ? OR action LIKE ? OR actor LIKE ? OR target LIKE ? OR data_json LIKE ?)'
    params[#params + 1] = search
    params[#params + 1] = search
    params[#params + 1] = search
    params[#params + 1] = search
    params[#params + 1] = search
  end

  if filters.dateFrom then
    where[#where + 1] = 'created_at >= ?'
    params[#params + 1] = filters.dateFrom
  end

  if filters.dateTo then
    where[#where + 1] = 'created_at <= ?'
    params[#params + 1] = filters.dateTo
  end

  local sql = 'SELECT id, scope, action, actor, target, org_code, audit_id, data_json, created_at FROM mz_logs'
  if #where > 0 then
    sql = sql .. ' WHERE ' .. table.concat(where, ' AND ')
  end

  sql = sql .. ' ORDER BY id DESC LIMIT ? OFFSET ?'
  params[#params + 1] = filters.limit
  params[#params + 1] = filters.offset

  return sql, params
end

function MZLogService.normalizeActor(actor)
  if actor == nil then
    return 'system'
  end

  local actorType = type(actor)

  if actorType == 'number' then
    if actor == 0 then
      return 'console'
    end

    if MZPlayerService and MZPlayerService.getPlayer then
      local player = MZPlayerService.getPlayer(actor)
      if player and player.citizenid then
        return player.citizenid
      end
    end

    return ('source:%s'):format(actor)
  end

  if actorType == 'table' then
    if actor.citizenid then
      return tostring(actor.citizenid)
    end

    if actor.source then
      return MZLogService.normalizeActor(actor.source)
    end

    if actor.id then
      return tostring(actor.id)
    end
  end

  return normalizeScalar(actor, 'system')
end

function MZLogService.makeActor(actorType, actorId, extra)
  local actor = cloneTable(extra or {})
  actor.type = normalizeScalar(actorType, 'system')
  actor.id = normalizeScalar(actorId, 'system')
  return actor
end

function MZLogService.makeTarget(targetType, targetId, extra)
  local target = cloneTable(extra or {})
  target.type = normalizeScalar(targetType, 'unknown')
  target.id = normalizeScalar(targetId, 'unknown')
  return target
end

function MZLogService.create(scope, action, actor, target, data, options)
  data = type(data) == 'table' and data or {}
  options = type(options) == 'table' and options or {}
  local orgCode = limitString(options.orgCode or options.org_code or getOrgCodeFromData(data), 64)
  local auditId = limitString(options.auditId or options.audit_id, 96)

  return MySQL.insert.await([[
    INSERT INTO mz_logs (scope, action, actor, target, org_code, audit_id, data_json)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  ]], {
    normalizeScalar(scope, 'core'),
    normalizeScalar(action, 'unknown'),
    MZLogService.normalizeActor(actor),
    normalizeScalar(target, 'unknown'),
    orgCode,
    auditId,
    MZUtils.jsonEncode(sanitizePayload(data))
  })
end

function MZLogService.createDetailed(scope, action, payload)
  payload = sanitizePayload(payload)

  local actor = payload.actor or {}
  local target = payload.target or {}
  local context = payload.context or {}
  local before = payload.before or {}
  local after = payload.after or {}
  local meta = payload.meta or {}

  return MZLogService.create(
    scope,
    action,
    actor.id or actor.citizenid or actor.source or payload.actor_id or 'system',
    target.id or payload.target_id or 'unknown',
    {
      actor = actor,
      target = target,
      context = context,
      before = before,
      after = after,
      meta = meta
    },
    {
      orgCode = getOrgCodeFromData({ context = context }),
      auditId = payload.auditId or payload.audit_id
    }
  )
end

function MZLogService.listOrgLogsSecure(source, orgCode, filters)
  source = tonumber(source)
  if not source or source <= 0 then
    return false, 'invalid_source'
  end

  filters = sanitizeFilters(filters)
  orgCode = limitString(orgCode or filters.orgCode, 64)
  if not orgCode then return false, 'invalid_org' end
  if not MZOrgRepository or not MZOrgRepository.getOrgByCode or not MZOrgRepository.getOrgByCode(orgCode) then
    return false, 'invalid_org'
  end
  if not canViewOrgLogs(source, orgCode) then return false, 'forbidden' end

  local sql, params = buildLogQuery(filters, 'org', orgCode)
  local rows = MySQL.query.await(sql, params) or {}
  local result = {}

  for _, row in ipairs(rows) do
    local item = normalizeLogRow(row)
    if item.orgCode == orgCode and (not filters.severity or item.severity == filters.severity) then
      result[#result + 1] = item
    end
  end

  return result
end

function MZLogService.listGlobalLogsSecure(source, filters)
  source = tonumber(source)
  if not source or source <= 0 then return false, 'invalid_source' end
  if not isGlobalLogViewer(source) then return false, 'forbidden' end

  filters = sanitizeFilters(filters)
  filters.orgCode = nil
  local sql, params = buildLogQuery(filters, 'global')
  local rows = MySQL.query.await(sql, params) or {}
  local result = {}
  for _, row in ipairs(rows) do
    local item = normalizeLogRow(row)
    if item.orgCode == nil and (not filters.severity or item.severity == filters.severity) then
      result[#result + 1] = item
    end
  end
  return result
end

function MZLogService.listLogs(source, filters)
  filters = sanitizeFilters(filters)
  if filters.orgCode then
    return MZLogService.listOrgLogsSecure(source, filters.orgCode, filters)
  end
  return MZLogService.listGlobalLogsSecure(source, filters)
end
