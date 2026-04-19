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

local function buildFlowMetadataPatch(action, actorSource, extra)
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
    last_take_out_garage = expectedGarage ~= '' and expectedGarage or tostring(vehicle.garage or '')
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
    last_store_garage = garage
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
