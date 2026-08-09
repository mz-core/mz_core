local PLAYER_LOAD_READY_TIMEOUT_MS = 60000
local PLAYER_LOAD_READY_WAIT_MS = 250
local LoadingPlayers = {}
local PositionSaveAttempts = {}
local PositionRejectionAudit = {}
local POSITION_SAVE_INTERVAL_MS = 10000
local POSITION_MAX_CLIENT_DRIFT = 75.0

local function isCoreReady()
  return MZCoreState and MZCoreState.ready == true
end

local function waitForCoreReady(timeoutMs)
  if isCoreReady() then
    return true
  end

  local timeout = tonumber(timeoutMs) or PLAYER_LOAD_READY_TIMEOUT_MS
  local started = GetGameTimer()

  while not isCoreReady() do
    if MZCoreState and MZCoreState.prepareDone == true and MZCoreState.prepareOk ~= true then
      return false, 'core_prepare_failed'
    end

    if MZCoreState and MZCoreState.seedDone == true and MZCoreState.seedOk ~= true then
      return false, 'core_seed_failed'
    end

    if GetGameTimer() - started >= timeout then
      return false, 'core_not_ready_timeout'
    end

    Wait(PLAYER_LOAD_READY_WAIT_MS)
  end

  return true
end

local function finiteNumber(value)
  return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function validPositionCandidate(coords)
  if type(coords) ~= 'table' then return false end
  local allowed = { x = true, y = true, z = true, heading = true }
  for key in pairs(coords) do
    if allowed[key] ~= true then return false end
  end
  return finiteNumber(coords.x)
    and finiteNumber(coords.y)
    and finiteNumber(coords.z)
    and (coords.heading == nil or finiteNumber(coords.heading))
end

local function validPositionSession(src)
  if not MZPlayerService or not MZPlayerService.isPlayerLoaded or not MZPlayerService.isPlayerLoaded(src) then
    return false, 'player_not_loaded'
  end

  local player = MZPlayerService.getPlayer and MZPlayerService.getPlayer(src) or nil
  local session = MZPlayerService.getPlayerSession and MZPlayerService.getPlayerSession(src) or nil
  if type(player) ~= 'table' or type(session) ~= 'table'
    or session.isActive ~= true
    or tonumber(session.source) ~= src
    or tostring(session.citizenid or '') ~= tostring(player.citizenid or '') then
    return false, 'invalid_session'
  end
  return true
end

local function auditPositionRejection(src, reason, operation)
  local now = type(GetGameTimer) == 'function' and GetGameTimer() or math.floor(os.clock() * 1000)
  local key = ('%s:%s'):format(tostring(src), tostring(reason))
  local previous = PositionRejectionAudit[key]
  if previous and now >= previous and now - previous < 30000 then return end
  PositionRejectionAudit[key] = now

  if MZLogService and MZLogService.createDetailed then
    pcall(MZLogService.createDetailed, 'player', 'position_save_rejected', {
      actor = { type = 'player', id = ('source:%s'):format(src), source = src },
      target = { type = 'position', id = ('source:%s'):format(src) },
      context = { source = src, operation = operation or 'periodic' },
      after = { persisted = false },
      meta = { result = 'rejected', reason = reason }
    })
  end
end

local function observedServerPosition(src)
  if type(GetPlayerPed) ~= 'function' or type(GetEntityCoords) ~= 'function' then
    return nil, 'server_position_unavailable'
  end

  local ped = GetPlayerPed(src)
  if not ped or ped == 0 or (type(DoesEntityExist) == 'function' and not DoesEntityExist(ped)) then
    return nil, 'player_entity_unavailable'
  end

  local coords = GetEntityCoords(ped)
  local heading = type(GetEntityHeading) == 'function' and GetEntityHeading(ped) or 0.0
  local observed = {
    x = coords and coords.x,
    y = coords and coords.y,
    z = coords and coords.z,
    heading = heading
  }
  if not validPositionCandidate(observed)
    or math.abs(observed.x) > 20000.0
    or math.abs(observed.y) > 20000.0
    or observed.z < -2000.0
    or observed.z > 3000.0 then
    return nil, 'invalid_server_position'
  end

  observed.heading = observed.heading % 360.0
  return observed
end

local function persistObservedPosition(src, candidate, operation, rateLimited)
  src = tonumber(src)
  if not src or src <= 0 or src % 1 ~= 0 then return false, 'invalid_source' end

  local function reject(reason)
    if candidate ~= nil then auditPositionRejection(src, reason, operation) end
    return false, reason
  end

  local sessionOk, sessionErr = validPositionSession(src)
  if not sessionOk then
    return reject(sessionErr)
  end

  if rateLimited then
    local now = type(GetGameTimer) == 'function' and GetGameTimer() or math.floor(os.clock() * 1000)
    local previous = PositionSaveAttempts[src]
    PositionSaveAttempts[src] = now
    if previous and now >= previous and now - previous < POSITION_SAVE_INTERVAL_MS then
      return reject('rate_limited')
    end
  end

  if candidate ~= nil and not validPositionCandidate(candidate) then
    return reject('invalid_coords')
  end

  local observed, observedErr = observedServerPosition(src)
  if not observed then
    return reject(observedErr)
  end

  if candidate then
    local dx = candidate.x - observed.x
    local dy = candidate.y - observed.y
    local dz = candidate.z - observed.z
    if dx * dx + dy * dy + dz * dz > POSITION_MAX_CLIENT_DRIFT * POSITION_MAX_CLIENT_DRIFT then
      return reject('client_position_mismatch')
    end
  end

  return MZPlayerService.savePosition(src, observed)
end

local function scheduleLoadPlayer(src, reason)
  src = tonumber(src)
  if not src or src <= 0 then
    return
  end

  if LoadingPlayers[src] then
    return
  end

  LoadingPlayers[src] = true

  CreateThread(function()
    local ready, readyErr = waitForCoreReady(PLAYER_LOAD_READY_TIMEOUT_MS)
    if not ready then
      LoadingPlayers[src] = nil
      print(('[mz_core] failed to load player source %s name=%s stage=waitForCoreReady error=%s reason=%s'):format(
        tostring(src),
        tostring(GetPlayerName(src) or 'unknown'),
        tostring(readyErr),
        tostring(reason or 'unknown')
      ))
      return
    end

    if not GetPlayerName(src) then
      LoadingPlayers[src] = nil
      return
    end

    local ok, playerData, loadErr = xpcall(function()
      return MZPlayerService.loadPlayer(src)
    end, debug.traceback)

    if not ok then
      LoadingPlayers[src] = nil
      print(('[mz_core] failed to load player source %s name=%s stage=loadPlayer error=%s reason=%s'):format(
        tostring(src),
        tostring(GetPlayerName(src) or 'unknown'),
        tostring(playerData),
        tostring(reason or 'unknown')
      ))
      return
    end

    if not playerData then
      LoadingPlayers[src] = nil
      print(('[mz_core] failed to load player source %s name=%s stage=loadPlayer error=%s reason=%s'):format(
        tostring(src),
        tostring(GetPlayerName(src) or 'unknown'),
        tostring(loadErr or 'unknown'),
        tostring(reason or 'unknown')
      ))
      print(debug.traceback())
      return
    end

    local orgOk, orgErr = xpcall(function()
      MZOrgService.loadPlayerOrgs(src)
    end, debug.traceback)

    if not orgOk then
      LoadingPlayers[src] = nil
      print(('[mz_core] failed to load player orgs source %s name=%s error=%s reason=%s'):format(
        tostring(src),
        tostring(GetPlayerName(src) or 'unknown'),
        tostring(orgErr),
        tostring(reason or 'unknown')
      ))
      return
    end

    local identityOk, syncIdentity = MZPlayerStateService.getSyncIdentity(src)
    TriggerClientEvent(
      'mz_core:client:playerLoaded',
      src,
      playerData,
      identityOk and syncIdentity.sessionToken or nil
    )
    local syncResult = MZPlayerStateSyncService.sync(src, 'player_loaded', {
      forcePhysicalApply = true,
      sessionReset = true
    })
    if syncResult.ok ~= true then
      print(('[mz_core][player_state][initial_sync_failed] source=%s code=%s'):format(
        tostring(src), tostring(syncResult.code)
      ))
    end

    CreateThread(function()
      Wait(5000)
      local cfg = Config and Config.VehicleWorld or {}
      if cfg.restoreOnPlayerJoin == true and GetPlayerName(src) and MZVehicleService and MZVehicleService.restoreWorldVehiclesForPlayer then
        MZVehicleService.restoreWorldVehiclesForPlayer(src, 'player_loaded')
      elseif cfg.debug == true then
        print(('[mz_vehicle_world] vehicle_restore_auto_disabled reason=player_loaded source=%s'):format(tostring(src)))
      end
    end)

    LoadingPlayers[src] = nil
  end)
end

AddEventHandler('playerJoining', function()
  scheduleLoadPlayer(source, 'playerJoining')
end)

AddEventHandler('onResourceStart', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then
    return
  end

  CreateThread(function()
    Wait(1000)
    for _, src in ipairs(GetPlayers()) do
      scheduleLoadPlayer(src, 'resource_start')
    end
  end)
end)

RegisterNetEvent('mz_core:server:savePosition', function(coords)
  local src = source
  persistObservedPosition(src, coords, 'client_periodic', true)
end)

AddEventHandler('playerDropped', function(reason)
  persistObservedPosition(source, nil, 'player_dropped', false)
  LoadingPlayers[source] = nil
  local sourceId = tonumber(source)
  PositionSaveAttempts[sourceId] = nil
  for key in pairs(PositionRejectionAudit) do
    if key:find(('^%s:'):format(sourceId)) then PositionRejectionAudit[key] = nil end
  end

  local stateFlushOk, stateFlushResult = MZPlayerStateService.beginUnload(source, reason or 'player_dropped')

  if MZInventoryService and MZInventoryService.handlePlayerDropped then
    MZInventoryService.handlePlayerDropped(source, reason)
  end

  MZPlayerService.unloadPlayer(source, reason, true, stateFlushOk, stateFlushResult)
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then
    return
  end

  MZPlayerStateService.beginShutdown()

  local loadedSources = {}
  for src, _ in pairs(MZCache.playersBySource or {}) do
    loadedSources[#loadedSources + 1] = src
  end

  table.sort(loadedSources)

  local flushSucceeded, flushFailed = 0, 0
  for _, src in ipairs(loadedSources) do
    persistObservedPosition(src, nil, 'resource_stop', false)
    local stateFlushOk, stateFlushResult = MZPlayerStateService.beginUnload(src, 'resource_stop')
    if stateFlushOk then flushSucceeded = flushSucceeded + 1 else flushFailed = flushFailed + 1 end

    if MZInventoryService and MZInventoryService.handlePlayerDropped then
      MZInventoryService.handlePlayerDropped(src, 'resource_stop')
    end

    MZPlayerService.unloadPlayer(src, 'resource_stop', true, stateFlushOk, stateFlushResult)
  end


  MZPlayerStateService.clearRuntime()
  print(('[mz_core][player_state][resource_stop_flush] total=%s succeeded=%s failed=%s'):format(
    tostring(#loadedSources), tostring(flushSucceeded), tostring(flushFailed)
  ))

  if MZLogService and MZLogService.createDetailed then
    pcall(MZLogService.createDetailed, 'player_state', 'resource_stop_flush', {
      actor = { type = 'resource', id = GetCurrentResourceName() },
      target = { type = 'player_state_runtime', id = 'all' },
      context = { operation = 'resource_stop_flush', timestamp = os.time() },
      after = { total = #loadedSources, succeeded = flushSucceeded, failed = flushFailed },
      meta = { result = flushFailed == 0 and 'success' or 'partial_failure' }
    })
  end
end)
