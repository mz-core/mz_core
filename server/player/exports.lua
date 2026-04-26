exports('GetPlayer', function(source)
  return MZPlayerService.getPlayer(source)
end)

exports('GetPlayerByCitizenId', function(citizenid)
  return MZPlayerService.getPlayerByCitizenId(citizenid)
end)

exports('GetSourceByCitizenId', function(citizenid)
  return MZPlayerService.getSourceByCitizenId(citizenid)
end)

exports('SetMetadataValue', function(source, key, value)
  return MZPlayerService.setMetadataValue(source, key, value)
end)

exports('GetMetadataValue', function(source, key)
  return MZPlayerService.getMetadataValue(source, key)
end)

exports('SetCharinfo', function(source, charinfo)
  return MZPlayerService.setCharinfo(source, charinfo)
end)

exports('GetPlayerSession', function(source)
  return MZPlayerService.getPlayerSession(source)
end)

exports('IsPlayerLoaded', function(source)
  return MZPlayerService.isPlayerLoaded(source)
end)

exports('GetHUDState', function(source)
  return MZPlayerHUDService.getStateForSource(source)
end)
