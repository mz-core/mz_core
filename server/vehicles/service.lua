MZVehicleService = {}

local VehicleStates = (MZConstants and MZConstants.VehicleStates) or {}
local STATE_STORED = VehicleStates.STORED or 'stored'
local STATE_OUT = VehicleStates.OUT or 'out'
local STATE_IMPOUNDED = VehicleStates.IMPOUNDED or VehicleStates.IMPOUND or 'impounded'

local function normalizeVehicleState(state)
  state = tostring(state or ''):lower()

  if state == 'impound' or state == 'impounded' then
    return STATE_IMPOUNDED
  end

  return state
end

local function debugVehicleWorld(message)
  if Config and Config.VehicleWorld and Config.VehicleWorld.debug == true then
    print(('[mz_vehicle_world] %s'):format(tostring(message)))
  end
end

local function isImpoundedState(state)
  return normalizeVehicleState(state) == STATE_IMPOUNDED
end

local function getPlayerBySource(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then
    return nil, 'player_not_loaded'
  end

  return player
end

local function normalizePlate(plate)
  plate = tostring(plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
  return plate
end

local function getOrgByCode(orgCode)
  orgCode = tostring(orgCode or '')
  if orgCode == '' then
    return nil
  end

  if MZOrgService and MZOrgService.getOrgByCode then
    return MZOrgService.getOrgByCode(orgCode)
  end

  return MySQL.single.await([[
    SELECT *
    FROM mz_orgs
    WHERE code = ?
    LIMIT 1
  ]], { orgCode })
end

local function playerHasOrgAccess(citizenid, orgId)
  local row = MySQL.single.await([[
    SELECT id
    FROM mz_player_orgs
    WHERE citizenid = ? AND org_id = ? AND active = 1
    LIMIT 1
  ]], { citizenid, orgId })

  return row ~= nil
end

local function getPlayerOrgIds(citizenid)
  local rows = MySQL.query.await([[
    SELECT org_id
    FROM mz_player_orgs
    WHERE citizenid = ? AND active = 1
  ]], { citizenid }) or {}

  local orgIds = {}
  for _, row in ipairs(rows) do
    local orgId = tonumber(row.org_id)
    if orgId then
      orgIds[#orgIds + 1] = orgId
    end
  end

  return orgIds
end

local function clampNumber(value, minValue, maxValue, fallback)
  value = tonumber(value)
  if not value then
    return fallback
  end

  if minValue ~= nil and value < minValue then
    value = minValue
  end

  if maxValue ~= nil and value > maxValue then
    value = maxValue
  end

  return value
end

local function buildImpoundData(reason, actorSource, extraData)
  local payload = {
    reason = tostring(reason or 'impounded'),
    at = os.time()
  }

  if actorSource ~= nil then
    if tonumber(actorSource) == 0 then
      payload.by = {
        type = 'console',
        id = 'console'
      }
    else
      local player = MZPlayerService.getPlayer(actorSource)
      if player and player.citizenid then
        payload.by = {
          type = 'player',
          id = tostring(player.citizenid),
          source = actorSource
        }
      else
        payload.by = {
          type = 'source',
          id = tostring(actorSource)
        }
      end
    end
  end

  if type(extraData) == 'table' then
    for k, v in pairs(extraData) do
      payload[k] = v
    end
  end

  return payload
end

local function normalizeVehicleMetadata(metadata)
  if type(metadata) ~= 'table' then
    return {}
  end

  return metadata
end

local function cloneTable(value)
  if type(value) ~= 'table' then
    return value
  end

  local out = {}
  for k, v in pairs(value) do
    if type(v) == 'table' then
      out[k] = cloneTable(v)
    else
      out[k] = v
    end
  end
  return out
end

local function mergeTable(base, extra)
  local out = {}

  for k, v in pairs(base or {}) do
    out[k] = v
  end

  for k, v in pairs(extra or {}) do
    out[k] = v
  end

  return out
end

local buildFlowMetadataPatch

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

local function normalizeWorldSnapshot(snapshot)
  snapshot = type(snapshot) == 'table' and snapshot or {}
  local coords = normalizeCoords(snapshot.coords or snapshot.last_coords)

  local world = {
    persistent = true,
    updated_at = os.time()
  }

  if coords then
    world.last_coords = coords
  end

  local heading = tonumber(snapshot.heading or snapshot.last_heading)
  if heading then
    world.last_heading = heading + 0.0
  end

  local netId = tonumber(snapshot.net_id or snapshot.netId)
  if netId and netId > 0 then
    world.net_id = math.floor(netId)
  end

  if snapshot.locked ~= nil then
    world.locked = snapshot.locked == true or tonumber(snapshot.locked) == 2
  end

  if snapshot.destroyed ~= nil then
    world.destroyed = snapshot.destroyed == true
  end

  return world
end

local function buildOutVehicleMetadata(vehicle, source, action, snapshot)
  local currentMetadata = normalizeVehicleMetadata(vehicle and vehicle.metadata_json or {})
  local previousWorld = type(currentMetadata.world) == 'table' and currentMetadata.world or {}
  local nextWorld = mergeTable(previousWorld, normalizeWorldSnapshot(snapshot))

  return mergeTable(currentMetadata, buildFlowMetadataPatch(action, source, {
    world = nextWorld,
    last_known_garage = tostring(vehicle and vehicle.garage or '')
  }))
end

local function clampConditionSnapshotValue(value, minValue, maxValue, fallback)
  return clampNumber(value, minValue, maxValue, fallback)
end

local function buildVehicleSnapshot(vehicle)
  if not vehicle then
    return {}
  end

  return {
    id = tonumber(vehicle.id),
    owner_type = tostring(vehicle.owner_type or ''),
    owner_id = tostring(vehicle.owner_id or ''),
    plate = tostring(vehicle.plate or ''),
    model = tostring(vehicle.model or ''),
    garage = tostring(vehicle.garage or ''),
    state = tostring(vehicle.state or ''),
    fuel = tonumber(vehicle.fuel) or 0,
    engine = tonumber(vehicle.engine) or 0,
    body = tonumber(vehicle.body) or 0,
    props = cloneTable(vehicle.props_json or {}),
    metadata = cloneTable(vehicle.metadata_json or {})
  }
end

local function buildVehicleActor(actorSource, vehicle)
  if actorSource ~= nil then
    local actorPlayer = MZPlayerService.getPlayer(actorSource)
    if actorPlayer then
      return {
        type = 'player',
        id = tostring(actorPlayer.citizenid),
        source = actorSource
      }
    end

    if tonumber(actorSource) == 0 then
      return {
        type = 'console',
        id = 'console'
      }
    end

    return {
      type = 'source',
      id = tostring(actorSource)
    }
  end

  if vehicle and vehicle.owner_type == 'player' then
    return {
      type = 'player',
      id = tostring(vehicle.owner_id)
    }
  end

  if vehicle and vehicle.owner_type == 'org' then
    return {
      type = 'org',
      id = tostring(vehicle.owner_id)
    }
  end

  return {
    type = 'system',
    id = 'system'
  }
end

local function buildVehicleTarget(vehicle)
  return {
    type = 'vehicle',
    id = tostring(vehicle and vehicle.plate or 'unknown')
  }
end

local function buildVehicleContext(vehicle, extra)
  local context = cloneTable(extra or {})

  if vehicle then
    context.vehicle_id = tonumber(vehicle.id)
    context.plate = tostring(vehicle.plate or '')
    context.model = tostring(vehicle.model or '')
    context.owner_type = tostring(vehicle.owner_type or '')
    context.owner_id = tostring(vehicle.owner_id or '')
    context.garage = tostring(vehicle.garage or '')
    context.state = tostring(vehicle.state or '')
  end

  return context
end

local function logVehicleAction(action, vehicle, actorSource, beforeState, afterState, meta)
  if not MZLogService then
    return
  end

  MZLogService.createDetailed('vehicles', action, {
    actor = buildVehicleActor(actorSource, vehicle),
    target = buildVehicleTarget(vehicle),
    context = buildVehicleContext(vehicle),
    before = beforeState or {},
    after = afterState or {},
    meta = meta or {}
  })
end


function MZVehicleService.getAccessibleVehicles(source, filters)
  local player, err = getPlayerBySource(source)
  if not player then
    return false, err
  end

  filters = type(filters) == 'table' and filters or {}

  local garageFilter = tostring(filters.garage or '')
  local stateFilter = normalizeVehicleState(filters.state)
  local includeOut = filters.include_out == true
  local includeImpounded = filters.include_impounded == true

  local rows = {}
  local seenById = {}

  local function appendVehicle(vehicle)
    local vehicleId = tonumber(vehicle and vehicle.id)
    if not vehicleId or seenById[vehicleId] then
      return
    end

    local vehicleState = normalizeVehicleState(vehicle.state)
    if garageFilter ~= '' and tostring(vehicle.garage or '') ~= garageFilter then
      return
    end
    if stateFilter ~= '' and vehicleState ~= stateFilter then
      return
    end
    if not includeOut and vehicleState == STATE_OUT then
      return
    end
    if not includeImpounded and vehicleState == STATE_IMPOUNDED then
      return
    end

    seenById[vehicleId] = true
    rows[#rows + 1] = vehicle
  end

  for _, vehicle in ipairs(MZVehicleRepository.getByOwner('player', player.citizenid) or {}) do
    appendVehicle(vehicle)
  end

  for _, orgId in ipairs(getPlayerOrgIds(player.citizenid)) do
    for _, vehicle in ipairs(MZVehicleRepository.getByOwner('org', tostring(orgId)) or {}) do
      appendVehicle(vehicle)
    end
  end

  table.sort(rows, function(a, b)
    local aState = normalizeVehicleState(a.state)
    local bState = normalizeVehicleState(b.state)
    if aState ~= bState then
      return aState < bState
    end

    local aGarage = tostring(a.garage or '')
    local bGarage = tostring(b.garage or '')
    if aGarage ~= bGarage then
      return aGarage < bGarage
    end

    return (tonumber(a.id) or 0) > (tonumber(b.id) or 0)
  end)

  return true, rows
end

buildFlowMetadataPatch = function(action, actorSource, extra)
  local patch = {
    last_flow_action = tostring(action or 'unknown'),
    last_flow_at = os.time()
  }

  if actorSource ~= nil then
    local actorPlayer = MZPlayerService.getPlayer(actorSource)
    if actorPlayer and actorPlayer.citizenid then
      patch.last_flow_by = {
        type = 'player',
        citizenid = tostring(actorPlayer.citizenid),
        source = actorSource
      }
    elseif tonumber(actorSource) == 0 then
      patch.last_flow_by = {
        type = 'console',
        id = 'console'
      }
    else
      patch.last_flow_by = {
        type = 'source',
        id = tostring(actorSource)
      }
    end
  end

  for key, value in pairs(extra or {}) do
    patch[key] = value
  end

  return patch
end

function MZVehicleService.getVehicleById(id)
  id = tonumber(id)
  if not id then
    return false, 'invalid_id'
  end

  local vehicle = MZVehicleRepository.getById(id)
  if not vehicle then
    return false, 'vehicle_not_found'
  end

  return true, vehicle
end

function MZVehicleService.getVehicleByPlate(plate)
  plate = normalizePlate(plate)
  if plate == '' then
    return false, 'invalid_plate'
  end

  local vehicle = MZVehicleRepository.getByPlate(plate)
  if not vehicle then
    return false, 'vehicle_not_found'
  end

  return true, vehicle
end

function MZVehicleService.getPlayerVehicles(source)
  local player, err = getPlayerBySource(source)
  if not player then
    return false, err
  end

  local rows = MZVehicleRepository.getByOwner('player', player.citizenid)
  return true, rows
end

function MZVehicleService.getPlayerVehiclesByCitizenId(citizenid)
  citizenid = tostring(citizenid or '')
  if citizenid == '' then
    return false, 'invalid_citizenid'
  end

  local rows = MZVehicleRepository.getByOwner('player', citizenid)
  return true, rows
end

function MZVehicleService.getOrgVehicles(orgCode)
  local org = getOrgByCode(orgCode)
  if not org then
    return false, 'org_not_found'
  end

  local rows = MZVehicleRepository.getByOwner('org', tostring(org.id))
  return true, rows
end

function MZVehicleService.registerPlayerVehicle(source, model, plate, props, garage, metadata)
  local player, err = getPlayerBySource(source)
  if not player then
    return false, err
  end

  model = tostring(model or '')
  plate = normalizePlate(plate)

  if model == '' then
    return false, 'invalid_model'
  end

  if plate == '' then
    return false, 'invalid_plate'
  end

  local existing = MZVehicleRepository.getByPlate(plate)
  if existing then
    return false, 'plate_already_exists'
  end

  local insertId = MZVehicleRepository.create({
    owner_type = 'player',
    owner_id = player.citizenid,
    plate = plate,
    model = model,
    garage = garage or 'default',
    props_json = props or {},
    metadata_json = metadata or {},
    state = 'stored'
  })

  local createdVehicle = MZVehicleRepository.getById(insertId)
  if createdVehicle then
    logVehicleAction(
      'register_player_vehicle',
      createdVehicle,
      source,
      {},
      buildVehicleSnapshot(createdVehicle),
      {
        registration_type = 'player'
      }
    )
  end

  return true, insertId
end

function MZVehicleService.registerOrgVehicle(orgCode, model, plate, props, garage, metadata)
  local org = getOrgByCode(orgCode)
  if not org then
    return false, 'org_not_found'
  end

  model = tostring(model or '')
  plate = normalizePlate(plate)

  if model == '' then
    return false, 'invalid_model'
  end

  if plate == '' then
    return false, 'invalid_plate'
  end

  local existing = MZVehicleRepository.getByPlate(plate)
  if existing then
    return false, 'plate_already_exists'
  end

  local insertId = MZVehicleRepository.create({
    owner_type = 'org',
    owner_id = tostring(org.id),
    plate = plate,
    model = model,
    garage = garage or 'default',
    props_json = props or {},
    metadata_json = metadata or {},
    state = 'stored'
  })

  local createdVehicle = MZVehicleRepository.getById(insertId)
  if createdVehicle then
    logVehicleAction(
      'register_org_vehicle',
      createdVehicle,
      nil,
      {},
      buildVehicleSnapshot(createdVehicle),
      {
        registration_type = 'org',
        org_code = org.code
      }
    )
  end

  return true, insertId
end

function MZVehicleService.playerOwnsVehicle(citizenid, plate)
  citizenid = tostring(citizenid or '')
  plate = normalizePlate(plate)

  if citizenid == '' or plate == '' then
    return false
  end

  local vehicle = MZVehicleRepository.getByPlate(plate)
  if not vehicle then
    return false
  end

  return vehicle.owner_type == 'player' and tostring(vehicle.owner_id) == citizenid
end

function MZVehicleService.orgOwnsVehicle(orgCode, plate)
  local org = getOrgByCode(orgCode)
  if not org then
    return false
  end

  plate = normalizePlate(plate)
  if plate == '' then
    return false
  end

  local vehicle = MZVehicleRepository.getByPlate(plate)
  if not vehicle then
    return false
  end

  return vehicle.owner_type == 'org' and tostring(vehicle.owner_id) == tostring(org.id)
end

function MZVehicleService.canAccessVehicle(source, plate)
  local player, err = getPlayerBySource(source)
  if not player then
    return false, err
  end

  plate = normalizePlate(plate)
  if plate == '' then
    return false, 'invalid_plate'
  end

  local vehicle = MZVehicleRepository.getByPlate(plate)
  if not vehicle then
    return false, 'vehicle_not_found'
  end

  if vehicle.owner_type == 'player' then
    if tostring(vehicle.owner_id) == tostring(player.citizenid) then
      return true, vehicle
    end

    return false, 'vehicle_access_denied'
  end

  if vehicle.owner_type == 'org' then
    local orgId = tonumber(vehicle.owner_id)
    if not orgId then
      return false, 'vehicle_access_denied'
    end

    if playerHasOrgAccess(player.citizenid, orgId) then
      return true, vehicle
    end

    return false, 'vehicle_access_denied'
  end

  return false, 'vehicle_access_denied'
end

function MZVehicleService.ensureVehicleAccessForPlayer(source, plate, data, reason)
  reason = tostring(reason or 'restore')
  plate = normalizePlate(plate)
  if plate == '' then
    return false, 'invalid_plate'
  end

  local ok, vehicleOrErr = MZVehicleService.canAccessVehicle(source, plate)
  if not ok then
    print(('[mz_vehicle_world] access denied %s %s %s'):format(plate, tostring(source), reason))
    return false, vehicleOrErr
  end

  if GetResourceState('mz_vehicles') ~= 'started' then
    return false, 'mz_vehicles_not_started'
  end

  local vehicle = vehicleOrErr
  data = type(data) == 'table' and data or {}
  local metadataJson = type(vehicle.metadata_json) == 'table' and vehicle.metadata_json or {}
  local worldMetadata = type(metadataJson.world) == 'table' and metadataJson.world or {}
  local locked = data.locked
  if locked == nil then
    locked = worldMetadata.locked
  end

  local metadata = {
    kind = tostring(data.kind or vehicle.owner_type or 'persistent'),
    garage_id = tostring(data.garage_id or data.garage or vehicle.garage or ''),
    owner_type = tostring(data.owner_type or vehicle.owner_type or ''),
    owner_id = tostring(data.owner_id or vehicle.owner_id or ''),
    vehicle_id = tonumber(data.vehicle_id or data.id or vehicle.id),
    model = tostring(data.model or vehicle.model or ''),
    locked = locked,
    persistent = true,
    reason = reason
  }

  local grantOk, grantResult, grantErr = pcall(function()
    return exports['mz_vehicles']:GrantVehicleAccess(source, plate, metadata)
  end)

  if not grantOk or grantResult ~= true then
    print(('[mz_vehicle_world] access denied %s %s %s'):format(plate, tostring(source), tostring(grantErr or grantResult or 'grant_failed')))
    return false, grantErr or grantResult or 'grant_failed'
  end

  print(('[mz_vehicle_world] access granted %s %s %s'):format(plate, tostring(source), reason))
  return true, metadata
end

function MZVehicleService.setVehicleStored(plate, stored, actorSource)
  plate = normalizePlate(plate)
  if plate == '' then
    return false, 'invalid_plate'
  end

  local vehicle = MZVehicleRepository.getByPlate(plate)
  if not vehicle then
    return false, 'vehicle_not_found'
  end

  local beforeState = buildVehicleSnapshot(vehicle)
  local state = stored and STATE_STORED or STATE_OUT

  if stored == true and MZVehicleWorldService then
    MZVehicleWorldService.clearWorldState(plate, actorSource)
  end

  MZVehicleRepository.updateStateById(vehicle.id, state)

  local updatedVehicle = MZVehicleRepository.getById(vehicle.id) or vehicle
  logVehicleAction('set_vehicle_stored', updatedVehicle, actorSource, beforeState, buildVehicleSnapshot(updatedVehicle), {
    stored = stored == true
  })

  return true
end

function MZVehicleService.setVehicleGarage(plate, garage, actorSource)
  plate = normalizePlate(plate)
  garage = tostring(garage or '')

  if plate == '' then
    return false, 'invalid_plate'
  end

  if garage == '' then
    return false, 'invalid_garage'
  end

  local vehicle = MZVehicleRepository.getByPlate(plate)
  if not vehicle then
    return false, 'vehicle_not_found'
  end

  local beforeState = buildVehicleSnapshot(vehicle)

  MZVehicleRepository.updateGarageById(vehicle.id, garage)

  local updatedVehicle = MZVehicleRepository.getById(vehicle.id) or vehicle
  logVehicleAction('set_vehicle_garage', updatedVehicle, actorSource, beforeState, buildVehicleSnapshot(updatedVehicle), {
    changed_field = 'garage'
  })

  return true
end

function MZVehicleService.setVehicleState(plate, state, actorSource)
  plate = normalizePlate(plate)
  state = normalizeVehicleState(state)

  if plate == '' then
    return false, 'invalid_plate'
  end

  if state == '' then
    return false, 'invalid_state'
  end

  local vehicle = MZVehicleRepository.getByPlate(plate)
  if not vehicle then
    return false, 'vehicle_not_found'
  end

  local beforeState = buildVehicleSnapshot(vehicle)

  MZVehicleRepository.updateStateById(vehicle.id, state)

  local updatedVehicle = MZVehicleRepository.getById(vehicle.id) or vehicle
  logVehicleAction('set_vehicle_state', updatedVehicle, actorSource, beforeState, buildVehicleSnapshot(updatedVehicle), {
    changed_field = 'state'
  })

  return true
end

function MZVehicleService.setVehicleMetadata(plate, metadata, mode, actorSource)
  plate = normalizePlate(plate)
  metadata = normalizeVehicleMetadata(metadata)
  mode = tostring(mode or 'merge'):lower()

  if plate == '' then
    return false, 'invalid_plate'
  end

  local vehicle = MZVehicleRepository.getByPlate(plate)
  if not vehicle then
    return false, 'vehicle_not_found'
  end

  local currentMetadata = normalizeVehicleMetadata(vehicle.metadata_json)
  local nextMetadata = {}
  local beforeState = buildVehicleSnapshot(vehicle)

  if mode == 'replace' then
    nextMetadata = metadata
  elseif mode == 'merge' then
    nextMetadata = mergeTable(currentMetadata, metadata)
  else
    return false, 'invalid_mode'
  end

  MZVehicleRepository.updateMetadataById(vehicle.id, nextMetadata)

  local updatedVehicle = MZVehicleRepository.getById(vehicle.id) or vehicle
  logVehicleAction('set_vehicle_metadata', updatedVehicle, actorSource, beforeState, buildVehicleSnapshot(updatedVehicle), {
    changed_field = 'metadata',
    mode = mode,
    metadata_patch = cloneTable(metadata)
  })

  return true, nextMetadata
end

function MZVehicleService.setVehicleProps(plate, props, actorSource)
  plate = normalizePlate(plate)
  if plate == '' then
    return false, 'invalid_plate'
  end

  local vehicle = MZVehicleRepository.getByPlate(plate)
  if not vehicle then
    return false, 'vehicle_not_found'
  end

  local beforeState = buildVehicleSnapshot(vehicle)

  MZVehicleRepository.updatePropsById(vehicle.id, props or {})

  local updatedVehicle = MZVehicleRepository.getById(vehicle.id) or vehicle
  logVehicleAction('set_vehicle_props', updatedVehicle, actorSource, beforeState, buildVehicleSnapshot(updatedVehicle), {
    changed_field = 'props'
  })

  return true
end

function MZVehicleService.setVehicleCondition(plate, fuel, engine, body, actorSource)
  plate = normalizePlate(plate)
  if plate == '' then
    return false, 'invalid_plate'
  end

  local vehicle = MZVehicleRepository.getByPlate(plate)
  if not vehicle then
    return false, 'vehicle_not_found'
  end

  local beforeState = buildVehicleSnapshot(vehicle)

  MZVehicleRepository.updateConditionById(vehicle.id, fuel, engine, body)

  local updatedVehicle = MZVehicleRepository.getById(vehicle.id) or vehicle
  logVehicleAction('set_vehicle_condition', updatedVehicle, actorSource, beforeState, buildVehicleSnapshot(updatedVehicle), {
    changed_fields = {
      fuel = fuel,
      engine = engine,
      body = body
    }
  })

  return true
end

function MZVehicleService.getOutVehiclesForRespawn(source)
  local player = MZPlayerService and MZPlayerService.getPlayer and MZPlayerService.getPlayer(source) or nil
  debugVehicleWorld(('loading out vehicles for player %s %s'):format(
    tostring(source),
    tostring(player and player.citizenid or 'unknown')
  ))

  local ok, vehiclesOrErr = MZVehicleService.getAccessibleVehicles(source, {
    state = STATE_OUT,
    include_out = true,
    include_impounded = false
  })

  if not ok then
    return false, vehiclesOrErr
  end

  if not MZVehicleWorldService then
    return false, 'world_service_unavailable'
  end

  local respawnOk, outVehicles = MZVehicleWorldService.getOutVehiclesForRespawn(vehiclesOrErr)
  if respawnOk == true then
    for _, vehicle in ipairs(vehiclesOrErr or {}) do
      if normalizeVehicleState(vehicle.state) == STATE_OUT then
        MZVehicleService.ensureVehicleAccessForPlayer(source, vehicle.plate, vehicle, 'get_out_respawn')
      end
    end
  end
  debugVehicleWorld(('out vehicles found %s'):format(respawnOk and #(outVehicles or {}) or 0))
  return respawnOk, outVehicles
end

function MZVehicleService.restoreWorldVehiclesForPlayer(source, reason)
  reason = tostring(reason or 'restore')
  local player = MZPlayerService and MZPlayerService.getPlayer and MZPlayerService.getPlayer(source) or nil
  if not player then
    return false, 'player_not_loaded'
  end

  print(('[mz_vehicle_world] restore start %s %s %s'):format(reason, tostring(source), tostring(player.citizenid or 'unknown')))
  print(('[mz_vehicle_world] player loaded restore %s %s'):format(tostring(source), tostring(player.citizenid or 'unknown')))

  local ok, vehiclesOrErr = MZVehicleService.getAccessibleVehicles(source, {
    state = STATE_OUT,
    include_out = true,
    include_impounded = false
  })

  if not ok then
    print(('[mz_vehicle_world] out vehicles found 0'))
    return false, vehiclesOrErr
  end

  print(('[mz_vehicle_world] out vehicles found %s'):format(#(vehiclesOrErr or {})))

  if not MZVehicleWorldService or not MZVehicleWorldService.RestoreOutVehiclesForPlayer then
    return false, 'world_service_unavailable'
  end

  for _, vehicle in ipairs(vehiclesOrErr or {}) do
    if normalizeVehicleState(vehicle.state) == STATE_OUT then
      MZVehicleService.ensureVehicleAccessForPlayer(source, vehicle.plate, vehicle, reason)
    end
  end

  return MZVehicleWorldService.RestoreOutVehiclesForPlayer(source, vehiclesOrErr, reason)
end

function MZVehicleService.registerOutVehicleEntity(source, plate, netId, snapshot)
  local ok, vehicleOrErr = MZVehicleService.canAccessVehicle(source, plate)
  if not ok then
    return false, vehicleOrErr
  end

  local vehicle = vehicleOrErr
  plate = normalizePlate(vehicle.plate)

  if normalizeVehicleState(vehicle.state) ~= STATE_OUT then
    return false, 'vehicle_not_out'
  end

  if not MZVehicleWorldService then
    return false, 'world_service_unavailable'
  end

  snapshot = type(snapshot) == 'table' and snapshot or {}
  netId = tonumber(netId) or tonumber(snapshot.net_id or snapshot.netId) or 0

  if netId > 0 then
    local isSpawned, _, reason = MZVehicleWorldService.isSpawned(plate, netId)
    if isSpawned and reason == 'different_net_id' then
      debugVehicleWorld(('skip duplicate %s'):format(plate))
      return false, 'vehicle_already_spawned'
    end

    local registered, registerErr = MZVehicleWorldService.registerEntity(vehicle, source, netId)
    if registered ~= true then
      debugVehicleWorld(('register entity failed, saving snapshot anyway %s %s'):format(plate, tostring(registerErr or 'entity_not_found')))
    end
  else
    debugVehicleWorld(('invalid net id, saving snapshot anyway %s'):format(plate))
  end

  local updateOk, updateResult = MZVehicleService.updateOutVehicleSnapshot(source, plate, snapshot)
  if updateOk == true then
    MZVehicleService.ensureVehicleAccessForPlayer(source, plate, updateResult or vehicle, 'register_entity')
  end

  return updateOk, updateResult
end

function MZVehicleService.updateOutVehicleSnapshot(source, plate, snapshot)
  local ok, vehicleOrErr = MZVehicleService.canAccessVehicle(source, plate)
  if not ok then
    return false, vehicleOrErr
  end

  local vehicle = vehicleOrErr
  if normalizeVehicleState(vehicle.state) ~= STATE_OUT then
    return false, 'vehicle_not_out'
  end

  snapshot = type(snapshot) == 'table' and snapshot or {}
  plate = normalizePlate(vehicle.plate)

  local netId = tonumber(snapshot.net_id or snapshot.netId)
  local beforeState = buildVehicleSnapshot(vehicle)
  local nextFuel = clampConditionSnapshotValue(snapshot.fuel, 0, 100, tonumber(vehicle.fuel) or 100)
  local nextEngine = clampConditionSnapshotValue(snapshot.engine, 0, 1000, tonumber(vehicle.engine) or 1000)
  local nextBody = clampConditionSnapshotValue(snapshot.body, 0, 1000, tonumber(vehicle.body) or 1000)
  local nextProps = type(snapshot.props) == 'table' and snapshot.props or (vehicle.props_json or {})
  local nextMetadata = buildOutVehicleMetadata(vehicle, source, 'out_snapshot', snapshot)

  if MZVehicleWorldService then
    MZVehicleWorldService.saveSnapshot(vehicle, source, snapshot)
  end

  MZVehicleRepository.updateVehicleFlowById(vehicle.id, {
    garage = vehicle.garage or 'default',
    state = STATE_OUT,
    fuel = nextFuel,
    engine = nextEngine,
    body = nextBody,
    props_json = nextProps,
    impound_data = vehicle.impound_data or {},
    metadata_json = nextMetadata
  })

  local updatedVehicle = MZVehicleRepository.getById(vehicle.id) or vehicle
  logVehicleAction('out_vehicle_snapshot', updatedVehicle, source, beforeState, buildVehicleSnapshot(updatedVehicle), {
    net_id = netId,
    has_coords = normalizeCoords(snapshot.coords or snapshot.last_coords) ~= nil
  })

  return true, updatedVehicle
end

function MZVehicleService.markOutVehicleDestroyed(source, plate, snapshot)
  local ok, vehicleOrErr = MZVehicleService.canAccessVehicle(source, plate)
  if not ok then
    return false, vehicleOrErr
  end

  local vehicle = vehicleOrErr
  if normalizeVehicleState(vehicle.state) ~= STATE_OUT then
    return false, 'vehicle_not_out'
  end

  snapshot = type(snapshot) == 'table' and snapshot or {}
  snapshot.destroyed = true

  if MZVehicleWorldService then
    MZVehicleWorldService.markDestroyed(vehicle, source, snapshot)
  end

  return MZVehicleService.updateOutVehicleSnapshot(source, plate, snapshot)
end

function MZVehicleService.takeOutVehicle(source, plate, expectedGarage)
  local ok, vehicleOrErr = MZVehicleService.canAccessVehicle(source, plate)
  if not ok then
    return false, vehicleOrErr
  end

  local vehicle = vehicleOrErr
  expectedGarage = tostring(expectedGarage or '')

  if isImpoundedState(vehicle.state) then
    return false, 'vehicle_impounded'
  end

  if normalizeVehicleState(vehicle.state) == STATE_OUT then
    return false, 'vehicle_already_out'
  end

  if expectedGarage ~= '' and tostring(vehicle.garage or '') ~= expectedGarage then
    return false, 'vehicle_wrong_garage'
  end

  local beforeState = buildVehicleSnapshot(vehicle)

  local nextMetadata = mergeTable(vehicle.metadata_json or {}, buildFlowMetadataPatch('take_out', source, {
    last_known_garage = tostring(vehicle.garage or ''),
    last_take_out_garage = expectedGarage ~= '' and expectedGarage or tostring(vehicle.garage or ''),
    world = mergeTable(
      type(vehicle.metadata_json) == 'table' and type(vehicle.metadata_json.world) == 'table' and vehicle.metadata_json.world or {},
      {
        persistent = true,
        updated_at = os.time()
      }
    )
  }))

  MZVehicleRepository.updateVehicleFlowById(vehicle.id, {
    garage = vehicle.garage or 'default',
    state = STATE_OUT,
    fuel = vehicle.fuel,
    engine = vehicle.engine,
    body = vehicle.body,
    props_json = vehicle.props_json or {},
    impound_data = vehicle.impound_data or {},
    metadata_json = nextMetadata
  })

  local updatedVehicle = MZVehicleRepository.getById(vehicle.id) or vehicle

  if MZVehicleWorldService then
    MZVehicleWorldService.registerOutVehicle(updatedVehicle, source, {
      fuel = updatedVehicle.fuel,
      engine = updatedVehicle.engine,
      body = updatedVehicle.body,
      props = updatedVehicle.props_json or {}
    })
  end

  logVehicleAction('take_out_vehicle', updatedVehicle, source, beforeState, buildVehicleSnapshot(updatedVehicle), {
    expected_garage = expectedGarage ~= '' and expectedGarage or nil
  })

  return true, updatedVehicle
end

function MZVehicleService.storeVehicle(source, plate, garage, props, fuel, engine, body)
  local ok, vehicleOrErr = MZVehicleService.canAccessVehicle(source, plate)
  if not ok then
    return false, vehicleOrErr
  end

  local vehicle = vehicleOrErr
  garage = tostring(garage or '')

  if garage == '' then
    return false, 'invalid_garage'
  end

  if isImpoundedState(vehicle.state) then
    return false, 'vehicle_impounded'
  end

  local beforeState = buildVehicleSnapshot(vehicle)

  local nextFuel = clampNumber(fuel, 0, 100, tonumber(vehicle.fuel) or 100)
  local nextEngine = clampNumber(engine, 0, 1000, tonumber(vehicle.engine) or 1000)
  local nextBody = clampNumber(body, 0, 1000, tonumber(vehicle.body) or 1000)
  local nextProps = type(props) == 'table' and props or (vehicle.props_json or {})
  local nextMetadata = mergeTable(vehicle.metadata_json or {}, buildFlowMetadataPatch('store', source, {
    last_known_garage = garage,
    last_store_garage = garage,
    world = mergeTable(
      type(vehicle.metadata_json) == 'table' and type(vehicle.metadata_json.world) == 'table' and vehicle.metadata_json.world or {},
      {
        persistent = false,
        net_id = 0,
        stored_at = os.time(),
        updated_at = os.time()
      }
    )
  }))
  local nextImpoundData = vehicle.impound_data or {}

  MZVehicleRepository.updateVehicleFlowById(vehicle.id, {
    garage = garage,
    state = STATE_STORED,
    fuel = nextFuel,
    engine = nextEngine,
    body = nextBody,
    props_json = nextProps,
    impound_data = nextImpoundData,
    metadata_json = nextMetadata
  })

  if MZVehicleWorldService then
    MZVehicleWorldService.clearWorldState(plate, source)
  end

  local updatedVehicle = MZVehicleRepository.getById(vehicle.id) or vehicle

  logVehicleAction('store_vehicle', updatedVehicle, source, beforeState, buildVehicleSnapshot(updatedVehicle), {
    garage = garage
  })

  return true, updatedVehicle
end

function MZVehicleService.impoundVehicle(plate, reason, actorSource, extraData)
  plate = normalizePlate(plate)
  if plate == '' then
    return false, 'invalid_plate'
  end

  local vehicle = MZVehicleRepository.getByPlate(plate)
  if not vehicle then
    return false, 'vehicle_not_found'
  end

  local beforeState = buildVehicleSnapshot(vehicle)

  local impoundData = buildImpoundData(reason, actorSource, extraData)
  local nextMetadata = mergeTable(vehicle.metadata_json or {}, buildFlowMetadataPatch('impound', actorSource, {
    last_known_garage = tostring(vehicle.garage or ''),
    last_impound_reason = tostring(reason or 'impounded')
  }))

  MZVehicleRepository.updateVehicleFlowById(vehicle.id, {
    garage = vehicle.garage or 'default',
    state = STATE_IMPOUNDED,
    fuel = vehicle.fuel,
    engine = vehicle.engine,
    body = vehicle.body,
    props_json = vehicle.props_json or {},
    impound_data = impoundData,
    metadata_json = nextMetadata
  })

  local updatedVehicle = MZVehicleRepository.getById(vehicle.id) or vehicle

  logVehicleAction('impound_vehicle', updatedVehicle, actorSource, beforeState, buildVehicleSnapshot(updatedVehicle), {
    reason = tostring(reason or 'impounded'),
    impound_data = impoundData
  })

  return true, updatedVehicle
end

function MZVehicleService.releaseImpound(plate, garage, actorSource)
  plate = normalizePlate(plate)
  garage = tostring(garage or '')

  if plate == '' then
    return false, 'invalid_plate'
  end

  if garage == '' then
    return false, 'invalid_garage'
  end

  local vehicle = MZVehicleRepository.getByPlate(plate)
  if not vehicle then
    return false, 'vehicle_not_found'
  end

  if not isImpoundedState(vehicle.state) then
    return false, 'vehicle_not_impounded'
  end

  local beforeState = buildVehicleSnapshot(vehicle)

  local nextMetadata = mergeTable(vehicle.metadata_json or {}, buildFlowMetadataPatch('release_impound', actorSource, {
    last_known_garage = garage,
    last_release_garage = garage
  }))

  MZVehicleRepository.updateVehicleFlowById(vehicle.id, {
    garage = garage,
    state = STATE_STORED,
    fuel = vehicle.fuel,
    engine = vehicle.engine,
    body = vehicle.body,
    props_json = vehicle.props_json or {},
    impound_data = {},
    metadata_json = nextMetadata
  })

  local updatedVehicle = MZVehicleRepository.getById(vehicle.id) or vehicle

  logVehicleAction('release_impound_vehicle', updatedVehicle, actorSource, beforeState, buildVehicleSnapshot(updatedVehicle), {
    garage = garage
  })

  return true, updatedVehicle
end
