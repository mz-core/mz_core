MZClient = MZClient or {}
MZClient.HUDState = MZClient.HUDState or {
  metadata = {}
}

local function clampNumber(value, minValue, maxValue, fallback)
  local numeric = tonumber(value)
  if numeric == nil then
    return fallback
  end

  if numeric < minValue then
    return minValue
  end

  if numeric > maxValue then
    return maxValue
  end

  return numeric
end

local function buildHUDStateFromPlayerData(playerData)
  local metadata = type(playerData) == 'table' and type(playerData.metadata) == 'table' and playerData.metadata or {}

  return {
    metadata = {
      hunger = clampNumber(metadata.hunger, 0, 100, 100),
      thirst = clampNumber(metadata.thirst, 0, 100, 100),
      stress = clampNumber(metadata.stress, 0, 100, 0),
      isdead = metadata.isdead == true,
      inlaststand = metadata.inlaststand == true
    }
  }
end

local function applyHUDState(hudState)
  if type(hudState) ~= 'table' then
    return
  end

  MZClient.HUDState = {
    metadata = type(hudState.metadata) == 'table' and hudState.metadata or {}
  }

  if type(MZClient.PlayerData) == 'table' and type(MZClient.HUDState.metadata) == 'table' then
    MZClient.PlayerData.metadata = MZClient.PlayerData.metadata or {}
    for key, value in pairs(MZClient.HUDState.metadata) do
      MZClient.PlayerData.metadata[key] = value
    end
  end
end

RegisterNetEvent('mz_core:client:hudStateUpdated', function(hudState)
  applyHUDState(hudState)
end)

RegisterNetEvent('mz_core:client:playerLoaded', function(playerData)
  applyHUDState(buildHUDStateFromPlayerData(playerData))
end)

CreateThread(function()
  Wait(2000)
  local hudState = lib.callback.await('mz_core:server:getHUDState', false)
  applyHUDState(hudState)
end)

exports('GetHUDState', function()
  return MZClient.HUDState
end)
