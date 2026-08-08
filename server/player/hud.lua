MZPlayerHUDService = {}

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
  local status = Config.PlayerStates and Config.PlayerStates.status or {}
  local hunger = status.hunger or { min = 0, max = 100, default = 100 }
  local thirst = status.thirst or { min = 0, max = 100, default = 100 }
  local stress = status.stress or { min = 0, max = 100, default = 0 }
  local health = status.health or { min = 0, max = 200, default = 200 }
  local armor = status.armor or { min = 0, max = 100, default = 0 }

  return {
    metadata = {
      hunger = clampNumber(metadata.hunger, hunger.min, hunger.max, hunger.default),
      thirst = clampNumber(metadata.thirst, thirst.min, thirst.max, thirst.default),
      stress = clampNumber(metadata.stress, stress.min, stress.max, stress.default),
      health = clampNumber(metadata.health, health.min, health.max, health.default),
      armor = clampNumber(metadata.armor, armor.min, armor.max, armor.default),
      deathState = tostring(metadata.deathState or 'alive'),
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
