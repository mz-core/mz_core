MZVehicleWorldService = {}

local VehicleStates = (MZConstants and MZConstants.VehicleStates) or {}
local STATE_OUT = VehicleStates.OUT or 'out'

local WorldCache = {
  byPlate = {},
  byNetId = {}
}

local WorldSpawning = {
  byPlate = {}
}

local ProximityCheckBySource = {}

local function getWorldConfig()
  return Config.VehicleWorld or {}
end

local function debugWorld(message)
  if getWorldConfig().debug == true then
    print(('[mz_vehicle_world] %s'):format(tostring(message)))
  end
end

local function logWorld(message)
  debugWorld(message)
end

local function normalizePlate(plate)
  return tostring(plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
end

local function safeDoesEntityExist(entity)
  if not entity or entity == 0 then
    return false
  end

  if type(DoesEntityExist) ~= 'function' then
    return true
  end

  local ok, exists = pcall(DoesEntityExist, entity)
  if not ok then
    return false
  end

  return exists == true
end

local function safeGetNetworkIdFromEntity(entity)
  if not safeDoesEntityExist(entity) or type(NetworkGetNetworkIdFromEntity) ~= 'function' then
    return 0
  end

  local ok, netId = pcall(NetworkGetNetworkIdFromEntity, entity)
  if not ok then
    return 0
  end

  return tonumber(netId) or 0
end

local function isPlateSpawning(plate)
  plate = normalizePlate(plate)
  return plate ~= '' and WorldSpawning.byPlate[plate] == true
end

local function clearSpawningPlate(plate)
  plate = normalizePlate(plate)
  if plate ~= '' then
    WorldSpawning.byPlate[plate] = nil
  end
end

local function clearSpawningPlateAfterError(plate, reason)
  plate = normalizePlate(plate)
  if plate ~= '' then
    WorldSpawning.byPlate[plate] = nil
    logWorld(('spawn lock cleared after error %s %s'):format(plate, tostring(reason or 'unknown_error')))
  end
end

local function markSpawningPlate(plate, reason, timeoutMs)
  plate = normalizePlate(plate)
  if plate == '' then
    return false
  end

  WorldSpawning.byPlate[plate] = true

  local timeout = tonumber(timeoutMs) or 30000
  if type(SetTimeout) == 'function' and timeout > 0 then
    SetTimeout(timeout, function()
      if WorldSpawning.byPlate[plate] == true then
        WorldSpawning.byPlate[plate] = nil
        debugWorld(('spawn lock timeout %s reason=%s'):format(plate, tostring(reason or 'unknown')))
      end
    end)
  end

  return true
end

local function cloneTable(value)
  if type(value) ~= 'table' then
    return value
  end

  local out = {}
  for key, child in pairs(value) do
    out[key] = type(child) == 'table' and cloneTable(child) or child
  end
  return out
end

local function decodeJson(value, fallback)
  if type(value) == 'table' then
    return value
  end

  if type(value) ~= 'string' or value == '' then
    return fallback
  end

  local ok, decoded = pcall(json.decode, value)
  if not ok then
    return fallback
  end

  return decoded
end

local function encodeJson(value)
  return MZUtils and MZUtils.jsonEncode and MZUtils.jsonEncode(value or {}) or json.encode(value or {})
end

local function normalizeNumber(value, fallback)
  local numeric = tonumber(value)
  if numeric == nil then
    return fallback
  end

  return numeric + 0.0
end

local function normalizeCoords(coords)
  if type(coords) ~= 'table' then
    return nil
  end

  local x = tonumber(coords.x)
  local y = tonumber(coords.y)
  local z = tonumber(coords.z)
  if not x or not y or not z then
    return nil
  end

  return {
    x = x + 0.0,
    y = y + 0.0,
    z = z + 0.0
  }
end

local function hasValidWorldCoords(row)
  if type(row) ~= 'table' then
    return false
  end

  local x = tonumber(row.x)
  local y = tonumber(row.y)
  local z = tonumber(row.z)
  if not x or not y or not z then
    return false
  end

  return not (x == 0.0 and y == 0.0 and z == 0.0)
end

local function getSnapshotNumber(snapshot, fallback, ...)
  snapshot = type(snapshot) == 'table' and snapshot or {}

  for i = 1, select('#', ...) do
    local key = select(i, ...)
    local value = tonumber(snapshot[key])
    if value ~= nil then
      return value + 0.0
    end
  end

  return fallback
end

local function isTruthyDestroyed(value)
  return value == true or value == 1 or value == '1'
end

local function computeDestroyed(snapshot, existing, plate)
  snapshot = type(snapshot) == 'table' and snapshot or {}
  existing = type(existing) == 'table' and existing or {}

  local snapshotEngine = tonumber(snapshot.engine_health or snapshot.engine)
  local snapshotBody = tonumber(snapshot.body_health or snapshot.body)
  local engine = snapshotEngine or tonumber(existing.engine_health or existing.engine) or 1000.0
  local body = snapshotBody or tonumber(existing.body_health or existing.body) or 1000.0
  local wasDestroyed = isTruthyDestroyed(existing.destroyed)
  local hasFreshCondition = snapshot.destroyed ~= nil
    or snapshotEngine ~= nil
    or snapshotBody ~= nil
  local destroyed

  if hasFreshCondition then
    destroyed = isTruthyDestroyed(snapshot.destroyed)
      or engine <= 50.0
      or body <= 100.0
  else
    destroyed = wasDestroyed
  end

  logWorld(('destroyed compute %s engine=%.3f body=%.3f result=%s previous=%s'):format(
    normalizePlate(plate or snapshot.plate or existing.plate),
    engine,
    body,
    tostring(destroyed == true),
    tostring(wasDestroyed == true)
  ))

  return destroyed == true, engine, body, wasDestroyed
end

local function getEntityFromNetId(netId)
  netId = tonumber(netId) or 0
  if netId <= 0 then
    return 0
  end

  if type(NetworkGetEntityFromNetworkId) ~= 'function' then
    logWorld(('getEntityFromNetId unavailable native %s'):format(tostring(netId)))
    return 0
  end

  local ok, entity = pcall(NetworkGetEntityFromNetworkId, netId)
  if not ok or not entity or entity == 0 then
    return 0
  end

  if type(DoesEntityExist) == 'function' then
    local existsOk, exists = pcall(DoesEntityExist, entity)
    if existsOk and not exists then
      return 0
    end

    if not existsOk then
      return 0
    end
  end

  return entity
end

local function readEntityPlate(entity)
  if not safeDoesEntityExist(entity) then
    return ''
  end

  local state = Entity(entity).state
  if state and state.mz_plate then
    local statePlate = normalizePlate(state.mz_plate)
    if statePlate ~= '' then
      return statePlate
    end
  end

  local ok, plate = pcall(GetVehicleNumberPlateText, entity)
  if ok then
    return normalizePlate(plate)
  end

  return ''
end

local function findExistingWorldEntityByPlate(plate)
  plate = normalizePlate(plate)
  if plate == '' or type(GetAllVehicles) ~= 'function' then
    return 0
  end

  local ok, vehicles = pcall(GetAllVehicles)
  if not ok or type(vehicles) ~= 'table' then
    return 0
  end

  for _, entity in ipairs(vehicles) do
    if safeDoesEntityExist(entity) and readEntityPlate(entity) == plate then
      return entity
    end
  end

  return 0
end

local function findAllVehiclesByPlate(plate)
  plate = normalizePlate(plate)
  if plate == '' or type(GetAllVehicles) ~= 'function' then
    return {}
  end

  local ok, vehicles = pcall(GetAllVehicles)
  if not ok or type(vehicles) ~= 'table' then
    return {}
  end

  local found = {}
  for _, entity in ipairs(vehicles) do
    if safeDoesEntityExist(entity) and readEntityPlate(entity) == plate then
      found[#found + 1] = entity
    end
  end

  return found
end

local function hasDriverOrPassengers(entity)
  if not safeDoesEntityExist(entity) then
    return false
  end

  if type(GetVehicleNumberOfPassengers) == 'function' then
    local ok, passengers = pcall(GetVehicleNumberOfPassengers, entity)
    if ok and passengers and passengers > 0 then
      return true
    end
  end

  if type(GetPedInVehicleSeat) == 'function' then
    local ok, driver = pcall(GetPedInVehicleSeat, entity, -1)
    if ok and driver and driver ~= 0 then
      return true
    end
  end

  return false
end

local function deduplicateVehiclesByPlate(plate, keepEntity)
  plate = normalizePlate(plate)
  if plate == '' then
    return 0
  end

  local allEntities = findAllVehiclesByPlate(plate)
  if #allEntities <= 1 then
    return 0
  end

  local entityToKeep = nil
  if keepEntity and safeDoesEntityExist(keepEntity) and readEntityPlate(keepEntity) == plate then
    entityToKeep = keepEntity
  else
    for _, entity in ipairs(allEntities) do
      if hasDriverOrPassengers(entity) then
        entityToKeep = entity
        break
      end
    end

    if not entityToKeep then
      local state = Entity(allEntities[1]).state
      if state and state.mz_persistent == true then
        entityToKeep = allEntities[1]
      else
        entityToKeep = allEntities[1]
      end
    end
  end

  local deleted = 0
  for _, entity in ipairs(allEntities) do
    if entity ~= entityToKeep then
      if hasDriverOrPassengers(entity) then
        debugWorld(('skip delete duplicate %s reason=has_driver'):format(plate))
      else
        if type(DeleteEntity) == 'function' then
          pcall(DeleteEntity, entity)
          deleted = deleted + 1
          debugWorld(('delete duplicate %s count=%d'):format(plate, deleted))
        end
      end
    end
  end

  if deleted > 0 then
    logWorld(('deduplicate %s kept=%s deleted=%d total=%d'):format(plate, tostring(entityToKeep), deleted, #allEntities))
  end

  return deleted
end

function MZVehicleWorldService.DeduplicateVehiclesByPlate(plate, keepNetIdOrEntity)
  plate = normalizePlate(plate)

  if plate == '' then
    return 0
  end

  local keepEntity = tonumber(keepNetIdOrEntity) or 0

  -- Se recebeu netId em vez de entity handle, tenta resolver.
  if keepEntity > 0 and not safeDoesEntityExist(keepEntity) then
    keepEntity = getEntityFromNetId(keepEntity)
  end

  if keepEntity <= 0 or not safeDoesEntityExist(keepEntity) then
    keepEntity = nil
  end

  return deduplicateVehiclesByPlate(plate, keepEntity)
end

local function deleteUnoccupiedVehiclesByPlate(plate)
  plate = normalizePlate(plate)
  if plate == '' then
    return 0
  end

  local allEntities = findAllVehiclesByPlate(plate)
  local deleted = 0

  for _, entity in ipairs(allEntities) do
    if hasDriverOrPassengers(entity) then
      debugWorld(('skip delete unoccupied cleanup %s reason=occupied'):format(plate))
    elseif type(DeleteEntity) == 'function' then
      local ok = pcall(DeleteEntity, entity)
      if ok then
        deleted = deleted + 1
      end
    end
  end

  debugWorld(('delete unoccupied cleanup %s removed=%d total=%d'):format(plate, deleted, #allEntities))
  return deleted
end

local function logWorldAction(action, vehicle, actorSource, before, after, meta)
  if not MZLogService then
    return
  end

  local actor = { type = 'system', id = 'system' }
  if actorSource ~= nil then
    local player = MZPlayerService and MZPlayerService.getPlayer and MZPlayerService.getPlayer(actorSource) or nil
    if player and player.citizenid then
      actor = {
        type = 'player',
        id = tostring(player.citizenid),
        source = actorSource
      }
    elseif tonumber(actorSource) == 0 then
      actor = { type = 'console', id = 'console' }
    else
      actor = { type = 'source', id = tostring(actorSource) }
    end
  end

  MZLogService.createDetailed('vehicles', action, {
    actor = actor,
    target = {
      type = 'vehicle',
      id = tostring(vehicle and vehicle.plate or 'unknown')
    },
    context = {
      vehicle_id = tonumber(vehicle and vehicle.id),
      plate = tostring(vehicle and vehicle.plate or ''),
      model = tostring(vehicle and vehicle.model or ''),
      garage = tostring(vehicle and vehicle.garage or ''),
      state = tostring(vehicle and vehicle.state or '')
    },
    before = before or {},
    after = after or {},
    meta = meta or {}
  })
end

local function decodeWorldRow(row)
  if not row then
    return nil
  end

  row.props_json = decodeJson(row.props_json or '{}', {})
  row.extra_json = decodeJson(row.extra_json or '{}', {})
  row.vehicle_id = tonumber(row.vehicle_id)
  row.x = normalizeNumber(row.x, 0.0)
  row.y = normalizeNumber(row.y, 0.0)
  row.z = normalizeNumber(row.z, 0.0)
  row.heading = normalizeNumber(row.heading, 0.0)
  row.fuel = normalizeNumber(row.fuel, 100.0)
  row.engine_health = normalizeNumber(row.engine_health, 1000.0)
  row.body_health = normalizeNumber(row.body_health, 1000.0)
  row.locked = row.locked == true or tonumber(row.locked) == 1
  row.destroyed = row.destroyed == true or tonumber(row.destroyed) == 1
  row.net_id = tonumber(row.net_id) or 0
  row.entity_handle = tonumber(row.entity_handle) or 0
  row.vehicle_category = tostring(row.vehicle_category or row.category or '')
  row.owner_type = tostring(row.owner_type or '')
  row.owner_id = tostring(row.owner_id or '')
  return row
end

local function getWorldRow(plate)
  plate = normalizePlate(plate)
  if plate == '' then
    return nil
  end

  local row = MySQL.single.await([[
    SELECT *
    FROM mz_vehicle_world_state
    WHERE UPPER(TRIM(plate)) = ?
    LIMIT 1
  ]], { plate })

  return decodeWorldRow(row)
end

local function decodeWorldRows(rows)
  local out = {}
  for _, row in ipairs(rows or {}) do
    out[#out + 1] = decodeWorldRow(row)
  end
  return out
end

local function worldRowToRespawnPayload(row, sourceLabel)
  if not row then
    return nil
  end

  return {
    id = row.vehicle_id,
    plate = normalizePlate(row.plate),
    model = tostring(row.model or ''),
    garage = tostring(row.garage or ''),
    owner_type = tostring(row.owner_type or ''),
    owner_id = tostring(row.owner_id or ''),
    fuel = normalizeNumber(row.fuel, 100.0),
    engine = normalizeNumber(row.engine_health, 1000.0),
    body = normalizeNumber(row.body_health, 1000.0),
    props = cloneTable(row.props_json or {}),
    metadata = {},
    world = {
      last_coords = {
        x = row.x,
        y = row.y,
        z = row.z
      },
      last_heading = row.heading,
      locked = row.locked == true,
      destroyed = row.destroyed == true,
      last_seen_at = row.last_seen_at,
      source = sourceLabel or 'mz_vehicle_world_state'
    }
  }
end

local function buildLegacyWorldState(vehicle)
  local metadata = type(vehicle and vehicle.metadata_json) == 'table' and vehicle.metadata_json or {}
  local world = type(metadata.world) == 'table' and metadata.world or nil
  local coords = normalizeCoords(world and world.last_coords or nil)
  if not coords then
    return nil
  end

  return {
    plate = normalizePlate(vehicle.plate),
    vehicle_id = tonumber(vehicle.id),
    state = STATE_OUT,
    model = tostring(vehicle.model or ''),
    garage = tostring(vehicle.garage or ''),
    x = coords.x,
    y = coords.y,
    z = coords.z,
    heading = normalizeNumber(world.last_heading, 0.0),
    fuel = normalizeNumber(vehicle.fuel, 100.0),
    engine_health = normalizeNumber(vehicle.engine, 1000.0),
    body_health = normalizeNumber(vehicle.body, 1000.0),
    locked = world.locked == true,
    destroyed = world.destroyed == true,
    props_json = cloneTable(vehicle.props_json or {}),
    extra_json = {
      has_coords = true,
      legacy_metadata_world = cloneTable(world)
    },
    net_id = 0,
    entity_handle = 0
  }
end

local function getStateForVehicle(vehicle)
  local row = getWorldRow(vehicle and vehicle.plate)
  if row then
    return row, false
  end

  return buildLegacyWorldState(vehicle), true
end

local function buildSnapshot(vehicle, snapshot, previous)
  snapshot = type(snapshot) == 'table' and snapshot or {}
  previous = type(previous) == 'table' and previous or {}

  local coords = normalizeCoords(snapshot.coords or snapshot.last_coords)
    or normalizeCoords({
      x = previous.x,
      y = previous.y,
      z = previous.z
    })

  local hasCoords = coords ~= nil and not (coords.x == 0.0 and coords.y == 0.0 and coords.z == 0.0)
  if not coords then
    coords = { x = 0.0, y = 0.0, z = 0.0 }
  end

  local props = type(snapshot.props) == 'table'
    and snapshot.props
    or (type(previous.props_json) == 'table' and previous.props_json or vehicle.props_json or {})

  local extra = type(previous.extra_json) == 'table' and cloneTable(previous.extra_json) or {}
  extra.has_coords = hasCoords
  extra.updated_by_world_service = true
  extra.last_snapshot_at = os.time()

  local locked = previous.locked == true
  if snapshot.locked ~= nil then
    locked = snapshot.locked == true or tonumber(snapshot.locked) == 2
  end

  local destroyed, engineHealth, bodyHealth = computeDestroyed(snapshot, previous, vehicle.plate)

  if destroyed == true then
    logWorld(('destroyed detected %s engine=%.3f body=%.3f'):format(
      normalizePlate(vehicle.plate),
      tonumber(engineHealth) or 0.0,
      tonumber(bodyHealth) or 0.0
    ))
  end

  return {
    plate = normalizePlate(vehicle.plate),
    vehicle_id = tonumber(vehicle.id),
    state = tostring(vehicle.state or STATE_OUT),
    model = tostring(vehicle.model or ''),
    garage = tostring(vehicle.garage or ''),
    x = coords.x,
    y = coords.y,
    z = coords.z,
    heading = normalizeNumber(snapshot.heading or snapshot.last_heading, normalizeNumber(previous.heading, 0.0)),
    fuel = normalizeNumber(snapshot.fuel, normalizeNumber(previous.fuel, normalizeNumber(vehicle.fuel, 100.0))),
    engine_health = engineHealth,
    body_health = bodyHealth,
    locked = locked,
    destroyed = destroyed,
    props_json = props,
    extra_json = extra,
    net_id = tonumber(snapshot.net_id or snapshot.netId) or tonumber(previous.net_id) or 0,
    entity_handle = tonumber(snapshot.entity or snapshot.entity_handle) or tonumber(previous.entity_handle) or 0
  }
end

local function upsertWorldState(data)
  MySQL.insert.await([[
    INSERT INTO mz_vehicle_world_state (
      plate, vehicle_id, state, model, garage,
      x, y, z, heading,
      fuel, engine_health, body_health,
      locked, destroyed,
      props_json, extra_json,
      net_id, entity_handle, last_seen_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
    ON DUPLICATE KEY UPDATE
      vehicle_id = VALUES(vehicle_id),
      state = VALUES(state),
      model = VALUES(model),
      garage = VALUES(garage),
      x = VALUES(x),
      y = VALUES(y),
      z = VALUES(z),
      heading = VALUES(heading),
      fuel = VALUES(fuel),
      engine_health = VALUES(engine_health),
      body_health = VALUES(body_health),
      locked = VALUES(locked),
      destroyed = VALUES(destroyed),
      props_json = VALUES(props_json),
      extra_json = VALUES(extra_json),
      net_id = VALUES(net_id),
      entity_handle = VALUES(entity_handle),
      last_seen_at = CURRENT_TIMESTAMP
  ]], {
    data.plate,
    data.vehicle_id,
    data.state,
    data.model,
    data.garage,
    data.x,
    data.y,
    data.z,
    data.heading,
    data.fuel,
    data.engine_health,
    data.body_health,
    data.locked == true and 1 or 0,
    data.destroyed == true and 1 or 0,
    encodeJson(data.props_json or {}),
    encodeJson(data.extra_json or {}),
    tonumber(data.net_id) or 0,
    tonumber(data.entity_handle) or 0
  })

  if data.destroyed == true then
    local affected = MySQL.update.await([[
      UPDATE mz_vehicle_world_state
      SET destroyed = 1,
          updated_at = CURRENT_TIMESTAMP
      WHERE UPPER(TRIM(plate)) = ?
    ]], { data.plate })

    if affected and affected > 0 then
      logWorld(('destroyed saved %s destroyed=1'):format(normalizePlate(data.plate)))
    else
      logWorld(('destroyed not saved %s reason=row_not_found'):format(normalizePlate(data.plate)))
    end
  end

  return getWorldRow(data.plate)
end

function MZVehicleWorldService.getCachedEntity(plate)
  plate = normalizePlate(plate)
  local cached = WorldCache.byPlate[plate]
  if not cached then
    local existing = findExistingWorldEntityByPlate(plate)
    if existing ~= 0 then
      local netId = safeGetNetworkIdFromEntity(existing)
      WorldCache.byPlate[plate] = {
        plate = plate,
        net_id = netId,
        entity = existing,
        updated_at = os.time()
      }
      WorldCache.byNetId[netId] = plate
      return existing, WorldCache.byPlate[plate]
    end

    return 0, nil
  end

  local entity = getEntityFromNetId(cached.net_id)
  if entity ~= 0 then
    return entity, cached
  end

  logWorld(('clearing stale netId cache %s %s'):format(plate, tostring(cached.net_id or 0)))
  WorldCache.byPlate[plate] = nil
  if cached.net_id then
    WorldCache.byNetId[tonumber(cached.net_id) or 0] = nil
  end

  return 0, nil
end

function MZVehicleWorldService.clearCache(plate)
  plate = normalizePlate(plate)
  local cached = WorldCache.byPlate[plate]
  if cached and cached.net_id then
    WorldCache.byNetId[tonumber(cached.net_id) or 0] = nil
  end
  WorldCache.byPlate[plate] = nil
end

function MZVehicleWorldService.isSpawned(plate, netId)
  local entity, cached = MZVehicleWorldService.getCachedEntity(plate)
  if entity == 0 then
    return false
  end

  netId = tonumber(netId) or 0
  if netId > 0 and tonumber(cached.net_id) ~= netId then
    return true, entity, 'different_net_id'
  end

  return true, entity
end

function MZVehicleWorldService.IsPlateSpawned(plate)
  local spawned, entity = MZVehicleWorldService.isSpawned(plate)
  return spawned == true, entity
end

function MZVehicleWorldService.registerEntity(vehicle, actorSource, netId)
  local plate = normalizePlate(vehicle and vehicle.plate)
  netId = tonumber(netId) or 0
  if plate == '' or netId <= 0 then
    return false, 'invalid_entity_registration'
  end

  local entity = getEntityFromNetId(netId)
  if entity == 0 then
    return false, 'entity_not_found'
  end

  MZVehicleWorldService.clearCache(plate)

  WorldCache.byPlate[plate] = {
    plate = plate,
    net_id = netId,
    entity = entity,
    updated_at = os.time()
  }
  WorldCache.byNetId[netId] = plate

  local state = Entity(entity).state
  if state then
    state:set('mz_plate', plate, true)
    state:set('mz_persistent', true, true)
  end

  if type(SetEntityOrphanMode) == 'function' then
    pcall(SetEntityOrphanMode, entity, 2)
  end

  logWorldAction('vehicle_world_register_entity', vehicle, actorSource, {}, {
    plate = plate,
    net_id = netId
  })

  clearSpawningPlate(plate)
  return true, entity
end

function MZVehicleWorldService.RegisterWorldEntity(plateOrVehicle, entity, netId, actorSource)
  local vehicle = type(plateOrVehicle) == 'table' and plateOrVehicle or {
    plate = normalizePlate(plateOrVehicle)
  }

  if (not netId or tonumber(netId) == 0) and safeDoesEntityExist(entity) then
    netId = safeGetNetworkIdFromEntity(entity)
  end

  return MZVehicleWorldService.registerEntity(vehicle, actorSource, netId)
end

function MZVehicleWorldService.registerOutVehicle(vehicle, actorSource, snapshot)
  if not vehicle or normalizePlate(vehicle.plate) == '' then
    return false, 'invalid_vehicle'
  end

  local previous = getWorldRow(vehicle.plate) or buildLegacyWorldState(vehicle) or {}
  local data = buildSnapshot(vehicle, snapshot or {}, previous)
  data.state = STATE_OUT

  local row = upsertWorldState(data)
  debugWorld(('withdraw/register %s %s'):format(tostring(data.plate or ''), tostring(data.model or '')))
  logWorldAction('vehicle_world_register_out', vehicle, actorSource, previous, row)

  return true, row
end

function MZVehicleWorldService.saveSnapshot(vehicle, actorSource, snapshot)
  if not vehicle or normalizePlate(vehicle.plate) == '' then
    return false, 'invalid_vehicle'
  end

  local previous = getWorldRow(vehicle.plate) or buildLegacyWorldState(vehicle) or {}
  local data = buildSnapshot(vehicle, snapshot or {}, previous)
  data.state = STATE_OUT

  local row = upsertWorldState(data)
  debugWorld(('snapshot saved %s %.3f %.3f %.3f'):format(
    tostring(data.plate or ''),
    tonumber(data.x) or 0.0,
    tonumber(data.y) or 0.0,
    tonumber(data.z) or 0.0
  ))
  logWorldAction('vehicle_world_snapshot', vehicle, actorSource, previous, row, {
    has_coords = type(row and row.extra_json) == 'table' and row.extra_json.has_coords == true
  })

  if row and row.destroyed ~= true and data.destroyed == true then
    logWorld(('destroyed not saved %s reason=verify_failed'):format(normalizePlate(data.plate)))
  end

  return true, row
end

function MZVehicleWorldService.markDestroyed(vehicle, actorSource, snapshot)
  snapshot = type(snapshot) == 'table' and snapshot or {}
  snapshot.destroyed = true

  local ok, rowOrErr = MZVehicleWorldService.saveSnapshot(vehicle, actorSource, snapshot)
  if ok then
    logWorldAction('vehicle_world_destroyed', vehicle, actorSource, {}, rowOrErr)
  end

  return ok, rowOrErr
end

function MZVehicleWorldService.clearWorldState(plate, actorSource)
  plate = normalizePlate(plate)
  if plate == '' then
    return false, 'invalid_plate'
  end

  local before = getWorldRow(plate)
  MySQL.update.await('DELETE FROM mz_vehicle_world_state WHERE UPPER(TRIM(plate)) = ?', { plate })
  MZVehicleWorldService.clearCache(plate)
  clearSpawningPlate(plate)
  deleteUnoccupiedVehiclesByPlate(plate)

  logWorldAction('vehicle_world_clear', { plate = plate }, actorSource, before or {}, {})
  return true
end

function MZVehicleWorldService.GetOutVehiclesNearCoords(coords, radius)
  coords = normalizeCoords(coords)
  if not coords then
    return false, 'invalid_coords'
  end

  radius = tonumber(radius) or tonumber(getWorldConfig().proximityRadius) or 200.0
  if radius <= 0.0 then
    return true, {}
  end

  local respawnDestroyed = getWorldConfig().respawnDestroyed ~= false
  local rows = MySQL.query.await([[
    SELECT
      w.*,
      v.category AS vehicle_category,
      v.owner_type AS owner_type,
      v.owner_id AS owner_id
    FROM mz_vehicle_world_state w
    INNER JOIN mz_player_vehicles v ON UPPER(TRIM(v.plate)) = UPPER(TRIM(w.plate))
    WHERE w.state = ?
      AND v.state = ?
      AND w.x BETWEEN ? AND ?
      AND w.y BETWEEN ? AND ?
      AND NOT (w.x = 0 AND w.y = 0 AND w.z = 0)
      AND ((w.x - ?) * (w.x - ?) + (w.y - ?) * (w.y - ?) + (w.z - ?) * (w.z - ?)) <= ?
      AND (? = 1 OR w.destroyed = 0)
    ORDER BY w.last_seen_at DESC, w.updated_at DESC
  ]], {
    STATE_OUT,
    STATE_OUT,
    coords.x - radius,
    coords.x + radius,
    coords.y - radius,
    coords.y + radius,
    coords.x,
    coords.x,
    coords.y,
    coords.y,
    coords.z,
    coords.z,
    radius * radius,
    respawnDestroyed and 1 or 0
  }) or {}

  return true, decodeWorldRows(rows)
end

local function getVehicleTypeForSpawn(row)
  local extra = type(row.extra_json) == 'table' and row.extra_json or {}
  local vehicleType = tostring(extra.vehicle_type or extra.spawn_type or '')
  if vehicleType ~= '' then
    return vehicleType
  end

  local category = tostring(row.vehicle_category or ''):lower()
  if category == 'motorcycle' or category == 'motorcycles' or category == 'bike' or category == 'bikes' then
    return 'bike'
  end
  if category == 'boat' or category == 'boats' then
    return 'boat'
  end
  if category == 'helicopter' or category == 'helicopters' or category == 'heli' then
    return 'heli'
  end
  if category == 'plane' or category == 'planes' or category == 'airplane' then
    return 'plane'
  end
  if category == 'train' or category == 'trains' then
    return 'train'
  end
  if category == 'trailer' or category == 'trailers' then
    return 'trailer'
  end

  return 'automobile'
end

local function setSpawnedVehicleState(entity, row)
  if not safeDoesEntityExist(entity) then
    return
  end

  local plate = normalizePlate(row.plate)

  pcall(SetVehicleNumberPlateText, entity, plate)
  pcall(SetVehicleEngineHealth, entity, normalizeNumber(row.engine_health, 1000.0))
  pcall(SetVehicleBodyHealth, entity, normalizeNumber(row.body_health, 1000.0))
  pcall(SetVehicleFuelLevel, entity, normalizeNumber(row.fuel, 100.0))

  if row.locked == true then
    pcall(SetVehicleDoorsLocked, entity, 2)
    pcall(SetVehicleDoorsLockedForAllPlayers, entity, true)
  else
    pcall(SetVehicleDoorsLocked, entity, 1)
    pcall(SetVehicleDoorsLockedForAllPlayers, entity, false)
  end

  local state = Entity(entity).state
  if state then
    state:set('mz_plate', plate, true)
    state:set('mz_persistent', true, true)
    if tonumber(row.vehicle_id) then
      state:set('mz_vehicle_id', tonumber(row.vehicle_id), true)
    end
    if row.owner_type ~= nil and tostring(row.owner_type) ~= '' then
      state:set('mz_owner_type', tostring(row.owner_type), true)
    end
    if row.owner_id ~= nil and tostring(row.owner_id) ~= '' then
      state:set('mz_owner_id', tostring(row.owner_id), true)
    end
    state:set('mz_locked', row.locked == true, true)
    state:set('mz_lock_state', row.locked == true and 2 or 1, true)
    state:set('mz_destroyed', row.destroyed == true, true)
    state:set('mz_world_props', row.props_json or {}, true)
    state:set('mz_world_condition', {
      fuel = row.fuel,
      engine = row.engine_health,
      body = row.body_health,
      locked = row.locked == true,
      destroyed = row.destroyed == true
    }, true)
  end

  debugWorld(('lock state applied %s locked=%s'):format(plate, tostring(row.locked == true)))
end

function MZVehicleWorldService.SpawnWorldVehicleFromState(row, actorSource, reason)
  row = type(row) == 'table' and row or nil
  if not row then
    return false, 'invalid_world_state'
  end

  row.plate = normalizePlate(row.plate)
  if row.plate == '' then
    return false, 'invalid_plate'
  end

  reason = tostring(reason or 'restore')

  if isPlateSpawning(row.plate) then
    debugWorld(('spawn check lock_active plate=%s reason=%s'):format(row.plate, reason))
    logWorld(('skip spawn already spawning %s %s'):format(reason, row.plate))
    return true, {
      plate = row.plate,
      already_spawning = true,
      skipped = true
    }
  end

  local alreadySpawned, entity = MZVehicleWorldService.IsPlateSpawned(row.plate)
  if alreadySpawned then
    deduplicateVehiclesByPlate(row.plate, entity)
    setSpawnedVehicleState(entity, row)
    debugWorld(('spawn check already_exists plate=%s netId=%s'):format(row.plate, tostring(safeGetNetworkIdFromEntity(entity))))
    logWorld(('skip spawn already spawned %s %s'):format(reason, row.plate))
    return true, {
      plate = row.plate,
      entity = entity,
      net_id = safeGetNetworkIdFromEntity(entity),
      already_spawned = true,
      skipped = true
    }
  end

  debugWorld(('spawn check before_spawn plate=%s model=%s reason=%s'):format(row.plate, tostring(row.model), reason))
  deduplicateVehiclesByPlate(row.plate)

  markSpawningPlate(row.plate, reason, 30000)

  logWorld(('respawn attempt %s %s %s %.3f %.3f %.3f'):format(
    reason,
    tostring(row.plate or ''),
    tostring(row.model or ''),
    tonumber(row.x) or 0.0,
    tonumber(row.y) or 0.0,
    tonumber(row.z) or 0.0
  ))

  local protectedOk, spawnOk, spawnResult = xpcall(function()
    if tostring(row.state or '') ~= STATE_OUT then
      return false, 'vehicle_not_out'
    end

    if row.destroyed == true and getWorldConfig().respawnDestroyed == false then
      return false, 'vehicle_destroyed'
    end

    local model = tostring(row.model or '')
    if model == '' then
      return false, 'invalid_model'
    end

    local modelHash = GetHashKey(model)
    local entityOrErr = nil
    local ok = false

    if type(CreateVehicleServerSetter) == 'function' then
      ok, entityOrErr = pcall(CreateVehicleServerSetter, modelHash, getVehicleTypeForSpawn(row), row.x + 0.0, row.y + 0.0, row.z + 0.0, row.heading + 0.0)
    end

    if (not ok or not entityOrErr or entityOrErr == 0) and type(CreateVehicle) == 'function' then
      ok, entityOrErr = pcall(CreateVehicle, modelHash, row.x + 0.0, row.y + 0.0, row.z + 0.0, row.heading + 0.0, true, true)
    end

    if not ok or not safeDoesEntityExist(entityOrErr) then
      return false, 'spawn_failed'
    end

    local spawnedEntity = entityOrErr
    setSpawnedVehicleState(spawnedEntity, row)

    local netId = safeGetNetworkIdFromEntity(spawnedEntity)
    if netId <= 0 then
      if type(DeleteEntity) == 'function' then
        pcall(DeleteEntity, spawnedEntity)
      end
      return false, 'native_unavailable'
    end

    local registered, registerErr = MZVehicleWorldService.RegisterWorldEntity({
      plate = row.plate,
      id = row.vehicle_id,
      model = row.model,
      garage = row.garage,
      state = row.state
    }, spawnedEntity, netId, actorSource)

    if registered ~= true then
      if type(DeleteEntity) == 'function' then
        pcall(DeleteEntity, spawnedEntity)
      end
      return false, registerErr or 'register_failed'
    end

    deduplicateVehiclesByPlate(row.plate, spawnedEntity)

    row.net_id = tonumber(netId) or 0
    row.entity_handle = tonumber(spawnedEntity) or 0
    upsertWorldState(row)

    logWorldAction('vehicle_world_proximity_spawn', {
      id = row.vehicle_id,
      plate = row.plate,
      model = row.model,
      garage = row.garage,
      state = row.state
    }, actorSource, {}, {
      plate = row.plate,
      net_id = netId,
      entity = spawnedEntity
    })

    clearSpawningPlate(row.plate)
    logWorld(('spawn success %s %s %s'):format(reason, row.plate, tostring(netId)))
    debugWorld(('finalize spawn %s locked=%s netId=%s'):format(row.plate, tostring(row.locked == true), tostring(netId)))

    return true, {
      plate = row.plate,
      entity = spawnedEntity,
      net_id = netId
    }
  end, debug.traceback)

  if not protectedOk then
    clearSpawningPlateAfterError(row.plate, 'runtime_error')
    logWorld(('spawn failed %s %s %s'):format(reason, row.plate, tostring(spawnOk)))
    return false, 'spawn_error'
  end

  if spawnOk ~= true then
    clearSpawningPlateAfterError(row.plate, spawnResult)
    logWorld(('spawn failed %s %s %s'):format(reason, row.plate, tostring(spawnResult or 'spawn_failed')))
    return false, spawnResult or 'spawn_failed'
  end

  return true, spawnResult
end

function MZVehicleWorldService.RestoreOutVehiclesForPlayer(source, vehicles, reason)
  reason = tostring(reason or 'restore')
  local out = {}
  local restored = 0
  local failed = 0
  local restoredThisCycle = {}

  for _, vehicle in ipairs(vehicles or {}) do
    if tostring(vehicle.state or '') == STATE_OUT then
      local plate = normalizePlate(vehicle.plate)
      local state, fromLegacy = getStateForVehicle(vehicle)

      if restoredThisCycle[plate] == true then
        logWorld(('skip duplicate %s %s'):format(reason, plate))
        goto continue
      end

      restoredThisCycle[plate] = true

      if state and hasValidWorldCoords(state) then
        state.plate = plate
        state.vehicle_id = tonumber(state.vehicle_id or vehicle.id)
        state.model = tostring(state.model or vehicle.model or '')
        state.garage = tostring(state.garage or vehicle.garage or '')
        state.owner_type = tostring(vehicle.owner_type or state.owner_type or '')
        state.owner_id = tostring(vehicle.owner_id or state.owner_id or '')
        state.vehicle_category = tostring(vehicle.category or state.vehicle_category or '')

        if fromLegacy == true then
          MZVehicleWorldService.registerOutVehicle(vehicle, nil, {
            coords = { x = state.x, y = state.y, z = state.z },
            heading = state.heading,
            fuel = state.fuel,
            engine = state.engine_health,
            body = state.body_health,
            locked = state.locked,
            destroyed = state.destroyed,
            props = state.props_json
          })
        end

        logWorld(('restore candidate %s %s %s %.3f %.3f %.3f'):format(
          reason,
          plate,
          tostring(state.model or ''),
          tonumber(state.x) or 0.0,
          tonumber(state.y) or 0.0,
          tonumber(state.z) or 0.0
        ))
        logWorld(('restore row %s %s %.3f %.3f %.3f %.2f'):format(plate, tostring(state.model or ''), tonumber(state.x) or 0.0, tonumber(state.y) or 0.0, tonumber(state.z) or 0.0, tonumber(state.heading) or 0.0))

        local spawnOk, spawnResultOrErr = MZVehicleWorldService.SpawnWorldVehicleFromState(state, source, reason)
        if spawnOk == true then
          restored = restored + 1
          out[#out + 1] = {
            plate = plate,
            ok = true,
            net_id = type(spawnResultOrErr) == 'table' and spawnResultOrErr.net_id or nil,
            already_spawned = type(spawnResultOrErr) == 'table' and spawnResultOrErr.already_spawned == true
          }
        else
          failed = failed + 1
          logWorld(('spawn failed %s %s %s'):format(reason, plate, tostring(spawnResultOrErr or 'unknown_error')))

          if source and tonumber(source) and tonumber(source) > 0 then
            local payload = worldRowToRespawnPayload(state, 'restore_fallback')
            if payload then
              markSpawningPlate(plate, reason .. ':fallback', 30000)
              TriggerClientEvent('mz_core:vehicles:client:restoreWorldVehicle', source, payload)
            end
          end

          out[#out + 1] = {
            plate = plate,
            ok = false,
            error = spawnResultOrErr or 'spawn_failed',
            fallback = true
          }
        end
      else
        failed = failed + 1
        logWorld(('spawn failed %s %s missing_coords'):format(reason, plate))
        out[#out + 1] = {
          plate = plate,
          ok = false,
          error = 'missing_coords'
        }
      end

      ::continue::
    end
  end

  logWorld(('out vehicles found %s'):format(#out))
  return true, {
    restored = restored,
    failed = failed,
    vehicles = out
  }
end

function MZVehicleWorldService.EnsureWorldVehiclesNearPlayer(source, coords)
  local player = MZPlayerService and MZPlayerService.getPlayer and MZPlayerService.getPlayer(source) or nil
  if not player then
    return false, 'player_not_loaded'
  end

  local cfg = getWorldConfig()
  if cfg.enableProximityRespawn ~= true then
    return true, {
      spawned = 0,
      disabled = true
    }
  end

  coords = normalizeCoords(coords)
  if not coords then
    return false, 'invalid_coords'
  end

  local now = GetGameTimer()
  local minInterval = math.max(1000, math.floor((tonumber(cfg.checkIntervalMs) or 15000) * 0.65))
  if ProximityCheckBySource[source] and now - ProximityCheckBySource[source] < minInterval then
    return true, {
      spawned = 0,
      throttled = true
    }
  end
  ProximityCheckBySource[source] = now

  local ok, rowsOrErr = MZVehicleWorldService.GetOutVehiclesNearCoords(coords, cfg.proximityRadius)
  if not ok then
    return false, rowsOrErr
  end

  local spawned = 0
  local maxPerTick = math.max(1, tonumber(cfg.maxRespawnsPerTick) or 3)

  for _, row in ipairs(rowsOrErr or {}) do
    if spawned >= maxPerTick then
      break
    end

    if not MZVehicleWorldService.IsPlateSpawned(row.plate) then
      local spawnOk = MZVehicleWorldService.SpawnWorldVehicleFromState(row, source, 'proximity')
      if spawnOk == true then
        spawned = spawned + 1
      end
    end
  end

  if spawned > 0 then
    debugWorld(('source=%s proximity spawned=%s near %.2f %.2f %.2f'):format(source, spawned, coords.x, coords.y, coords.z))
  end

  return true, {
    spawned = spawned,
    candidates = #(rowsOrErr or {})
  }
end

function MZVehicleWorldService.getOutVehiclesForRespawn(vehicles)
  local out = {}

  for _, vehicle in ipairs(vehicles or {}) do
    if tostring(vehicle.state or '') == STATE_OUT then
      local plate = normalizePlate(vehicle.plate)
      local isSpawned = MZVehicleWorldService.isSpawned(plate)
      local state, fromLegacy = getStateForVehicle(vehicle)

      if state and hasValidWorldCoords(state) then
        if fromLegacy == true then
          MZVehicleWorldService.registerOutVehicle(vehicle, nil, {
            coords = { x = state.x, y = state.y, z = state.z },
            heading = state.heading,
            fuel = state.fuel,
            engine = state.engine_health,
            body = state.body_health,
            locked = state.locked,
            destroyed = state.destroyed,
            props = state.props_json
          })
        end

        if isSpawned then
          debugWorld(('skip duplicate %s'):format(plate))
        end

        out[#out + 1] = {
          id = vehicle.id,
          plate = plate,
          model = tostring(vehicle.model or state.model or ''),
          garage = tostring(vehicle.garage or state.garage or ''),
          owner_type = tostring(vehicle.owner_type or ''),
          owner_id = tostring(vehicle.owner_id or ''),
          fuel = normalizeNumber(state.fuel, tonumber(vehicle.fuel) or 100),
          engine = normalizeNumber(state.engine_health, tonumber(vehicle.engine) or 1000),
          body = normalizeNumber(state.body_health, tonumber(vehicle.body) or 1000),
          props = cloneTable(state.props_json or vehicle.props_json or {}),
          metadata = cloneTable(vehicle.metadata_json or {}),
          already_spawned = isSpawned == true,
          world = {
            last_coords = {
              x = state.x,
              y = state.y,
              z = state.z
            },
            last_heading = state.heading,
            locked = state.locked == true,
            destroyed = state.destroyed == true,
            last_seen_at = state.last_seen_at,
            source = fromLegacy == true and 'metadata_json.world' or 'mz_vehicle_world_state'
          }
        }
      else
        debugWorld(('respawn failed %s missing_coords'):format(plate))
      end
    end
  end

  debugWorld(('out vehicles found %s'):format(#out))
  return true, out
end
