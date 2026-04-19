MZClient = {
  PlayerData = nil,
  PlayerSession = nil
}

RegisterNetEvent('mz_core:client:playerLoaded', function(playerData)
  MZClient.PlayerData = playerData
  MZClient.PlayerSession = playerData and playerData.session or nil
end)

CreateThread(function()
  Wait(2000)
  local data = lib.callback.await('mz_core:server:getPlayerData', false)
  MZClient.PlayerData = data
  MZClient.PlayerSession = data and data.session or nil
end)
