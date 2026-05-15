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
    or MZOrgService.hasGlobalPermission(source, 'staff.orgs.manage') == true
end

local function canViewOrgLogs(source, orgCode)
  if not orgCode or not MZOrgService or not MZOrgService.canOrg then
    return false
  end

  return MZOrgService.canOrg(source, orgCode, 'logs.view') == true
end

local function sanitizeFilters(filters)
  filters = type(filters) == 'table' and filters or {}

  return {
    orgCode = limitString(filters.orgCode or filters.org_code, 48),
    category = limitString(filters.category or filters.scope, 32),
    severity = limitString(filters.severity, 24),
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
    orgCode = getOrgCodeFromData(data),
    actorName = getActorName(actor, row.actor),
    actorCitizenId = getCitizenId(actor),
    targetName = firstString(target.name, target.label, target.id, row.target),
    targetCitizenId = getCitizenId(target),
    message = firstString(data.message, meta.message),
    reason = firstString(data.reason, meta.reason),
    meta = sanitizePanelPayload(meta)
  }
end

local function buildLogQuery(filters, canViewGlobal)
  local where = {}
  local params = {}

  if filters.category then
    where[#where + 1] = 'scope = ?'
    params[#params + 1] = filters.category
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

  if filters.orgCode then
    where[#where + 1] = '(target LIKE ? OR data_json LIKE ?)'
    params[#params + 1] = ('%%%s%%'):format(filters.orgCode)
    params[#params + 1] = ('%%%s%%'):format(filters.orgCode)
  elseif not canViewGlobal then
    where[#where + 1] = '1 = 0'
  end

  local sql = 'SELECT id, scope, action, actor, target, data_json, created_at FROM mz_logs'
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

function MZLogService.create(scope, action, actor, target, data)
  MySQL.insert.await([[
    INSERT INTO mz_logs (scope, action, actor, target, data_json)
    VALUES (?, ?, ?, ?, ?)
  ]], {
    normalizeScalar(scope, 'core'),
    normalizeScalar(action, 'unknown'),
    MZLogService.normalizeActor(actor),
    normalizeScalar(target, 'unknown'),
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
    }
  )
end

function MZLogService.listLogs(source, filters)
  source = tonumber(source)
  if not source or source <= 0 then
    return false, 'invalid_source'
  end

  filters = sanitizeFilters(filters)

  local canViewGlobal = isGlobalLogViewer(source)
  if not canViewGlobal and not canViewOrgLogs(source, filters.orgCode) then
    return false, 'forbidden'
  end

  local sql, params = buildLogQuery(filters, canViewGlobal)
  local rows = MySQL.query.await(sql, params) or {}
  local result = {}

  for _, row in ipairs(rows) do
    local item = normalizeLogRow(row)
    if (not filters.orgCode or item.orgCode == filters.orgCode or tostring(row.target or ''):find(filters.orgCode, 1, true)) then
      if (not filters.severity or item.severity == filters.severity) then
        result[#result + 1] = item
      end
    end
  end

  return result
end
