lib.callback.register('mz_core:server:getPlayerData', function(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then
    player = MZPlayerService.loadPlayer(source)
  end

  if player then
    MZPlayerService.touchPlayer(source)
    MZOrgService.loadPlayerOrgs(source)
  end

  return player
end)

lib.callback.register('mz_core:server:getPlayerSession', function(source)
  MZPlayerService.touchPlayer(source)
  return MZPlayerService.getPlayerSession(source)
end)

lib.callback.register('mz_core:server:getHUDState', function(source)
  MZPlayerService.touchPlayer(source)
  return MZPlayerHUDService.getStateForSource(source)
end)

lib.callback.register('mz_core:server:getSpawnData', function(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then
    player = MZPlayerService.loadPlayer(source)
  end

  if not player then return nil end

  local appearance = type(player.metadata) == 'table' and player.metadata.appearance or nil
  local model = type(appearance) == 'table' and tostring(appearance.model or '') or ''
  if model ~= 'mp_m_freemode_01' and model ~= 'mp_f_freemode_01' then
    model = 'mp_m_freemode_01'
  end

  local lastPosition = MZPlayerService.getLastPosition(source)
  if lastPosition then
    return {
      x = lastPosition.x,
      y = lastPosition.y,
      z = lastPosition.z,
      heading = lastPosition.heading or 0.0,
      model = model
    }
  end

  return {
    x = Config.DefaultSpawn.x,
    y = Config.DefaultSpawn.y,
    z = Config.DefaultSpawn.z,
    heading = Config.DefaultSpawn.heading or 0.0,
    model = model
  }
end)
