local function reply(msg)
  print(('[mz_core] %s'):format(msg))
end

local function canUseVehicleCommand(source)
  return source == 0
end

RegisterCommand('mveh_add_player', function(source, args)
  if not canUseVehicleCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local model = tostring(args[2] or '')
  local plate = tostring(args[3] or '')
  local garage = tostring(args[4] or 'default')

  if not targetSource or model == '' or plate == '' then
    return reply('Uso: mveh_add_player [source] [model] [plate] [garage opcional]')
  end

  local ok, result = exports['mz_core']:RegisterPlayerVehicle(targetSource, model, plate, {}, garage, {})
  if not ok then
    return reply(('Erro: %s'):format(result or 'unknown'))
  end

  reply(('Veículo de player registrado: source=%s model=%s plate=%s garage=%s id=%s'):format(
    targetSource,
    model,
    plate,
    garage,
    tostring(result)
  ))
end, true)

RegisterCommand('mveh_add_org', function(source, args)
  if not canUseVehicleCommand(source) then
    return reply('Sem permissão.')
  end

  local orgCode = tostring(args[1] or '')
  local model = tostring(args[2] or '')
  local plate = tostring(args[3] or '')
  local garage = tostring(args[4] or 'default')

  if orgCode == '' or model == '' or plate == '' then
    return reply('Uso: mveh_add_org [orgCode] [model] [plate] [garage opcional]')
  end

  local ok, result = exports['mz_core']:RegisterOrgVehicle(orgCode, model, plate, {}, garage, {})
  if not ok then
    return reply(('Erro: %s'):format(result or 'unknown'))
  end

  reply(('Veículo de org registrado: org=%s model=%s plate=%s garage=%s id=%s'):format(
    orgCode,
    model,
    plate,
    garage,
    tostring(result)
  ))
end, true)

RegisterCommand('mveh_info_plate', function(source, args)
  if not canUseVehicleCommand(source) then
    return reply('Sem permissão.')
  end

  local plate = tostring(args[1] or '')
  if plate == '' then
    return reply('Uso: mveh_info_plate [plate]')
  end

  local ok, vehicle = exports['mz_core']:GetVehicleByPlate(plate)
  if not ok then
    return reply(('Erro: %s'):format(vehicle or 'unknown'))
  end

  local metadataText = '{}'
  local propsText = '{}'
  local impoundText = '{}'

  if type(vehicle.metadata_json) == 'table' then
    metadataText = json.encode(vehicle.metadata_json) or '{}'
  end

  if type(vehicle.props_json) == 'table' then
    propsText = json.encode(vehicle.props_json) or '{}'
  end

  if type(vehicle.impound_data) == 'table' then
    impoundText = json.encode(vehicle.impound_data) or '{}'
  end

  reply(('Veículo plate=%s | id=%s | owner_type=%s | owner_id=%s | model=%s | garage=%s | state=%s | fuel=%s | engine=%s | body=%s'):format(
    tostring(vehicle.plate),
    tostring(vehicle.id),
    tostring(vehicle.owner_type),
    tostring(vehicle.owner_id),
    tostring(vehicle.model),
    tostring(vehicle.garage),
    tostring(vehicle.state),
    tostring(vehicle.fuel),
    tostring(vehicle.engine),
    tostring(vehicle.body)
  ))

  reply(('props=%s'):format(propsText))
  reply(('metadata=%s'):format(metadataText))
  reply(('impound=%s'):format(impoundText))
end, true)

RegisterCommand('mveh_info_id', function(source, args)
  if not canUseVehicleCommand(source) then
    return reply('Sem permissão.')
  end

  local vehicleId = tonumber(args[1])
  if not vehicleId then
    return reply('Uso: mveh_info_id [id]')
  end

  local ok, vehicle = exports['mz_core']:GetVehicleById(vehicleId)
  if not ok then
    return reply(('Erro: %s'):format(vehicle or 'unknown'))
  end

  local metadataText = '{}'
  local propsText = '{}'
  local impoundText = '{}'

  if type(vehicle.metadata_json) == 'table' then
    metadataText = json.encode(vehicle.metadata_json) or '{}'
  end

  if type(vehicle.props_json) == 'table' then
    propsText = json.encode(vehicle.props_json) or '{}'
  end

  if type(vehicle.impound_data) == 'table' then
    impoundText = json.encode(vehicle.impound_data) or '{}'
  end

  reply(('Veículo id=%s | plate=%s | owner_type=%s | owner_id=%s | model=%s | garage=%s | state=%s | fuel=%s | engine=%s | body=%s'):format(
    tostring(vehicle.id),
    tostring(vehicle.plate),
    tostring(vehicle.owner_type),
    tostring(vehicle.owner_id),
    tostring(vehicle.model),
    tostring(vehicle.garage),
    tostring(vehicle.state),
    tostring(vehicle.fuel),
    tostring(vehicle.engine),
    tostring(vehicle.body)
  ))

  reply(('props=%s'):format(propsText))
  reply(('metadata=%s'):format(metadataText))
  reply(('impound=%s'):format(impoundText))
end, true)

RegisterCommand('mveh_restore_world', function(source)
  if source == 0 then
    return reply('Use este comando dentro do jogo para restaurar os veiculos out do seu personagem.')
  end

  if not MZVehicleService or not MZVehicleService.restoreWorldVehiclesForPlayer then
    return reply('Restore world indisponivel.')
  end

  local ok, result = MZVehicleService.restoreWorldVehiclesForPlayer(source, 'command')
  if not ok then
    return reply(('Restore world falhou: %s'):format(tostring(result or 'unknown_error')))
  end

  reply(('Restore world solicitado: restored=%s failed=%s'):format(
    tostring(type(result) == 'table' and result.restored or 0),
    tostring(type(result) == 'table' and result.failed or 0)
  ))
end, false)

RegisterCommand('mveh_list_player', function(source, args)
  if not canUseVehicleCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  if not targetSource then
    return reply('Uso: mveh_list_player [source]')
  end

  local ok, vehicles = exports['mz_core']:GetPlayerVehicles(targetSource)
  if not ok then
    return reply(('Erro: %s'):format(vehicles or 'unknown'))
  end

  reply(('Veículos do source %s:'):format(targetSource))

  if type(vehicles) ~= 'table' or #vehicles == 0 then
    return reply('(vazio)')
  end

  for _, vehicle in ipairs(vehicles) do
    reply(('- id=%s | plate=%s | model=%s | owner_type=%s | owner_id=%s | garage=%s | state=%s'):format(
      tostring(vehicle.id),
      tostring(vehicle.plate),
      tostring(vehicle.model),
      tostring(vehicle.owner_type),
      tostring(vehicle.owner_id),
      tostring(vehicle.garage),
      tostring(vehicle.state)
    ))
  end
end, true)

RegisterCommand('mveh_list_org', function(source, args)
  if not canUseVehicleCommand(source) then
    return reply('Sem permissão.')
  end

  local orgCode = tostring(args[1] or '')
  if orgCode == '' then
    return reply('Uso: mveh_list_org [orgCode]')
  end

  local ok, vehicles = exports['mz_core']:GetOrgVehicles(orgCode)
  if not ok then
    return reply(('Erro: %s'):format(vehicles or 'unknown'))
  end

  reply(('Veículos da org %s:'):format(orgCode))

  if type(vehicles) ~= 'table' or #vehicles == 0 then
    return reply('(vazio)')
  end

  for _, vehicle in ipairs(vehicles) do
    reply(('- id=%s | plate=%s | model=%s | owner_type=%s | owner_id=%s | garage=%s | state=%s'):format(
      tostring(vehicle.id),
      tostring(vehicle.plate),
      tostring(vehicle.model),
      tostring(vehicle.owner_type),
      tostring(vehicle.owner_id),
      tostring(vehicle.garage),
      tostring(vehicle.state)
    ))
  end
end, true)

RegisterCommand('mveh_list_accessible', function(source, args)
  if not canUseVehicleCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local garage = tostring(args[2] or '')
  local includeOut = tostring(args[3] or '') == '1'
  local includeImpounded = tostring(args[4] or '') == '1'

  if not targetSource then
    return reply('Uso: mveh_list_accessible [source] [garage opcional] [includeOut 0/1] [includeImpounded 0/1]')
  end

  local ok, vehicles = exports['mz_core']:GetAccessibleVehicles(targetSource, {
    garage = garage ~= '' and garage or nil,
    include_out = includeOut,
    include_impounded = includeImpounded
  })
  if not ok then
    return reply(('Erro: %s'):format(vehicles or 'unknown'))
  end

  reply(('Veículos acessíveis do source %s:'):format(targetSource))

  if type(vehicles) ~= 'table' or #vehicles == 0 then
    return reply('(vazio)')
  end

  for _, vehicle in ipairs(vehicles) do
    reply(('- id=%s | plate=%s | model=%s | owner_type=%s | owner_id=%s | garage=%s | state=%s'):format(
      tostring(vehicle.id),
      tostring(vehicle.plate),
      tostring(vehicle.model),
      tostring(vehicle.owner_type),
      tostring(vehicle.owner_id),
      tostring(vehicle.garage),
      tostring(vehicle.state)
    ))
  end
end, true)

RegisterCommand('mveh_can_access', function(source, args)
  if not canUseVehicleCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local plate = tostring(args[2] or '')

  if not targetSource or plate == '' then
    return reply('Uso: mveh_can_access [source] [plate]')
  end

  local ok, result = exports['mz_core']:CanAccessVehicle(targetSource, plate)
  if not ok then
    return reply(('Acesso negado/erro: %s'):format(result or 'unknown'))
  end

  reply(('Acesso permitido: source=%s plate=%s owner_type=%s owner_id=%s'):format(
    targetSource,
    tostring(result.plate),
    tostring(result.owner_type),
    tostring(result.owner_id)
  ))
end, true)

RegisterCommand('mveh_set_stored', function(source, args)
  if not canUseVehicleCommand(source) then
    return reply('Sem permissão.')
  end

  local plate = tostring(args[1] or '')
  local storedRaw = tostring(args[2] or '')

  if plate == '' or storedRaw == '' then
    return reply('Uso: mveh_set_stored [plate] [0/1]')
  end

  local stored = storedRaw == '1' or storedRaw:lower() == 'true'

  local ok, err = exports['mz_core']:SetVehicleStored(plate, stored)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Stored atualizado: plate=%s stored=%s'):format(plate, tostring(stored)))
end, true)

RegisterCommand('mveh_set_garage', function(source, args)
  if not canUseVehicleCommand(source) then
    return reply('Sem permissão.')
  end

  local plate = tostring(args[1] or '')
  local garage = tostring(args[2] or '')

  if plate == '' or garage == '' then
    return reply('Uso: mveh_set_garage [plate] [garage]')
  end

  local ok, err = exports['mz_core']:SetVehicleGarage(plate, garage)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Garage atualizado: plate=%s garage=%s'):format(plate, garage))
end, true)

RegisterCommand('mveh_set_state', function(source, args)
  if not canUseVehicleCommand(source) then
    return reply('Sem permissão.')
  end

  local plate = tostring(args[1] or '')
  local state = tostring(args[2] or '')

  if plate == '' or state == '' then
    return reply('Uso: mveh_set_state [plate] [state]')
  end

  local ok, err = exports['mz_core']:SetVehicleState(plate, state)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('State atualizado: plate=%s state=%s'):format(plate, state))
end, true)

RegisterCommand('mveh_set_meta', function(source, args)
  if not canUseVehicleCommand(source) then
    return reply('Sem permissão.')
  end

  local plate = tostring(args[1] or '')
  local key = tostring(args[2] or '')
  local value = tostring(args[3] or '')
  local mode = tostring(args[4] or 'merge')

  if plate == '' or key == '' then
    return reply('Uso: mveh_set_meta [plate] [key] [value] [merge/replace opcional]')
  end

  local metadata = {}
  metadata[key] = value

  local ok, result = exports['mz_core']:SetVehicleMetadata(plate, metadata, mode)
  if not ok then
    return reply(('Erro: %s'):format(result or 'unknown'))
  end

  local metadataText = '{}'
  if type(result) == 'table' then
    metadataText = json.encode(result) or '{}'
  end

  reply(('Metadata atualizada: plate=%s mode=%s metadata=%s'):format(
    plate,
    mode,
    metadataText
  ))
end, true)

RegisterCommand('mveh_set_condition', function(source, args)
  if not canUseVehicleCommand(source) then
    return reply('Sem permissão.')
  end

  local plate = tostring(args[1] or '')
  local fuel = tonumber(args[2])
  local engine = tonumber(args[3])
  local body = tonumber(args[4])

  if plate == '' or not fuel or not engine or not body then
    return reply('Uso: mveh_set_condition [plate] [fuel] [engine] [body]')
  end

  local ok, err = exports['mz_core']:SetVehicleCondition(plate, fuel, engine, body)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Condition atualizada: plate=%s fuel=%s engine=%s body=%s'):format(
    plate,
    fuel,
    engine,
    body
  ))
end, true)
