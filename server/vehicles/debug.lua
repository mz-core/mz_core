if not MZVehicleService then
  print('[mz_core] vehicles debug not loaded: MZVehicleService missing')
  return
end

local DEBUG_ACE = 'mzcore.debug'
local DEBUG_ALLOW_CONSOLE = true

local function isDebugAllowed(source)
  if source == 0 then
    return DEBUG_ALLOW_CONSOLE
  end

  if Config and Config.Debug == true then
    return true
  end

  return IsPlayerAceAllowed(source, DEBUG_ACE)
end

local function debugPrint(source, message)
  if source == 0 then
    print(('[mz_core][vehicles_debug] %s'):format(message))
    return
  end

  TriggerClientEvent('chat:addMessage', source, {
    color = { 255, 200, 0 },
    multiline = false,
    args = { 'mz_core', message }
  })
end

local function dumpVehicleShort(vehicle)
  if not vehicle then
    return 'nil'
  end

  return ('id=%s plate=%s owner_type=%s owner_id=%s garage=%s state=%s fuel=%s engine=%s body=%s'):format(
    tostring(vehicle.id),
    tostring(vehicle.plate),
    tostring(vehicle.owner_type),
    tostring(vehicle.owner_id),
    tostring(vehicle.garage),
    tostring(vehicle.state),
    tostring(vehicle.fuel),
    tostring(vehicle.engine),
    tostring(vehicle.body)
  )
end

RegisterCommand('mveh_register_org', function(source, args)
  if not isDebugAllowed(source) then
    debugPrint(source, 'Sem permissão.')
    return
  end

  local orgCode = tostring(args[1] or '')
  local model = tostring(args[2] or 'adder')
  local plate = tostring(args[3] or 'DBG001')
  local garage = tostring(args[4] or 'default')

  if orgCode == '' then
    debugPrint(source, 'Uso: mveh_register_org [orgCode] [model] [plate] [garage]')
    return
  end

  local ok, result = MZVehicleService.registerOrgVehicle(orgCode, model, plate, {}, garage, {
    debug = true
  })

  if ok then
    debugPrint(source, ('register org ok | id=%s | plate=%s'):format(tostring(result), plate))
  else
    debugPrint(source, ('register org falhou | err=%s'):format(tostring(result)))
  end
end, false)

RegisterCommand('mveh_info', function(source, args)
  if not isDebugAllowed(source) then
    debugPrint(source, 'Sem permissão.')
    return
  end

  local plate = tostring(args[1] or '')
  if plate == '' then
    debugPrint(source, 'Uso: mveh_info [plate]')
    return
  end

  local ok, result = MZVehicleService.getVehicleByPlate(plate)
  if not ok then
    debugPrint(source, ('info falhou | err=%s'):format(tostring(result)))
    return
  end

  debugPrint(source, dumpVehicleShort(result))
end, false)

RegisterCommand('mveh_out', function(source, args)
  if not isDebugAllowed(source) then
    debugPrint(source, 'Sem permissão.')
    return
  end

  local plate = tostring(args[1] or '')
  local garage = tostring(args[2] or '')

  if plate == '' then
    debugPrint(source, 'Uso: mveh_out [plate] [garage opcional]')
    return
  end

  local ok, result = MZVehicleService.takeOutVehicle(source, plate, garage)
  if not ok then
    debugPrint(source, ('take out falhou | err=%s'):format(tostring(result)))
    return
  end

  debugPrint(source, ('take out ok | %s'):format(dumpVehicleShort(result)))
end, false)

RegisterCommand('mveh_out_as', function(source, args)
  if not isDebugAllowed(source) then
    debugPrint(source, 'Sem permissÃ£o.')
    return
  end

  local targetSource = tonumber(args[1])
  local plate = tostring(args[2] or '')
  local garage = tostring(args[3] or '')

  if not targetSource or plate == '' then
    debugPrint(source, 'Uso: mveh_out_as [source] [plate] [garage opcional]')
    return
  end

  local ok, result = MZVehicleService.takeOutVehicle(targetSource, plate, garage)
  if not ok then
    debugPrint(source, ('take out as falhou | err=%s'):format(tostring(result)))
    return
  end

  debugPrint(source, ('take out as ok | actor_source=%s | %s'):format(
    tostring(targetSource),
    dumpVehicleShort(result)
  ))
end, false)

RegisterCommand('mveh_store', function(source, args)
  if not isDebugAllowed(source) then
    debugPrint(source, 'Sem permissão.')
    return
  end

  local plate = tostring(args[1] or '')
  local garage = tostring(args[2] or 'default')
  local fuel = tonumber(args[3] or 100)
  local engine = tonumber(args[4] or 1000)
  local body = tonumber(args[5] or 1000)

  if plate == '' then
    debugPrint(source, 'Uso: mveh_store [plate] [garage] [fuel] [engine] [body]')
    return
  end

  local ok, result = MZVehicleService.storeVehicle(source, plate, garage, {
    plate = plate,
    model = `adder`,
    color1 = 12,
    color2 = 12
  }, fuel, engine, body)

  if not ok then
    debugPrint(source, ('store falhou | err=%s'):format(tostring(result)))
    return
  end

  debugPrint(source, ('store ok | %s'):format(dumpVehicleShort(result)))
end, false)

RegisterCommand('mveh_store_as', function(source, args)
  if not isDebugAllowed(source) then
    debugPrint(source, 'Sem permissÃ£o.')
    return
  end

  local targetSource = tonumber(args[1])
  local plate = tostring(args[2] or '')
  local garage = tostring(args[3] or 'default')
  local fuel = tonumber(args[4] or 100)
  local engine = tonumber(args[5] or 1000)
  local body = tonumber(args[6] or 1000)

  if not targetSource or plate == '' then
    debugPrint(source, 'Uso: mveh_store_as [source] [plate] [garage] [fuel] [engine] [body]')
    return
  end

  local ok, result = MZVehicleService.storeVehicle(targetSource, plate, garage, {
    plate = plate,
    model = `adder`,
    color1 = 12,
    color2 = 12
  }, fuel, engine, body)

  if not ok then
    debugPrint(source, ('store as falhou | err=%s'):format(tostring(result)))
    return
  end

  debugPrint(source, ('store as ok | actor_source=%s | %s'):format(
    tostring(targetSource),
    dumpVehicleShort(result)
  ))
end, false)

RegisterCommand('mveh_impound', function(source, args)
  if not isDebugAllowed(source) then
    debugPrint(source, 'Sem permissão.')
    return
  end

  local plate = tostring(args[1] or '')
  local reason = tostring(args[2] or 'debug_impound')

  if plate == '' then
    debugPrint(source, 'Uso: mveh_impound [plate] [reason opcional]')
    return
  end

  local ok, result = MZVehicleService.impoundVehicle(plate, reason, source, {
    debug = true
  })

  if not ok then
    debugPrint(source, ('impound falhou | err=%s'):format(tostring(result)))
    return
  end

  debugPrint(source, ('impound ok | %s'):format(dumpVehicleShort(result)))
end, false)

RegisterCommand('mveh_release', function(source, args)
  if not isDebugAllowed(source) then
    debugPrint(source, 'Sem permissão.')
    return
  end

  local plate = tostring(args[1] or '')
  local garage = tostring(args[2] or 'default')

  if plate == '' then
    debugPrint(source, 'Uso: mveh_release [plate] [garage]')
    return
  end

  local ok, result = MZVehicleService.releaseImpound(plate, garage, source)
  if not ok then
    debugPrint(source, ('release falhou | err=%s'):format(tostring(result)))
    return
  end

  debugPrint(source, ('release ok | %s'):format(dumpVehicleShort(result)))
end, false)

RegisterCommand('mveh_setstate', function(source, args)
  if not isDebugAllowed(source) then
    debugPrint(source, 'Sem permissão.')
    return
  end

  local plate = tostring(args[1] or '')
  local state = tostring(args[2] or '')

  if plate == '' or state == '' then
    debugPrint(source, 'Uso: mveh_setstate [plate] [state]')
    return
  end

  local ok, err = MZVehicleService.setVehicleState(plate, state, source)
  if not ok then
    debugPrint(source, ('setstate falhou | err=%s'):format(tostring(err)))
    return
  end

  debugPrint(source, ('setstate ok | plate=%s state=%s'):format(plate, state))
end, false)
