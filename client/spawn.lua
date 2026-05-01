local didFirstSpawn = false
local isSpawning = false

local function loadModel(model)
  if type(model) == 'string' then
    model = joaat(model)
  end

  if not IsModelInCdimage(model) or not IsModelValid(model) then
    return nil
  end

  RequestModel(model)

  local timeout = 0
  while not HasModelLoaded(model) and timeout < 200 do
    Wait(50)
    timeout = timeout + 1
  end

  if not HasModelLoaded(model) then
    return nil
  end

  return model
end

local function applyDefaultFreemodeSkin(ped)
  SetPedDefaultComponentVariation(ped)

  SetPedComponentVariation(ped, 3, 15, 0, 0) -- braços
  SetPedComponentVariation(ped, 4, 21, 0, 0) -- calça
  SetPedComponentVariation(ped, 6, 34, 0, 0) -- sapato
  SetPedComponentVariation(ped, 8, 15, 0, 0) -- undershirt
  SetPedComponentVariation(ped, 11, 15, 0, 0) -- torso

  ClearAllPedProps(ped)
end

local function doSpawn(spawnData)
  if isSpawning then return end
  isSpawning = true

  local model = loadModel(spawnData.model or 'mp_m_freemode_01')
  if not model then
    print('[mz_core] falha ao carregar modelo de spawn')
    isSpawning = false
    return
  end

  exports.spawnmanager:setAutoSpawn(false)

  SetPlayerModel(PlayerId(), model)
  SetModelAsNoLongerNeeded(model)

  Wait(100)

  local spawn = {
    x = spawnData.x,
    y = spawnData.y,
    z = spawnData.z,
    heading = spawnData.heading or 0.0,
    model = model,
    skipFade = false
  }

  exports.spawnmanager:spawnPlayer(spawn, function()
    local ped = PlayerPedId()

    NetworkResurrectLocalPlayer(spawn.x, spawn.y, spawn.z, spawn.heading or 0.0, true, true, false)

    SetEntityCoordsNoOffset(ped, spawn.x, spawn.y, spawn.z, false, false, false)
    SetEntityHeading(ped, spawn.heading or 0.0)

    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)

    SetPlayerInvincible(PlayerId(), false)
    SetEntityInvincible(ped, false)
    ClearPedTasksImmediately(ped)
    ClearPlayerWantedLevel(PlayerId())

    if GetEntityModel(ped) == joaat('mp_m_freemode_01') or GetEntityModel(ped) == joaat('mp_f_freemode_01') then
      applyDefaultFreemodeSkin(ped)
    end

    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    TriggerEvent('playerSpawned', spawn)
    TriggerServerEvent('mz_core:vehicles:server:playerWorldReady')

    didFirstSpawn = true
    isSpawning = false
  end)
end

RegisterNetEvent('mz_core:client:spawnPlayer', function(spawnData)
  doSpawn(spawnData)
end)

RegisterNetEvent('mz_core:client:playerLoaded', function(playerData)
  MZClient.PlayerData = playerData
  MZClient.PlayerSession = playerData and playerData.session or nil

  if didFirstSpawn then return end

  CreateThread(function()
    Wait(500)
    local spawnData = lib.callback.await('mz_core:server:getSpawnData', false)
    if spawnData then
      doSpawn(spawnData)
    end
  end)
end)


-----


CreateThread(function()
  while true do
    Wait(30000)

    if didFirstSpawn then
      local ped = PlayerPedId()
      if ped and ped ~= 0 and DoesEntityExist(ped) then
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)

        TriggerServerEvent('mz_core:server:savePosition', {
          x = coords.x,
          y = coords.y,
          z = coords.z,
          heading = heading
        })
      end
    end
  end
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then return end
  if not didFirstSpawn then return end

  local ped = PlayerPedId()
  if ped and ped ~= 0 and DoesEntityExist(ped) then
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    TriggerServerEvent('mz_core:server:savePosition', {
      x = coords.x,
      y = coords.y,
      z = coords.z,
      heading = heading
    })
  end
end)
