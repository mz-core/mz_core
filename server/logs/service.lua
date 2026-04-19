MZLogService = {}

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
  if type(payload) ~= 'table' then
    return {}
  end

  return cloneTable(payload)
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