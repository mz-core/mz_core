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