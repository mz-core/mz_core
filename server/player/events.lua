AddEventHandler('playerJoining', function()
  local src = source
  CreateThread(function()
    local playerData = MZPlayerService.loadPlayer(src)
    if not playerData then
      print(('[mz_core] failed to load player source %s'):format(src))
      return
    end

    MZOrgService.loadPlayerOrgs(src)
    TriggerClientEvent('mz_core:client:playerLoaded', src, playerData)
  end)
end)

RegisterNetEvent('mz_core:server:savePosition', function(coords)
  local src = source
  if type(coords) ~= 'table' then return end
  if type(coords.x) ~= 'number' then return end
  if type(coords.y) ~= 'number' then return end
  if type(coords.z) ~= 'number' then return end
  if coords.heading ~= nil and type(coords.heading) ~= 'number' then return end

  MZPlayerService.savePosition(src, coords)
end)

AddEventHandler('playerDropped', function(reason)
  MZPlayerService.unloadPlayer(source, reason)
end)