MZVehicleRepository = {}

local VehicleStates = (MZConstants and MZConstants.VehicleStates) or {}
local STATE_STORED = VehicleStates.STORED or 'stored'
local STATE_IMPOUNDED = VehicleStates.IMPOUNDED or VehicleStates.IMPOUND or 'impounded'

local function normalizeVehicleState(state)
  state = tostring(state or ''):lower()

  if state == 'impound' or state == 'impounded' then
    return STATE_IMPOUNDED
  end

  return state
end

local function decodeVehicleRow(row)
  if not row then
    return nil
  end

  row.props_json = MZUtils.jsonDecode(row.props_json or '{}') or {}
  row.impound_data = MZUtils.jsonDecode(row.impound_data or '{}') or {}
  row.metadata_json = MZUtils.jsonDecode(row.metadata_json or '{}') or {}

  row.fuel = tonumber(row.fuel) or 100
  row.engine = tonumber(row.engine) or 1000
  row.body = tonumber(row.body) or 1000
  row.id = tonumber(row.id)
  row.state = normalizeVehicleState(row.state)
  row.stored = row.state == STATE_STORED

  return row
end

local function decodeVehicleRows(rows)
  local out = {}
  for _, row in ipairs(rows or {}) do
    out[#out + 1] = decodeVehicleRow(row)
  end
  return out
end

function MZVehicleRepository.create(data)
  return MySQL.insert.await([[
    INSERT INTO mz_player_vehicles (
      owner_type,
      owner_id,
      plate,
      model,
      category,
      garage,
      state,
      fuel,
      engine,
      body,
      props_json,
      impound_data,
      metadata_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    data.owner_type,
    data.owner_id,
    data.plate,
    data.model,
    data.category or 'car',
    data.garage or 'default',
    normalizeVehicleState(data.state) ~= '' and normalizeVehicleState(data.state) or STATE_STORED,
    tonumber(data.fuel) or 100,
    tonumber(data.engine) or 1000,
    tonumber(data.body) or 1000,
    MZUtils.jsonEncode(data.props_json or {}),
    MZUtils.jsonEncode(data.impound_data or {}),
    MZUtils.jsonEncode(data.metadata_json or {})
  })
end

function MZVehicleRepository.getById(id)
  local row = MySQL.single.await([[
    SELECT *
    FROM mz_player_vehicles
    WHERE id = ?
    LIMIT 1
  ]], { id })

  return decodeVehicleRow(row)
end

function MZVehicleRepository.getByPlate(plate)
  local row = MySQL.single.await([[
    SELECT *
    FROM mz_player_vehicles
    WHERE plate = ?
    LIMIT 1
  ]], { plate })

  return decodeVehicleRow(row)
end

function MZVehicleRepository.getByOwner(ownerType, ownerId)
  local rows = MySQL.query.await([[
    SELECT *
    FROM mz_player_vehicles
    WHERE owner_type = ? AND owner_id = ?
    ORDER BY id DESC
  ]], { ownerType, ownerId }) or {}

  return decodeVehicleRows(rows)
end

function MZVehicleRepository.updateStateById(id, state)
  state = normalizeVehicleState(state)

  return MySQL.update.await([[
    UPDATE mz_player_vehicles
    SET state = ?
    WHERE id = ?
  ]], { state ~= '' and state or STATE_STORED, id })
end

function MZVehicleRepository.updateGarageById(id, garage)
  return MySQL.update.await([[
    UPDATE mz_player_vehicles
    SET garage = ?
    WHERE id = ?
  ]], { garage, id })
end

function MZVehicleRepository.updatePropsById(id, props)
  return MySQL.update.await([[
    UPDATE mz_player_vehicles
    SET props_json = ?
    WHERE id = ?
  ]], { MZUtils.jsonEncode(props or {}), id })
end

function MZVehicleRepository.updateMetadataById(id, metadata)
  return MySQL.update.await([[
    UPDATE mz_player_vehicles
    SET metadata_json = ?
    WHERE id = ?
  ]], { MZUtils.jsonEncode(metadata or {}), id })
end

function MZVehicleRepository.updateConditionById(id, fuel, engine, body)
  return MySQL.update.await([[
    UPDATE mz_player_vehicles
    SET fuel = ?, engine = ?, body = ?
    WHERE id = ?
  ]], {
    tonumber(fuel) or 100,
    tonumber(engine) or 1000,
    tonumber(body) or 1000,
    id
  })
end

function MZVehicleRepository.updateStateGarageById(id, state, garage)
  state = normalizeVehicleState(state)

  return MySQL.update.await([[
    UPDATE mz_player_vehicles
    SET state = ?, garage = ?
    WHERE id = ?
  ]], { state ~= '' and state or STATE_STORED, garage, id })
end

function MZVehicleRepository.updateImpoundDataById(id, impoundData)
  return MySQL.update.await([[
    UPDATE mz_player_vehicles
    SET impound_data = ?
    WHERE id = ?
  ]], { MZUtils.jsonEncode(impoundData or {}), id })
end

function MZVehicleRepository.updateVehicleFlowById(id, data)
  local state = normalizeVehicleState(data.state)

  return MySQL.update.await([[
    UPDATE mz_player_vehicles
    SET
      garage = ?,
      state = ?,
      fuel = ?,
      engine = ?,
      body = ?,
      props_json = ?,
      impound_data = ?,
      metadata_json = ?
    WHERE id = ?
  ]], {
    data.garage or 'default',
    state ~= '' and state or STATE_STORED,
    tonumber(data.fuel) or 100,
    tonumber(data.engine) or 1000,
    tonumber(data.body) or 1000,
    MZUtils.jsonEncode(data.props_json or {}),
    MZUtils.jsonEncode(data.impound_data or {}),
    MZUtils.jsonEncode(data.metadata_json or {}),
    id
  })
end
