MZPlayerStateNormalizer = {}

local VALID_DEATH_STATES = {
  alive = true,
  downed = true,
  dead = true,
  respawning = true
}

local DEATH_LEGACY = {
  alive = { isdead = false, inlaststand = false },
  downed = { isdead = false, inlaststand = true },
  dead = { isdead = true, inlaststand = false },
  respawning = { isdead = true, inlaststand = false }
}

local TIMESTAMP_FIELDS = {
  'downedAt',
  'downedExpiresAt',
  'deadAt',
  'respawnAvailableAt',
  'reviveAt',
  'respawnStartedAt',
  'respawnCompletedAt'
}

local function clone(value)
  if type(value) ~= 'table' then return value end
  local result = {}
  for key, child in pairs(value) do
    result[key] = clone(child)
  end
  return result
end

local function finiteNumber(value)
  local number = tonumber(value)
  if not number or number ~= number or number == math.huge or number == -math.huge then
    return nil
  end
  return number
end

local function normalizeBoolean(value)
  if value == true or value == 1 then return true, true end
  if value == false or value == 0 then return false, true end
  if type(value) == 'string' then
    local normalized = value:lower():gsub('^%s+', ''):gsub('%s+$', '')
    if normalized == 'true' or normalized == '1' or normalized == 'yes' then return true, true end
    if normalized == 'false' or normalized == '0' or normalized == 'no' then return false, true end
  end
  return false, false
end

local function addCorrection(corrections, field, reason, previousValue, nextValue)
  corrections[#corrections + 1] = {
    field = field,
    reason = reason,
    previousValue = previousValue,
    nextValue = nextValue
  }
end

local function setCorrected(metadata, corrections, field, nextValue, reason)
  local previousValue = metadata[field]
  if previousValue == nextValue and type(previousValue) == type(nextValue) then
    return false
  end
  metadata[field] = nextValue
  addCorrection(corrections, field, reason, previousValue, nextValue)
  return true
end

local function statusConfig()
  return Config and Config.PlayerStates and Config.PlayerStates.status or {}
end

local function deathConfig()
  return Config and Config.PlayerStates and Config.PlayerStates.death or {}
end

function MZPlayerStateNormalizer.isFiniteNumber(value)
  return finiteNumber(value) ~= nil
end

function MZPlayerStateNormalizer.getLegacyFlags(deathState)
  return clone(DEATH_LEGACY[deathState] or DEATH_LEGACY.alive)
end

function MZPlayerStateNormalizer.decodeAndNormalize(value)
  local decoded = value
  local decodeInvalid = false

  if type(value) == 'string' then
    if value == '' then
      decoded = nil
      decodeInvalid = true
    else
      local ok, result = pcall(json.decode, value)
      if not ok or type(result) ~= 'table' then
        decoded = nil
        decodeInvalid = true
      else
        decoded = result
      end
    end
  elseif value ~= nil and type(value) ~= 'table' then
    decoded = nil
    decodeInvalid = true
  end

  local normalized, changed, corrections = MZPlayerStateNormalizer.normalize(decoded)
  if decodeInvalid then
    table.insert(corrections, 1, {
      field = 'metadata',
      reason = 'invalid_json_or_type'
    })
    changed = true
  end
  return normalized, changed, corrections, decodeInvalid
end

function MZPlayerStateNormalizer.normalize(input)
  local metadata = type(input) == 'table' and clone(input) or {}
  local corrections = {}
  local changed = type(input) ~= 'table'
  if changed then
    addCorrection(corrections, 'metadata', 'missing_or_invalid_table', type(input), 'table')
  end

  for name, definition in pairs(statusConfig()) do
    local number = finiteNumber(metadata[name])
    local reason
    if number == nil then
      number = tonumber(definition.default) or 0
      reason = metadata[name] == nil and 'missing_defaulted' or 'invalid_number_defaulted'
    else
      number = math.floor(number)
      if number < definition.min then
        number = definition.min
        reason = 'clamped_min'
      elseif number > definition.max then
        number = definition.max
        reason = 'clamped_max'
      elseif type(metadata[name]) ~= 'number' or metadata[name] ~= number then
        reason = 'number_normalized'
      end
    end
    if reason and setCorrected(metadata, corrections, name, number, reason) then changed = true end
  end

  local configuredDefault = tostring(deathConfig().default or 'alive')
  if not VALID_DEATH_STATES[configuredDefault] then configuredDefault = 'alive' end

  local currentDeathState = type(metadata.deathState) == 'string' and metadata.deathState:lower() or nil
  local legacyDead, deadValid = normalizeBoolean(metadata.isdead)
  local legacyDowned, downedValid = normalizeBoolean(metadata.inlaststand)
  local deathReason

  if not VALID_DEATH_STATES[currentDeathState] then
    if deadValid and legacyDead then
      currentDeathState = 'dead'
      deathReason = downedValid and legacyDowned and 'legacy_conflict_isdead_precedence' or 'derived_from_isdead'
    elseif downedValid and legacyDowned then
      currentDeathState = 'downed'
      deathReason = 'derived_from_inlaststand'
    else
      currentDeathState = configuredDefault
      deathReason = metadata.deathState == nil and 'missing_defaulted' or 'invalid_death_state_defaulted'
    end
  elseif metadata.deathState ~= currentDeathState then
    deathReason = 'death_state_normalized'
  end

  if deathReason and setCorrected(metadata, corrections, 'deathState', currentDeathState, deathReason) then changed = true end

  local expectedLegacy = DEATH_LEGACY[currentDeathState]
  if setCorrected(metadata, corrections, 'isdead', expectedLegacy.isdead, 'derived_from_death_state') then changed = true end
  if setCorrected(metadata, corrections, 'inlaststand', expectedLegacy.inlaststand, 'derived_from_death_state') then changed = true end

  local healthDefinition = statusConfig().health or { min = 0 }
  local armorDefinition = statusConfig().armor or { min = 0 }
  if currentDeathState == 'downed' then
    local downedHealth = math.max(tonumber(healthDefinition.min) or 0, tonumber(deathConfig().downedHealth) or 1)
    if setCorrected(metadata, corrections, 'health', downedHealth, 'derived_from_downed_state') then changed = true end
  elseif currentDeathState == 'dead' or currentDeathState == 'respawning' then
    if setCorrected(metadata, corrections, 'health', tonumber(healthDefinition.min) or 0, 'derived_from_death_state') then changed = true end
  elseif currentDeathState == 'alive' then
    local aliveMinimum = tonumber(Config and Config.PlayerStates and Config.PlayerStates.sync
      and Config.PlayerStates.sync.aliveMinHealth) or 1
    if tonumber(metadata.health) < aliveMinimum then
      if setCorrected(metadata, corrections, 'health', aliveMinimum, 'derived_from_alive_state') then changed = true end
    end
  end
  if currentDeathState ~= 'alive' then
    if setCorrected(metadata, corrections, 'armor', tonumber(armorDefinition.min) or 0, 'derived_from_death_state') then changed = true end
  end

  for _, field in ipairs(TIMESTAMP_FIELDS) do
    if metadata[field] ~= nil then
      local timestamp = finiteNumber(metadata[field])
      if not timestamp or timestamp < 0 then
        local previousValue = metadata[field]
        metadata[field] = nil
        addCorrection(corrections, field, 'invalid_timestamp_removed', previousValue, nil)
        changed = true
      else
        timestamp = math.floor(timestamp)
        if setCorrected(metadata, corrections, field, timestamp, 'timestamp_normalized') then changed = true end
      end
    end
  end

  if currentDeathState ~= 'downed' and metadata.downedExpiresAt ~= nil then
    local previousValue = metadata.downedExpiresAt
    metadata.downedExpiresAt = nil
    addCorrection(corrections, 'downedExpiresAt', 'cleared_outside_downed', previousValue, nil)
    changed = true
  end
  if currentDeathState ~= 'dead' and currentDeathState ~= 'respawning' and metadata.respawnAvailableAt ~= nil then
    local previousValue = metadata.respawnAvailableAt
    metadata.respawnAvailableAt = nil
    addCorrection(corrections, 'respawnAvailableAt', 'cleared_outside_death_cycle', previousValue, nil)
    changed = true
  end

  return metadata, changed, corrections
end

MZPlayerStateNormalizer.VALID_DEATH_STATES = VALID_DEATH_STATES
MZPlayerStateNormalizer.TIMESTAMP_FIELDS = TIMESTAMP_FIELDS
