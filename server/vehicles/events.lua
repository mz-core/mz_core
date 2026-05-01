RegisterNetEvent('mz_core:server:vehicle:takeOut', function(plate, garage)
  local source = source
  local ok, result = MZVehicleService.takeOutVehicle(source, plate, garage)
  TriggerClientEvent('mz_core:client:vehicle:takeOutResult', source, ok, result)
end)

RegisterNetEvent('mz_core:server:vehicle:store', function(plate, garage, props, fuel, engine, body)
  local source = source
  local ok, result = MZVehicleService.storeVehicle(source, plate, garage, props, fuel, engine, body)
  TriggerClientEvent('mz_core:client:vehicle:storeResult', source, ok, result)
end)

RegisterNetEvent('mz_core:server:vehicle:impound', function(plate, reason, extraData)
  local source = source
  local ok, result = MZVehicleService.impoundVehicle(plate, reason, source, extraData)
  TriggerClientEvent('mz_core:client:vehicle:impoundResult', source, ok, result)
end)

RegisterNetEvent('mz_core:server:vehicle:releaseImpound', function(plate, garage)
  local source = source
  local ok, result = MZVehicleService.releaseImpound(plate, garage, source)
  TriggerClientEvent('mz_core:client:vehicle:releaseImpoundResult', source, ok, result)
end)

RegisterNetEvent('mz_core:vehicles:server:checkWorldVehiclesNear', function(coords)
  local src = source
  if type(coords) ~= 'table' then
    return
  end

  if type(coords.x) ~= 'number' or type(coords.y) ~= 'number' or type(coords.z) ~= 'number' then
    return
  end

  if not MZVehicleWorldService then
    return
  end

  MZVehicleWorldService.EnsureWorldVehiclesNearPlayer(src, coords)
end)

RegisterNetEvent('mz_core:vehicles:server:restoreWorldVehicleSpawned', function(plate, netId, snapshot)
  local src = source
  if type(snapshot) ~= 'table' then
    snapshot = {}
  end

  snapshot.net_id = tonumber(netId or snapshot.net_id or snapshot.netId) or 0

  local normalizedPlate = tostring(plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
  if MZVehicleWorldService and MZVehicleWorldService.isSpawned then
    local spawned, _, reason = MZVehicleWorldService.isSpawned(normalizedPlate, snapshot.net_id)
    if spawned == true and reason == 'different_net_id' then
      print(('[mz_vehicle_world] skip duplicate client_fallback %s'):format(normalizedPlate))
      TriggerClientEvent('mz_core:vehicles:client:deleteWorldVehicleNet', src, snapshot.net_id)
      return
    end
  end

  if MZVehicleService and MZVehicleService.registerOutVehicleEntity then
    local ok, err = MZVehicleService.registerOutVehicleEntity(src, normalizedPlate, snapshot.net_id, snapshot)
    if ok ~= true then
      print(('[mz_vehicle_world] spawn failed client_fallback %s %s'):format(normalizedPlate, tostring(err or 'register_failed')))
    end
  end
end)

RegisterNetEvent('mz_core:vehicles:server:worldSnapshot', function(snapshot)
  local src = source
  if type(snapshot) ~= 'table' then
    return
  end

  local plate = tostring(snapshot.plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
  if plate == '' then
    return
  end

  snapshot.plate = plate

  if snapshot.destroyed == true or tonumber(snapshot.destroyed) == 1 then
    print(('[mz_vehicle_world] server destroyed snapshot received %s'):format(plate))

    if MZVehicleService and MZVehicleService.markOutVehicleDestroyed then
      local ok, err = MZVehicleService.markOutVehicleDestroyed(src, plate, snapshot)
      if ok ~= true then
        print(('[mz_vehicle_world] destroyed not saved %s reason=%s'):format(plate, tostring(err or 'mark_failed')))
      end
    end

    return
  end

  if MZVehicleService and MZVehicleService.updateOutVehicleSnapshot then
    MZVehicleService.updateOutVehicleSnapshot(src, plate, snapshot)
  end
end)

RegisterNetEvent('mz_core:vehicles:server:playerWorldReady', function()
  local src = source
  if not MZPlayerService or not MZPlayerService.isPlayerLoaded or not MZPlayerService.isPlayerLoaded(src) then
    return
  end

  SetTimeout(3000, function()
    if GetPlayerName(src) and MZVehicleService and MZVehicleService.restoreWorldVehiclesForPlayer then
      MZVehicleService.restoreWorldVehiclesForPlayer(src, 'player_world_ready')
    end
  end)
end)
