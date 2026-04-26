MZPlayerHUDService = {}

local HUD_DEFAULTS = {
  hunger = 100,
  thirst = 100,
  stress = 0,
  isdead = false,
  inlaststand = false
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

local function getPlayerMetadata(player)
  if type(player) ~= 'table' then
    return {}
  end

  if type(player.metadata) == 'table' then
    return player.metadata
  end

  return {}
end

function MZPlayerHUDService.buildStateFromPlayer(player)
  local metadata = getPlayerMetadata(player)

  return {
    metadata = {
      hunger = clampNumber(metadata.hunger, 0, 100, HUD_DEFAULTS.hunger),
      thirst = clampNumber(metadata.thirst, 0, 100, HUD_DEFAULTS.thirst),
      stress = clampNumber(metadata.stress, 0, 100, HUD_DEFAULTS.stress),
      isdead = metadata.isdead == true,
      inlaststand = metadata.inlaststand == true
    }
  }
end

function MZPlayerHUDService.getStateForSource(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then
    return MZPlayerHUDService.buildStateFromPlayer(nil)
  end

  return MZPlayerHUDService.buildStateFromPlayer(player)
end

function MZPlayerHUDService.syncToClient(source)
  local hudState = MZPlayerHUDService.getStateForSource(source)
  TriggerClientEvent('mz_core:client:hudStateUpdated', source, hudState)
  return hudState
end
