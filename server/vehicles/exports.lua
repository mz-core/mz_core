exports('GetVehicleById', function(id)
  return MZVehicleService.getVehicleById(id)
end)

exports('GetVehicleByPlate', function(plate)
  return MZVehicleService.getVehicleByPlate(plate)
end)

exports('GetPlayerVehicles', function(source)
  return MZVehicleService.getPlayerVehicles(source)
end)

exports('GetPlayerVehiclesByCitizenId', function(citizenid)
  return MZVehicleService.getPlayerVehiclesByCitizenId(citizenid)
end)

exports('GetOrgVehicles', function(orgCode)
  return MZVehicleService.getOrgVehicles(orgCode)
end)

exports('GetAccessibleVehicles', function(source, filters)
  return MZVehicleService.getAccessibleVehicles(source, filters)
end)

exports('RegisterPlayerVehicle', function(source, model, plate, props, garage, metadata)
  return MZVehicleService.registerPlayerVehicle(source, model, plate, props, garage, metadata)
end)

exports('RegisterOrgVehicle', function(orgCode, model, plate, props, garage, metadata)
  return MZVehicleService.registerOrgVehicle(orgCode, model, plate, props, garage, metadata)
end)

exports('PlayerOwnsVehicle', function(citizenid, plate)
  return MZVehicleService.playerOwnsVehicle(citizenid, plate)
end)

exports('OrgOwnsVehicle', function(orgCode, plate)
  return MZVehicleService.orgOwnsVehicle(orgCode, plate)
end)

exports('CanAccessVehicle', function(source, plate)
  return MZVehicleService.canAccessVehicle(source, plate)
end)

exports('EnsureVehicleAccessForPlayer', function(source, plate, data, reason)
  return MZVehicleService.ensureVehicleAccessForPlayer(source, plate, data, reason)
end)

exports('SetVehicleStored', function(plate, stored)
  return MZVehicleService.setVehicleStored(plate, stored)
end)

exports('SetVehicleGarage', function(plate, garage)
  return MZVehicleService.setVehicleGarage(plate, garage)
end)

exports('SetVehicleState', function(plate, state)
  return MZVehicleService.setVehicleState(plate, state)
end)

exports('SetVehicleMetadata', function(plate, metadata, mode)
  return MZVehicleService.setVehicleMetadata(plate, metadata, mode)
end)

exports('SetVehicleProps', function(plate, props)
  return MZVehicleService.setVehicleProps(plate, props)
end)

exports('SetVehicleCondition', function(plate, fuel, engine, body)
  return MZVehicleService.setVehicleCondition(plate, fuel, engine, body)
end)

exports('GetOutVehiclesForRespawn', function(source)
  return MZVehicleService.getOutVehiclesForRespawn(source)
end)

exports('RestoreWorldVehiclesForPlayer', function(source, reason)
  return MZVehicleService.restoreWorldVehiclesForPlayer(source, reason)
end)

exports('GetOutVehiclesNearCoords', function(coords, radius)
  return MZVehicleWorldService.GetOutVehiclesNearCoords(coords, radius)
end)

exports('EnsureWorldVehiclesNearPlayer', function(source, coords)
  return MZVehicleWorldService.EnsureWorldVehiclesNearPlayer(source, coords)
end)

exports('IsPlateSpawned', function(plate)
  return MZVehicleWorldService.IsPlateSpawned(plate)
end)

exports('RegisterOutVehicleEntity', function(source, plate, netId, snapshot)
  local ok, resultOrErr, extra = xpcall(function()
    return MZVehicleService.registerOutVehicleEntity(source, plate, netId, snapshot)
  end, debug.traceback)

  if not ok then
    print(('[mz_vehicle_world] RegisterOutVehicleEntity failed %s'):format(tostring(resultOrErr)))
    return false, 'entity_not_found'
  end

  return resultOrErr, extra
end)

exports('UpdateOutVehicleSnapshot', function(source, plate, snapshot)
  return MZVehicleService.updateOutVehicleSnapshot(source, plate, snapshot)
end)

exports('MarkOutVehicleDestroyed', function(source, plate, snapshot)
  return MZVehicleService.markOutVehicleDestroyed(source, plate, snapshot)
end)

exports('TakeOutVehicle', function(source, plate, garage)
  return MZVehicleService.takeOutVehicle(source, plate, garage)
end)

exports('StoreVehicle', function(source, plate, garage, props, fuel, engine, body)
  return MZVehicleService.storeVehicle(source, plate, garage, props, fuel, engine, body)
end)

exports('ImpoundVehicle', function(plate, reason, actorSource, extraData)
  return MZVehicleService.impoundVehicle(plate, reason, actorSource, extraData)
end)

exports('ReleaseImpoundVehicle', function(plate, garage, actorSource)
  return MZVehicleService.releaseImpound(plate, garage, actorSource)
end)
