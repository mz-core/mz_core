local PLAYER_LOAD_READY_TIMEOUT_MS = 60000
local PLAYER_LOAD_READY_WAIT_MS = 250
local LoadingPlayers = {}

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

    TriggerClientEvent('mz_core:client:playerLoaded', src, playerData)
    MZPlayerHUDService.syncToClient(src)

    CreateThread(function()
      Wait(5000)
      if GetPlayerName(src) and MZVehicleService and MZVehicleService.restoreWorldVehiclesForPlayer then
        MZVehicleService.restoreWorldVehiclesForPlayer(src, 'player_loaded')
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
  if type(coords) ~= 'table' then return end
  if type(coords.x) ~= 'number' then return end
  if type(coords.y) ~= 'number' then return end
  if type(coords.z) ~= 'number' then return end
  if coords.heading ~= nil and type(coords.heading) ~= 'number' then return end

  MZPlayerService.savePosition(src, coords)
end)

AddEventHandler('playerDropped', function(reason)
  LoadingPlayers[source] = nil

  if MZInventoryService and MZInventoryService.handlePlayerDropped then
    MZInventoryService.handlePlayerDropped(source, reason)
  end

  MZPlayerService.unloadPlayer(source, reason)
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then
    return
  end

  local loadedSources = {}
  for src, _ in pairs(MZCache.playersBySource or {}) do
    loadedSources[#loadedSources + 1] = src
  end

  table.sort(loadedSources)

  for _, src in ipairs(loadedSources) do
    if MZInventoryService and MZInventoryService.handlePlayerDropped then
      MZInventoryService.handlePlayerDropped(src, 'resource_stop')
    end

    MZPlayerService.unloadPlayer(src, 'resource_stop')
  end
end)
