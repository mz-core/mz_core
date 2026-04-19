RegisterNetEvent('mz_core:server:refreshOrgs', function()
  local src = source
  MZOrgService.loadPlayerOrgs(src)
  local player = MZPlayerService.getPlayer(src)
  TriggerClientEvent('mz_core:client:playerLoaded', src, player)
end)

lib.callback.register('mz_core:server:getPlayerOrgs', function(source)
  MZOrgService.loadPlayerOrgs(source)
  return MZOrgService.getPlayerOrgs(source)
end)
