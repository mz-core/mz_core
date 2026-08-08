lib.callback.register('mz_core:server:getPlayerData', function(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then
    player = MZPlayerService.loadPlayer(source)
  end

  if player then
    MZPlayerService.touchPlayer(source)
    MZOrgService.loadPlayerOrgs(source)

    CreateThread(function()
      Wait(5000)
      local cfg = Config and Config.VehicleWorld or {}
      if cfg.restoreOnPlayerJoin == true and GetPlayerName(source) and MZVehicleService and MZVehicleService.restoreWorldVehiclesForPlayer then
        MZVehicleService.restoreWorldVehiclesForPlayer(source, 'get_player_data')
      elseif cfg.debug == true then
        print(('[mz_vehicle_world] vehicle_restore_auto_disabled reason=get_player_data source=%s'):format(tostring(source)))
      end
    end)
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
  local spawnData
  if lastPosition then
    spawnData = {
      x = lastPosition.x,
      y = lastPosition.y,
      z = lastPosition.z,
      heading = lastPosition.heading or 0.0,
      model = model
    }
  else
    spawnData = {
      x = Config.DefaultSpawn.x,
      y = Config.DefaultSpawn.y,
      z = Config.DefaultSpawn.z,
      heading = Config.DefaultSpawn.heading or 0.0,
      model = model
    }
  end

  if GetResourceState('mz_banguard') == 'started' then
    pcall(function()
      local lifecycleId = exports['mz_banguard']:BeginSecurityLifecycle(source, 'character_spawn', 45000, {
        model = GetHashKey(model), bucket = GetPlayerRoutingBucket(source),
        x = spawnData.x, y = spawnData.y, z = spawnData.z, reason = 'core_spawn'
      })
      if type(lifecycleId) == 'string' then spawnData.securityLifecycleId = lifecycleId end
      exports['mz_banguard']:RegisterSecurityLease(source, 'player.model.change', 10000, {
        model = GetHashKey(model), quantity = 1, reason = 'core_spawn'
      })
      exports['mz_banguard']:RegisterSecurityLease(source, 'movement.teleport', 10000, {
        x = spawnData.x, y = spawnData.y, z = spawnData.z, quantity = 4, reason = 'core_spawn'
      })
    end)
  end
  return spawnData
end)

exports('SpawnPlayerForMedical', function(source, request)
  if GetInvokingResource() ~= 'mz_medical' or type(request) ~= 'table' then
    return false, 'not_authorized'
  end
  local allowed = {
    operationId = true, token = true, x = true, y = true, z = true, heading = true
  }
  local count = 0
  for key in pairs(request) do
    count = count + 1
    if count > 6 or allowed[key] ~= true then return false, 'invalid_payload' end
  end
  local operationId = type(request.operationId) == 'string' and request.operationId or ''
  local token = type(request.token) == 'string' and request.token or ''
  local x, y, z = tonumber(request.x), tonumber(request.y), tonumber(request.z)
  local heading = tonumber(request.heading)
  if operationId == '' or #operationId > 96 or token == '' or #token > 96
    or not x or not y or not z or not heading
    or x ~= x or y ~= y or z ~= z or heading ~= heading
    or math.abs(x) > 20000 or math.abs(y) > 20000 or math.abs(z) > 2000 or math.abs(heading) > 3600 then
    return false, 'invalid_payload'
  end
  local deathOk, death = MZPlayerStateService.getDeathState(source)
  if not deathOk or not death or death.deathState ~= 'respawning' then
    return false, 'invalid_state'
  end
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, 'player_not_loaded' end
  local appearance = type(player.metadata) == 'table' and player.metadata.appearance or nil
  local model = type(appearance) == 'table' and tostring(appearance.model or '') or ''
  if model ~= 'mp_m_freemode_01' and model ~= 'mp_f_freemode_01' then model = 'mp_m_freemode_01' end

  if GetResourceState('mz_banguard') == 'started' then
    pcall(function()
      exports['mz_banguard']:RegisterSecurityLease(source, 'player.model.change', 10000, {
        model = GetHashKey(model), quantity = 1, reason = 'hospital_respawn'
      })
      exports['mz_banguard']:RegisterSecurityLease(source, 'movement.teleport', 10000, {
        x = x, y = y, z = z, quantity = 4, reason = 'hospital_respawn'
      })
    end)
  end

  TriggerClientEvent('mz_core:client:spawnPlayer', source, {
    x = x, y = y, z = z, heading = heading, model = model,
    authorizedOperation = { operationId = operationId, token = token }
  })
  return true, { operationId = operationId }
end)
