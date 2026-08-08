local StagingWindows = {}

local function stagingConfig()
  return Config and Config.PlayerStates and Config.PlayerStates.staging or {}
end

local function enabled()
  local name = tostring(stagingConfig().convar or 'mz_player_state_staging')
  return type(GetConvarInt) == 'function' and GetConvarInt(name, 0) == 1
end

local function allowed(source)
  if not enabled() then return false, 'staging_disabled' end
  source = tonumber(source) or 0
  if source == 0 then return true end
  local ace = tostring(stagingConfig().ace or 'mz.player_state.staging')
  if type(IsPlayerAceAllowed) == 'function' and IsPlayerAceAllowed(source, ace) then return true end
  return false, 'not_authorized'
end

local function consume(source)
  source = tonumber(source) or 0
  local current = type(GetGameTimer) == 'function' and GetGameTimer() or math.floor(os.clock() * 1000)
  local cfg = stagingConfig()
  local windowMs = math.max(1000, math.floor(tonumber(cfg.windowMs) or 10000))
  local maximum = math.max(1, math.floor(tonumber(cfg.maximumPerWindow) or 12))
  local window = StagingWindows[source]
  if not window or current - window.startedAt >= windowMs then
    window = { startedAt = current, count = 0 }
    StagingWindows[source] = window
  end
  window.count = window.count + 1
  return window.count <= maximum
end

local function reply(source, message)
  message = tostring(message or '')
  if tonumber(source) == 0 then print(('[mz_core][state_staging] %s'):format(message)); return end
  TriggerClientEvent('chat:addMessage', source, { args = { 'MZ State', message } })
end

local function authorizeCommand(source, name)
  local ok, err = allowed(source)
  if not ok then reply(source, ('%s: %s'):format(name, err)); return false end
  if not consume(source) then
    reply(source, ('%s: rate_limited'):format(name))
    if MZPlayerStateObservability then
      MZPlayerStateObservability.record('player_state_rate_limited', {
        source = tonumber(source), reason = 'staging_command', result = 'rejected', error = name
      }, 'mz_core')
    end
    return false
  end
  return true
end

local function targetFrom(args)
  local target = tonumber(type(args) == 'table' and args[1] or nil)
  if not target or target <= 0 or not GetPlayerName(target) then return nil end
  return math.floor(target)
end

local function encode(value)
  if json and type(json.encode) == 'function' then
    local ok, result = pcall(json.encode, value)
    if ok then return result end
  end
  return tostring(value)
end

RegisterCommand('mz_state_diag', function(source, args)
  if not authorizeCommand(source, 'mz_state_diag') then return end
  local target = targetFrom(args)
  if not target then return reply(source, 'uso: mz_state_diag <source>') end
  local ok, result = MZPlayerStateService.getState(target)
  reply(source, encode(ok and result or { ok = false, error = result and result.code }))
end, false)

RegisterCommand('mz_state_runtime', function(source, args)
  if not authorizeCommand(source, 'mz_state_runtime') then return end
  local target = targetFrom(args)
  if not target then return reply(source, 'uso: mz_state_runtime <source>') end
  local stateOk, stateResult = MZPlayerStateService.getState(target)
  local identityOk, identityResult = MZPlayerStateService.getRuntimeIdentity(target)
  reply(source, encode({
    source = target,
    state = {
      ok = stateOk == true,
      error = stateOk == true and nil or (stateResult and stateResult.code),
      revision = stateOk == true and stateResult.revision or nil
    },
    runtimeIdentity = {
      ok = identityOk == true,
      error = identityOk == true and nil or (identityResult and identityResult.code),
      sessionId = identityOk == true and identityResult.sessionId or nil,
      revision = identityOk == true and identityResult.revision or nil
    }
  }))
end, false)

RegisterCommand('mz_state_bags', function(source, args)
  if not authorizeCommand(source, 'mz_state_bags') then return end
  local target = targetFrom(args)
  if not target then return reply(source, 'uso: mz_state_bags <source>') end
  local payload = { source = target }
  if type(Player) == 'function' then
    local ok, player = pcall(Player, target)
    local state = ok and player and player.state or nil
    for _, key in ipairs({ 'mz:loaded', 'mz:stateRevision', 'mz:deathState', 'mz:isDead', 'mz:isDowned', 'mz:isRespawning', 'mz:inventoryBlocked', 'mz:weaponBlocked', 'mz:interactionBlocked' }) do
      local value
      if state then value = state[key] end
      if value == nil then
        payload[key] = '<missing>'
      elseif value == false then
        payload[key] = '<false>'
      else
        payload[key] = value
      end
    end
  end
  reply(source, encode(payload))
end, false)

local function transitionCommand(command, handler)
  RegisterCommand(command, function(source, args)
    if not authorizeCommand(source, command) then return end
    local target = targetFrom(args)
    if not target then return reply(source, ('uso: %s <source>'):format(command)) end
    local ok, result = handler(target, MZPlayerStateService.internalContext('staging_command', {
      actorSource = tonumber(source) or 0,
      administrative = command == 'mz_state_revive'
    }))
    reply(source, encode({ ok = ok == true, result = result }))
  end, false)
end

transitionCommand('mz_state_down', MZPlayerStateService.markDowned)
transitionCommand('mz_state_dead', MZPlayerStateService.markDead)
transitionCommand('mz_state_revive', MZPlayerStateService.revive)

RegisterCommand('mz_status_set', function(source, args)
  if not authorizeCommand(source, 'mz_status_set') then return end
  local target = targetFrom(args)
  local statusName = tostring(type(args) == 'table' and args[2] or '')
  local value = tonumber(type(args) == 'table' and args[3] or nil)
  if not target or value == nil then return reply(source, 'uso: mz_status_set <source> <status> <value>') end
  local ok, result = MZPlayerStateService.setStatus(target, statusName, value, MZPlayerStateService.internalContext('staging_status', {
    actorSource = tonumber(source) or 0
  }))
  reply(source, encode({ ok = ok == true, result = result }))
end, false)

RegisterCommand('mz_state_metrics', function(source)
  if not authorizeCommand(source, 'mz_state_metrics') then return end
  reply(source, encode(MZPlayerStateObservability and MZPlayerStateObservability.snapshot() or { error = 'unavailable' }))
end, false)

RegisterCommand('mz_medical_diag', function(source, args)
  if not authorizeCommand(source, 'mz_medical_diag') then return end
  local target = targetFrom(args)
  if not target then return reply(source, 'uso: mz_medical_diag <source>') end
  if GetResourceState('mz_medical') ~= 'started' then return reply(source, 'mz_medical: unavailable') end
  local callOk, ok, result = pcall(function() return exports['mz_medical']:GetMedicalState(target) end)
  reply(source, encode({ ok = callOk and ok == true, result = callOk and result or 'export_failed' }))
end, false)

RegisterCommand('mz_medical_ops', function(source)
  if not authorizeCommand(source, 'mz_medical_ops') then return end
  if GetResourceState('mz_medical') ~= 'started' then return reply(source, 'mz_medical: unavailable') end
  local callOk, ok, result = pcall(function() return exports['mz_medical']:GetMedicalOperations() end)
  reply(source, encode({ ok = callOk and ok == true, result = callOk and result or 'export_failed' }))
end, false)

RegisterCommand('mz_medical_recover', function(source, args)
  if not authorizeCommand(source, 'mz_medical_recover') then return end
  local operationId = tostring(type(args) == 'table' and args[1] or '')
  if operationId == '' or #operationId > 128 then return reply(source, 'uso: mz_medical_recover <operationId>') end
  if GetResourceState('mz_medical') ~= 'started' then return reply(source, 'mz_medical: unavailable') end
  local callOk, ok, result = pcall(function() return exports['mz_medical']:RecoverMedicalOperation(operationId) end)
  reply(source, encode({ ok = callOk and ok == true, result = callOk and result or 'export_failed' }))
end, false)

AddEventHandler('playerDropped', function()
  StagingWindows[tonumber(source)] = nil
end)
