local AppliedWorldProps = {}

local function NormalizePlate(plate)
  return tostring(plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
end

local function getVehicleWorldConfig()
  return Config.VehicleWorld or {}
end

local function getEntityFromBagName(bagName)
  if type(GetEntityFromStateBagName) ~= 'function' then
    return 0
  end

  local entity = GetEntityFromStateBagName(bagName)
  if entity and entity ~= 0 and DoesEntityExist(entity) then
    return entity
  end

  return 0
end

local function requestControl(entity, timeoutMs)
  if not entity or entity == 0 or not DoesEntityExist(entity) then
    return false
  end

  local timeoutAt = GetGameTimer() + (tonumber(timeoutMs) or 1500)
  repeat
    if NetworkHasControlOfEntity(entity) then
      return true
    end

    NetworkRequestControlOfEntity(entity)
    Wait(0)
  until GetGameTimer() > timeoutAt

  return NetworkHasControlOfEntity(entity)
end

local function loadVehicleModel(model)
  if GetResourceState('mz_vehicles') == 'started' then
    local ok, exportOk, modelHash = pcall(function()
      return exports['mz_vehicles']:LoadModel(model)
    end)

    if ok and exportOk == true and modelHash then
      return tonumber(modelHash) or modelHash
    end
  end

  local modelHash = type(model) == 'number' and model or GetHashKey(tostring(model or ''))
  if not modelHash or modelHash == 0 or not IsModelInCdimage(modelHash) then
    return nil, 'invalid_model'
  end

  RequestModel(modelHash)
  local timeoutAt = GetGameTimer() + 5000
  while not HasModelLoaded(modelHash) and GetGameTimer() < timeoutAt do
    Wait(0)
  end

  if not HasModelLoaded(modelHash) then
    return nil, 'model_load_timeout'
  end

  return modelHash
end

local function findVehicleByPlate(plate)
  plate = NormalizePlate(plate)
  if plate == '' then
    return 0
  end

  for _, vehicle in ipairs(GetGamePool('CVehicle')) do
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
      local vehiclePlate = NormalizePlate(GetVehicleNumberPlateText(vehicle))
      local state = Entity(vehicle).state
      if vehiclePlate == plate or (state and NormalizePlate(state.mz_plate) == plate) then
        return vehicle
      end
    end
  end

  return 0
end

local function finalizeWorldVehicle(vehicle, data)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return false, 'entity_not_found'
  end

  data = type(data) == 'table' and data or {}
  local world = type(data.world) == 'table' and data.world or {}
  local plate = NormalizePlate(data.plate)
  local locked = world.locked == true or data.locked == true

  if plate ~= '' then
    SetVehicleNumberPlateText(vehicle, plate)
  end

  requestControl(vehicle, 1500)

  if GetResourceState('mz_vehicles') == 'started' and type(data.props) == 'table' then
    pcall(function()
      exports['mz_vehicles']:SetVehicleProperties(vehicle, data.props)
    end)
  end

  SetVehicleFuelLevel(vehicle, (tonumber(data.fuel) or 100) + 0.0)
  SetVehicleEngineHealth(vehicle, (tonumber(data.engine) or 1000) + 0.0)
  SetVehicleBodyHealth(vehicle, (tonumber(data.body) or 1000) + 0.0)
  SetVehicleDoorsLocked(vehicle, locked and 2 or 1)
  SetVehicleDoorsLockedForAllPlayers(vehicle, locked)
  SetVehicleOnGroundProperly(vehicle)

  local state = Entity(vehicle).state
  if state then
    state:set('mz_plate', plate, true)
    state:set('mz_persistent', true, true)
    if tonumber(data.id or data.vehicle_id) then
      state:set('mz_vehicle_id', tonumber(data.id or data.vehicle_id), true)
    end
    if data.owner_type ~= nil and tostring(data.owner_type) ~= '' then
      state:set('mz_owner_type', tostring(data.owner_type), true)
    end
    if data.owner_id ~= nil and tostring(data.owner_id) ~= '' then
      state:set('mz_owner_id', tostring(data.owner_id), true)
    end
    state:set('mz_locked', locked, true)
    state:set('mz_lock_state', locked and 2 or 1, true)
    state:set('mz_world_props', type(data.props) == 'table' and data.props or {}, true)
    state:set('mz_world_condition', {
      fuel = tonumber(data.fuel) or 100,
      engine = tonumber(data.engine) or 1000,
      body = tonumber(data.body) or 1000,
      locked = locked,
      destroyed = world.destroyed == true or data.destroyed == true
    }, true)
  end

  return true
end

local function captureWorldSnapshot(vehicle)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return nil
  end

  local coords = GetEntityCoords(vehicle)
  return {
    plate = NormalizePlate(GetVehicleNumberPlateText(vehicle)),
    coords = {
      x = tonumber(coords.x) or 0.0,
      y = tonumber(coords.y) or 0.0,
      z = tonumber(coords.z) or 0.0
    },
    heading = GetEntityHeading(vehicle),
    fuel = GetVehicleFuelLevel(vehicle),
    engine = GetVehicleEngineHealth(vehicle),
    body = GetVehicleBodyHealth(vehicle),
    locked = GetVehicleDoorLockStatus(vehicle),
    net_id = NetworkGetNetworkIdFromEntity(vehicle)
  }
end

local function applyWorldVehicleState(vehicle)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return false
  end

  local state = Entity(vehicle).state
  if not state or state.mz_persistent ~= true then
    return false
  end

  local plate = tostring(state.mz_plate or '')
  local props = type(state.mz_world_props) == 'table' and state.mz_world_props or nil
  local condition = type(state.mz_world_condition) == 'table' and state.mz_world_condition or {}
  local locked = condition.locked
  if locked == nil then
    locked = state.mz_locked == true
  else
    locked = locked == true
  end

  requestControl(vehicle, 1200)

  if GetResourceState('mz_vehicles') == 'started' and props then
    pcall(function()
      exports['mz_vehicles']:SetVehicleProperties(vehicle, props)
    end)
  end

  if plate ~= '' then
    SetVehicleNumberPlateText(vehicle, plate)
  end

  SetVehicleFuelLevel(vehicle, (tonumber(condition.fuel) or 100) + 0.0)
  SetVehicleEngineHealth(vehicle, (tonumber(condition.engine) or 1000) + 0.0)
  SetVehicleBodyHealth(vehicle, (tonumber(condition.body) or 1000) + 0.0)
  SetVehicleDoorsLocked(vehicle, locked and 2 or 1)
  SetVehicleDoorsLockedForAllPlayers(vehicle, locked)
  SetVehicleOnGroundProperly(vehicle)

  AppliedWorldProps[vehicle] = GetGameTimer()
  return true
end

RegisterNetEvent('mz_core:vehicles:client:restoreWorldVehicle', function(data)
  if type(data) ~= 'table' then
    return
  end

  local plate = NormalizePlate(data.plate)
  if plate == '' then
    print('[mz_vehicle_world] respawn failed  invalid_plate')
    return
  end

  local existing = findVehicleByPlate(plate)
  if existing ~= 0 then
    finalizeWorldVehicle(existing, data)
    local snapshot = captureWorldSnapshot(existing)
    TriggerServerEvent('mz_core:vehicles:server:restoreWorldVehicleSpawned', plate, snapshot and snapshot.net_id or 0, snapshot or {})
    print(('[mz_vehicle_world] respawn success %s %s'):format(plate, tostring(snapshot and snapshot.net_id or 0)))
    return
  end

  local world = type(data.world) == 'table' and data.world or {}
  local coords = type(world.last_coords) == 'table' and world.last_coords or nil
  if not coords or coords.x == nil or coords.y == nil or coords.z == nil then
    print(('[mz_vehicle_world] respawn failed %s missing_coords'):format(plate))
    return
  end

  print(('[mz_vehicle_world] respawn attempt %s %s %.3f %.3f %.3f'):format(
    plate,
    tostring(data.model or ''),
    tonumber(coords.x) or 0.0,
    tonumber(coords.y) or 0.0,
    tonumber(coords.z) or 0.0
  ))

  local modelHash, modelErr = loadVehicleModel(data.model)
  if not modelHash then
    print(('[mz_vehicle_world] respawn failed %s %s'):format(plate, tostring(modelErr or 'invalid_model')))
    return
  end

  local vehicle = 0
  if GetResourceState('mz_vehicles') == 'started' then
    local ok, spawnOk, result = pcall(function()
      return exports['mz_vehicles']:SpawnVehicleEntity({
        vehicle_model = tostring(data.model or ''),
        model_hash = modelHash,
        spawn_point = {
          x = tonumber(coords.x) or 0.0,
          y = tonumber(coords.y) or 0.0,
          z = tonumber(coords.z) or 0.0,
          w = tonumber(world.last_heading) or 0.0
        },
        props = type(data.props) == 'table' and data.props or {},
        plate = plate,
        fuel = tonumber(data.fuel) or 100,
        engine = tonumber(data.engine) or 1000,
        body = tonumber(data.body) or 1000,
        warp_into_vehicle = false,
        engine_on = false
      })
    end)

    if ok and spawnOk == true and type(result) == 'table' and result.vehicle then
      vehicle = result.vehicle
    end
  end

  if vehicle == 0 then
    vehicle = CreateVehicle(
      modelHash,
      (tonumber(coords.x) or 0.0) + 0.0,
      (tonumber(coords.y) or 0.0) + 0.0,
      (tonumber(coords.z) or 0.0) + 0.0,
      (tonumber(world.last_heading) or 0.0) + 0.0,
      true,
      false
    )
  end

  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    print(('[mz_vehicle_world] respawn failed %s spawn_failed'):format(plate))
    return
  end

  SetEntityAsMissionEntity(vehicle, true, true)
  finalizeWorldVehicle(vehicle, data)

  local snapshot = captureWorldSnapshot(vehicle) or {}
  TriggerServerEvent('mz_core:vehicles:server:restoreWorldVehicleSpawned', plate, snapshot.net_id or 0, snapshot)
  print(('[mz_vehicle_world] respawn success %s %s'):format(plate, tostring(snapshot.net_id or 0)))
end)

RegisterNetEvent('mz_core:vehicles:client:deleteWorldVehicleNet', function(netId)
  netId = tonumber(netId) or 0
  if netId <= 0 or not NetworkDoesNetworkIdExist(netId) then
    return
  end

  local vehicle = NetworkGetEntityFromNetworkId(netId)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    return
  end

  requestControl(vehicle, 1500)
  DeleteEntity(vehicle)
end)

local function scheduleApplyFromBag(bagName)
  CreateThread(function()
    for _ = 1, 20 do
      local entity = getEntityFromBagName(bagName)
      if entity ~= 0 and applyWorldVehicleState(entity) == true then
        return
      end

      Wait(250)
    end
  end)
end

AddStateBagChangeHandler('mz_world_props', nil, function(bagName)
  scheduleApplyFromBag(bagName)
end)

AddStateBagChangeHandler('mz_world_condition', nil, function(bagName)
  scheduleApplyFromBag(bagName)
end)

AddStateBagChangeHandler('mz_persistent', nil, function(bagName, _, value)
  if value == true then
    scheduleApplyFromBag(bagName)
  end
end)

CreateThread(function()
  while true do
    local cfg = getVehicleWorldConfig()
    local interval = tonumber(cfg.checkIntervalMs) or 15000

    if cfg.enableProximityRespawn == true and MZClient and MZClient.PlayerData then
      local ped = PlayerPedId()
      if ped and ped ~= 0 and DoesEntityExist(ped) then
        local coords = GetEntityCoords(ped)
        TriggerServerEvent('mz_core:vehicles:server:checkWorldVehiclesNear', {
          x = coords.x,
          y = coords.y,
          z = coords.z
        })
      end
    end

    Wait(math.max(5000, interval))
  end
end)

CreateThread(function()
  while true do
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
      if DoesEntityExist(vehicle) then
        local state = Entity(vehicle).state
        if state and state.mz_persistent == true then
          local lastApplied = tonumber(AppliedWorldProps[vehicle]) or 0
          if GetGameTimer() - lastApplied > 30000 then
            applyWorldVehicleState(vehicle)
          end
        end
      end
    end

    Wait(5000)
  end
end)
