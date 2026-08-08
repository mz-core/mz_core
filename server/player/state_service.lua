MZPlayerStateService = {}

local RuntimeStates = {}
local shuttingDown = false
local auditSequence = 0
local tokenSequence = 0

local ERROR_MESSAGES = {
  player_not_found = 'Player was not found.',
  player_not_loaded = 'Player is not loaded.',
  invalid_status = 'Status is not registered.',
  invalid_value = 'Value must be a finite number.',
  invalid_transition = 'The requested death-state transition is not allowed.',
  already_in_state = 'Player is already in the requested state.',
  not_authorized = 'Invoking resource is not authorized for this operation.',
  unloading = 'Player is unloading and no longer accepts mutations.',
  lock_timeout = 'Timed out waiting for the player-state lock.',
  persistence_failed = 'Player state could not be persisted.',
  persistence_pending = 'State changed in memory but persistence is pending.',
  feature_disabled = 'Player-state service is disabled.',
  internal_error = 'Player-state operation failed unexpectedly.',
  protected_metadata = 'Sensitive metadata must be changed through a specific player-state API.',
  invalid_action = 'Action is not registered.',
  invalid_patch = 'Status patch has an invalid schema.',
  invalid_state = 'Player state does not allow this operation.',
  invalid_deadline = 'Death-state deadline is invalid.',
  revision_mismatch = 'Player-state revision no longer matches the operation.',
  no_benefit = 'The operation would not change player state.'
}

local PROTECTED_METADATA = {
  hunger = 'SetStatus',
  thirst = 'SetStatus',
  stress = 'SetStatus',
  health = 'SetStatus',
  armor = 'SetStatus',
  deathState = 'MarkPlayerDowned/MarkPlayerDead/RevivePlayer/BeginPlayerRespawn/CompletePlayerRespawn',
  isdead = 'death-state APIs',
  inlaststand = 'death-state APIs',
  downedAt = 'death-state APIs',
  downedExpiresAt = 'death-state APIs',
  deadAt = 'death-state APIs',
  respawnAvailableAt = 'death-state APIs',
  reviveAt = 'death-state APIs',
  respawnStartedAt = 'death-state APIs',
  respawnCompletedAt = 'death-state APIs'
}

local TRANSITIONS = {
  alive = { downed = true, dead = true },
  downed = { dead = true, alive = true },
  dead = { respawning = true },
  respawning = { alive = true, dead = true }
}

local function config()
  return Config and Config.PlayerStates or {}
end

local function nowMs()
  if type(GetGameTimer) == 'function' then return GetGameTimer() end
  return math.floor(os.clock() * 1000)
end

local function opaqueToken(prefix, source)
  tokenSequence = tokenSequence + 1
  if MZUtils and type(MZUtils.generateInstanceUid) == 'function' then
    local ok, token = pcall(MZUtils.generateInstanceUid, tostring(prefix or 'state'):upper())
    if ok and type(token) == 'string' and token ~= '' then return token end
  end
  return ('%s-%s-%s-%s'):format(
    tostring(prefix or 'state'), tostring(source or 0), tostring(os.time()), tostring(tokenSequence)
  )
end

local function clone(value)
  if type(value) ~= 'table' then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = clone(child) end
  return result
end

local function errorResult(code, extra)
  local result = clone(type(extra) == 'table' and extra or {})
  result.code = code
  result.message = ERROR_MESSAGES[code] or ERROR_MESSAGES.internal_error
  return result
end

local function successResult(runtime, state, changed, code, extra)
  local result = clone(type(extra) == 'table' and extra or {})
  result.revision = runtime and runtime.revision or 0
  result.state = state
  result.changed = changed == true
  if code then result.code = code end
  return result
end

local function nextAuditId()
  auditSequence = auditSequence + 1
  return ('PS-%s-%s'):format(tostring(os.time()), tostring(auditSequence))
end

local function safeLog(action, source, fields)
  fields = type(fields) == 'table' and fields or {}
  local player = MZPlayerService and MZPlayerService.getPlayer and MZPlayerService.getPlayer(source) or nil
  local auditId = fields.auditId or nextAuditId()
  local payload = {
    auditId = auditId,
    actor = {
      type = 'player_state_actor',
      id = tostring(fields.actorSource or fields.invokingResource or 'system'),
      source = tonumber(fields.actorSource)
    },
    target = {
      type = 'player',
      id = player and player.citizenid or ('source:%s'):format(tostring(source)),
      citizenid = player and player.citizenid or nil
    },
    context = {
      source = tonumber(source),
      operation = fields.operation,
      statusName = fields.statusName,
      reason = fields.reason,
      invokingResource = fields.invokingResource,
      actorSource = tonumber(fields.actorSource),
      timestamp = os.time()
    },
    before = {
      value = fields.previousValue,
      deathState = fields.previousDeathState
    },
    after = {
      value = fields.nextValue,
      deathState = fields.nextDeathState,
      revision = fields.revision
    },
    meta = {
      result = fields.result,
      error = fields.error,
      correctionCount = fields.correctionCount
    }
  }

  if MZLogService and MZLogService.createDetailed then
    local ok, err = pcall(MZLogService.createDetailed, 'player_state', action, payload)
    if not ok then
      print(('[mz_core][player_state][log_failed] action=%s source=%s error=%s'):format(
        tostring(action), tostring(source), tostring(err)
      ))
    end
  elseif Config and Config.Debug == true then
    print(('[mz_core][player_state] action=%s source=%s result=%s error=%s'):format(
      tostring(action), tostring(source), tostring(fields.result), tostring(fields.error)
    ))
  end
  return auditId
end

local function safeSuspiciousActivity(source, fields)
  fields = type(fields) == 'table' and fields or {}
  if MZPlayerStateObservability and type(MZPlayerStateObservability.reportSuspicion) == 'function' then
    MZPlayerStateObservability.reportSuspicion(
      tostring(fields.error or fields.operation or 'state_rejected'),
      source,
      {
        reason = fields.reason or fields.error or fields.operation,
        error = fields.error,
        operation = fields.operation,
        evidence = {
          statusName = fields.statusName,
          invokingResource = fields.invokingResource,
          attemptedValue = fields.attemptedValue,
          expected = fields.expected,
          revision = fields.revision
        }
      },
      'mz_core'
    )
    return
  end
  local player = MZPlayerService and MZPlayerService.getPlayer and MZPlayerService.getPlayer(source) or nil
  local payload = {
    auditId = fields.auditId or nextAuditId(),
    actor = {
      type = 'player_state_actor',
      id = tostring(fields.actorSource or fields.invokingResource or 'system'),
      source = tonumber(fields.actorSource)
    },
    target = {
      type = 'player',
      id = player and player.citizenid or ('source:%s'):format(tostring(source)),
      citizenid = player and player.citizenid or nil
    },
    context = {
      source = tonumber(source),
      operation = fields.operation,
      statusName = fields.statusName,
      reason = fields.reason,
      invokingResource = fields.invokingResource,
      actorSource = tonumber(fields.actorSource),
      timestamp = os.time()
    },
    meta = {
      category = 'suspicious_activity',
      result = fields.result or 'rejected',
      error = fields.error,
      attemptedValue = fields.attemptedValue,
      expected = fields.expected,
      revision = fields.revision
    }
  }

  if MZLogService and MZLogService.createDetailed then
    local ok, err = pcall(MZLogService.createDetailed, 'player_state', 'suspicious_activity', payload)
    if not ok then
      print(('[mz_core][player_state][suspicious_log_failed] source=%s error=%s'):format(
        tostring(source), tostring(err)
      ))
    end
  elseif Config and Config.Debug == true then
    print(('[mz_core][player_state][suspicious_activity] source=%s operation=%s error=%s'):format(
      tostring(source), tostring(fields.operation), tostring(fields.error)
    ))
  end
end

local function featureEnabled()
  return config().enabled ~= false and shuttingDown ~= true
end

local function getPlayerAndRuntime(source)
  source = tonumber(source)
  if not source or source <= 0 then return nil, nil, 'player_not_found' end
  local player = MZPlayerService and MZPlayerService.getPlayer and MZPlayerService.getPlayer(source) or nil
  if not player then return nil, nil, 'player_not_found' end
  if not player.state or player.state.loaded ~= true then return player, nil, 'player_not_loaded' end
  local runtime = RuntimeStates[source]
  if not runtime or runtime.citizenid ~= player.citizenid or runtime.sessionId ~= (player.session and player.session.id or nil) then
    return player, nil, 'player_not_loaded'
  end
  return player, runtime
end

local function configuredResources(kind)
  local authorization = config().authorization or {}
  local map = {
    status = authorization.statusWriters,
    damage = authorization.damageWriters,
    healing = authorization.healingWriters,
    medical = authorization.medicalWriters,
    armor = authorization.armorWriters,
    administrative = authorization.administrativeWriters
  }
  return type(map[kind]) == 'table' and map[kind] or {}
end

local function listContains(list, value)
  for _, candidate in ipairs(list or {}) do
    if candidate == value then return true end
  end
  return false
end

function MZPlayerStateService.isResourceAuthorized(operation, invokingResource, internal)
  if internal == true then return true end
  if type(invokingResource) ~= 'string' or invokingResource == '' then return false end
  if operation == 'persistence' then
    return listContains(configuredResources('status'), invokingResource)
      or listContains(configuredResources('damage'), invokingResource)
      or listContains(configuredResources('healing'), invokingResource)
      or listContains(configuredResources('medical'), invokingResource)
      or listContains(configuredResources('armor'), invokingResource)
      or listContains(configuredResources('administrative'), invokingResource)
  end
  return listContains(configuredResources(operation), invokingResource)
end

local function emitVitalChanged(source, payload)
  if type(TriggerEvent) ~= 'function' or type(payload) ~= 'table' then return end
  local eventPayload = clone(payload)
  eventPayload.source = tonumber(source)
  TriggerEvent('mz_core:server:playerVitalChangedInternal', tonumber(source), eventPayload)
end

local function emitDeathStateChanged(source, payload)
  if type(TriggerEvent) ~= 'function' or type(payload) ~= 'table' then return end
  local eventPayload = clone(payload)
  eventPayload.source = tonumber(source)
  TriggerEvent('mz_core:server:playerDeathStateChangedInternal', tonumber(source), eventPayload)
end

local function authorize(source, operation, context)
  context = type(context) == 'table' and context or {}
  if MZPlayerStateService.isResourceAuthorized(operation, context.invokingResource, context.internal == true) then
    return true
  end
  safeLog('authorization_denied', source, {
    operation = operation,
    reason = context.reason,
    invokingResource = context.invokingResource,
    actorSource = context.actorSource,
    result = 'rejected',
    error = 'not_authorized'
  })
  safeSuspiciousActivity(source, {
    operation = operation,
    reason = context.reason,
    invokingResource = context.invokingResource,
    actorSource = context.actorSource,
    result = 'rejected',
    error = 'not_authorized'
  })
  return false, errorResult('not_authorized', { operation = operation })
end

local function unloadingError(source, operation, context, runtime)
  context = type(context) == 'table' and context or {}
  safeLog('operation_after_unload', source, {
    operation = operation,
    reason = context.reason,
    invokingResource = context.invokingResource,
    actorSource = context.actorSource,
    result = 'rejected',
    error = 'unloading',
    revision = runtime and runtime.revision
  })
  return false, errorResult('unloading')
end

local function acquireLock(source, allowUnloading)
  local runtime = RuntimeStates[source]
  if not runtime then return nil, 'player_not_loaded' end
  local timeout = tonumber(config().persistence and config().persistence.lockTimeoutMs) or 5000
  local startedAt = nowMs()
  local token = {}

  while runtime.lock ~= nil do
    if nowMs() - startedAt >= timeout then
      safeLog('lock_timeout', source, {
        operation = runtime.lockOperation,
        result = 'rejected',
        error = 'lock_timeout',
        revision = runtime.revision
      })
      return nil, 'lock_timeout'
    end
    if type(Wait) ~= 'function' then return nil, 'lock_timeout' end
    Wait(0)
    runtime = RuntimeStates[source]
    if not runtime then return nil, 'player_not_loaded' end
  end

  if runtime.unloading == true and allowUnloading ~= true then return nil, 'unloading' end
  runtime.lock = token
  runtime.lockedAt = nowMs()
  return { runtime = runtime, token = token }
end

local function releaseLock(handle)
  if not handle or not handle.runtime then return end
  if handle.runtime.lock == handle.token then
    handle.runtime.lock = nil
    handle.runtime.lockedAt = nil
    handle.runtime.lockOperation = nil
  end
end

local function withLock(source, operation, allowUnloading, handler)
  local handle, lockErr = acquireLock(source, allowUnloading)
  if not handle then return false, errorResult(lockErr) end
  handle.runtime.lockOperation = operation
  local packed = table.pack(xpcall(handler, debug.traceback, handle.runtime))
  releaseLock(handle)
  if packed[1] ~= true then
    safeLog('operation_failed', source, {
      operation = operation,
      result = 'failed',
      error = 'internal_error',
      revision = handle.runtime.revision
    })
    print(('[mz_core][player_state][operation_failed] source=%s operation=%s error=%s'):format(
      tostring(source), tostring(operation), tostring(packed[2])
    ))
    return false, errorResult('internal_error')
  end
  return table.unpack(packed, 2, packed.n)
end

local function markDirty(runtime, field)
  runtime.dirty[field] = true
  runtime.dirtySince = runtime.dirtySince or nowMs()
end

local function dirtyList(runtime)
  local result = {}
  for field in pairs(runtime.dirty) do result[#result + 1] = field end
  table.sort(result)
  return result
end

local function buildSnapshot(player, runtime)
  local metadata = player.metadata or {}
  local deathState = metadata.deathState or 'alive'
  return {
    revision = runtime.revision,
    hunger = metadata.hunger,
    thirst = metadata.thirst,
    stress = metadata.stress,
    health = metadata.health,
    armor = metadata.armor,
    deathState = deathState,
    isdead = metadata.isdead == true,
    inlaststand = metadata.inlaststand == true,
    status = {
      hunger = metadata.hunger,
      thirst = metadata.thirst,
      stress = metadata.stress,
      health = metadata.health,
      armor = metadata.armor
    },
    deathTimestamps = {
      downedAt = metadata.downedAt,
      downedExpiresAt = metadata.downedExpiresAt,
      deadAt = metadata.deadAt,
      respawnAvailableAt = metadata.respawnAvailableAt,
      reviveAt = metadata.reviveAt,
      respawnStartedAt = metadata.respawnStartedAt,
      respawnCompletedAt = metadata.respawnCompletedAt
    },
    flags = {
      loaded = player.state and player.state.loaded == true,
      unloading = runtime.unloading == true,
      actionsBlocked = deathState ~= 'alive'
    }
  }
end

local function syncPresentation(source, reason, options)
  if MZPlayerStateSyncService and MZPlayerStateSyncService.sync then
    local ok, result = pcall(MZPlayerStateSyncService.sync, source, reason or 'state_changed', options)
    if not ok or type(result) ~= 'table' or result.ok ~= true then
      print(('[mz_core][player_state][canonical_sync_failed] source=%s reason=%s error=%s'):format(
        tostring(source), tostring(reason), tostring(ok and result and result.code or result)
      ))
    end
    return
  end

  if MZPlayerHUDService and MZPlayerHUDService.syncToClient then
    local ok, err = pcall(MZPlayerHUDService.syncToClient, source)
    if not ok then
      print(('[mz_core][player_state][presentation_sync_failed] source=%s error=%s'):format(
        tostring(source), tostring(err)
      ))
    end
  end
end

local function flushLocked(source, player, runtime, reason)
  local fields = dirtyList(runtime)
  if #fields == 0 then
    return true, successResult(runtime, buildSnapshot(player, runtime), false, 'not_dirty')
  end

  local ok, persisted = pcall(MZPlayerRepository.updateMetadata, player.citizenid, player.metadata)
  if not ok or persisted ~= true then
    safeLog('persistence_failed', source, {
      operation = 'flush', reason = reason, result = 'failed', error = 'persistence_failed',
      revision = runtime.revision
    })
    if MZPlayerStateObservability then
      MZPlayerStateObservability.record('player_state_persistence_failed', {
        source = source, citizenid = player.citizenid, revision = runtime.revision,
        reason = reason, result = 'failed', error = 'persistence_failed'
      }, 'mz_core')
    end
    return false, errorResult('persistence_failed', {
      revision = runtime.revision,
      state = buildSnapshot(player, runtime),
      dirtyFields = fields
    })
  end

  runtime.dirty = {}
  runtime.dirtySince = nil
  runtime.lastFlushAt = nowMs()
  return true, successResult(runtime, buildSnapshot(player, runtime), false, 'flushed', {
    dirtyFields = fields
  })
end

local function criticalFlushLocked(source, player, runtime, reason)
  local persistence = config().persistence or {}
  local death = config().death or {}
  if persistence.criticalImmediateSave ~= true or death.persistCriticalTransitions == false then
    return true
  end
  local ok, result = flushLocked(source, player, runtime, reason)
  if ok then return true end
  if MZPlayerStateObservability then
    MZPlayerStateObservability.record('player_state_persistence_pending', {
      source = source, citizenid = player.citizenid, revision = runtime.revision,
      reason = reason, result = 'pending', error = result and result.code or 'persistence_failed'
    }, 'mz_core')
  end
  return false, errorResult('persistence_pending', {
    revision = runtime.revision,
    state = buildSnapshot(player, runtime),
    changed = true,
    persistenceError = result
  })
end

function MZPlayerStateService.initializePlayer(source, corrections)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, errorResult('player_not_found') end
  RuntimeStates[source] = {
    citizenid = player.citizenid,
    sessionId = player.session and player.session.id or nil,
    syncSessionToken = opaqueToken('session', source),
    observationToken = opaqueToken('observation', source),
    revision = 0,
    dirty = {},
    dirtySince = nil,
    lastFlushAt = 0,
    unloading = false,
    lock = nil,
    lastCriticalTransitionId = nil,
    lastCriticalTransitionAt = nil,
    clientSync = {
      lastResyncAt = nil,
      reportWindowStartedAt = nil,
      reportCount = 0,
      lastSequence = 0,
      eventWindows = {},
      fatalCandidateStartedAt = nil,
      fatalCandidateCount = 0,
      lastFatalCandidateAt = nil
    }
  }
  local runtime = RuntimeStates[source]
  if MZPlayerStateObservability then
    MZPlayerStateObservability.playerLoaded(source, player.metadata and player.metadata.deathState or 'alive')
  end
  if type(corrections) == 'table' and #corrections > 0 then
    local invalidMetadata = false
    for _, correction in ipairs(corrections) do markDirty(runtime, correction.field or 'metadata') end
    for _, correction in ipairs(corrections) do
      if correction.reason == 'invalid_json_or_type' or correction.reason == 'missing_or_invalid_table' then
        invalidMetadata = true
        break
      end
    end
    if invalidMetadata then
      safeLog('metadata_invalid', source, {
        operation = 'load_normalization', result = 'defaults_applied', correctionCount = #corrections,
        error = 'invalid_metadata', revision = 0
      })
    end
    safeLog('metadata_normalized', source, {
      operation = 'load_normalization', result = 'corrected', correctionCount = #corrections,
      revision = 0
    })
    if MZPlayerStateObservability then
      MZPlayerStateObservability.record('player_state_normalized', {
        source = source, citizenid = player.citizenid, revision = 0,
        reason = 'load_normalization', result = 'corrected', evidence = { correctionCount = #corrections }
      }, 'mz_core')
    end
    return withLock(source, 'load_normalization_flush', false, function(lockedRuntime)
      local ok, result = flushLocked(source, player, lockedRuntime, 'load_normalization')
      if not ok then
        return false, errorResult('persistence_pending', {
          revision = lockedRuntime.revision,
          state = buildSnapshot(player, lockedRuntime),
          persistenceError = result
        })
      end
      return true, result
    end)
  end
  return true, successResult(runtime, buildSnapshot(player, runtime), false, 'initialized')
end

function MZPlayerStateService.getState(source)
  if config().enabled == false then return false, errorResult('feature_disabled') end
  local player, runtime, err = getPlayerAndRuntime(source)
  if not player then return false, errorResult(err) end
  if not runtime then return false, errorResult(err) end
  return true, successResult(runtime, buildSnapshot(player, runtime), false)
end

function MZPlayerStateService.getStatus(source, statusName)
  local definition = config().status and config().status[statusName]
  if not definition then return false, errorResult('invalid_status', { statusName = statusName }) end
  local ok, result = MZPlayerStateService.getState(source)
  if not ok then return false, result end
  return true, {
    revision = result.revision,
    statusName = statusName,
    value = result.state.status[statusName]
  }
end

function MZPlayerStateService.getDeathState(source)
  local ok, result = MZPlayerStateService.getState(source)
  if not ok then return false, result end
  return true, {
    revision = result.revision,
    deathState = result.state.deathState,
    isdead = result.state.isdead,
    inlaststand = result.state.inlaststand
  }
end

local function statusAuthorization(statusName)
  local definition = config().status and config().status[statusName]
  return definition and definition.writer or 'status'
end

local function mutateStatus(source, statusName, value, mode, context)
  if not featureEnabled() then return false, errorResult('feature_disabled') end
  local definition = config().status and config().status[statusName]
  if not definition then return false, errorResult('invalid_status', { statusName = statusName }) end
  local number = tonumber(value)
  if not MZPlayerStateNormalizer.isFiniteNumber(value) then
    return false, errorResult('invalid_value', { statusName = statusName })
  end
  if mode ~= 'set' and number < 0 then
    return false, errorResult('invalid_value', { statusName = statusName })
  end
  local authorized, authErr = authorize(source, statusAuthorization(statusName), context)
  if not authorized then return false, authErr end
  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  if runtime.unloading then return unloadingError(source, mode .. '_status', context, runtime) end

  return withLock(source, mode .. '_status', false, function(lockedRuntime)
    local currentPlayer, currentRuntime, currentErr = getPlayerAndRuntime(source)
    if not currentPlayer or currentRuntime ~= lockedRuntime then return false, errorResult(currentErr or 'player_not_loaded') end
    local current = tonumber(currentPlayer.metadata[statusName]) or tonumber(definition.default) or 0
    local nextValue = number
    if mode == 'add' then nextValue = current + number end
    if mode == 'remove' then nextValue = current - number end
    nextValue = math.floor(nextValue)
    if nextValue < definition.min then nextValue = definition.min end
    if nextValue > definition.max then nextValue = definition.max end
    local deathState = currentPlayer.metadata.deathState
    if statusName == 'health' and (deathState == 'dead' or deathState == 'respawning') and nextValue > 0 then
      return false, errorResult('invalid_transition', {
        previousDeathState = deathState,
        nextValue = nextValue,
        use = 'RevivePlayer or CompletePlayerRespawn'
      })
    end
    if statusName == 'health' and (deathState == 'alive' or deathState == 'downed') and nextValue <= 0 then
      return false, errorResult('invalid_transition', {
        previousDeathState = deathState,
        nextValue = nextValue,
        use = 'MarkPlayerDowned or MarkPlayerDead'
      })
    end
    if nextValue == current then
      return true, successResult(lockedRuntime, buildSnapshot(currentPlayer, lockedRuntime), false, 'unchanged')
    end
    currentPlayer.metadata[statusName] = nextValue
    lockedRuntime.revision = lockedRuntime.revision + 1
    markDirty(lockedRuntime, statusName)
    syncPresentation(source, ('status_%s'):format(statusName))
    return true, successResult(lockedRuntime, buildSnapshot(currentPlayer, lockedRuntime), true)
  end)
end

function MZPlayerStateService.setStatus(source, statusName, value, context)
  return mutateStatus(source, statusName, value, 'set', context)
end

function MZPlayerStateService.addStatus(source, statusName, amount, context)
  return mutateStatus(source, statusName, amount, 'add', context)
end

function MZPlayerStateService.removeStatus(source, statusName, amount, context)
  return mutateStatus(source, statusName, amount, 'remove', context)
end

function MZPlayerStateService.applyStatusPatch(source, patch, context)
  if not featureEnabled() then return false, errorResult('feature_disabled') end
  if type(patch) ~= 'table' then return false, errorResult('invalid_patch') end
  local allowed = { hunger = true, thirst = true, stress = true }
  local normalized, count = {}, 0
  for statusName, delta in pairs(patch) do
    count = count + 1
    if count > 3 or allowed[statusName] ~= true
      or not MZPlayerStateNormalizer.isFiniteNumber(delta) then
      return false, errorResult('invalid_patch', { statusName = statusName })
    end
    normalized[statusName] = math.floor(tonumber(delta))
  end
  if count == 0 then return false, errorResult('invalid_patch') end
  local authorized, authErr = authorize(source, 'status', context)
  if not authorized then return false, authErr end
  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  if runtime.unloading then return unloadingError(source, 'status_patch', context, runtime) end

  return withLock(source, 'status_patch', false, function(lockedRuntime)
    local currentPlayer, currentRuntime, currentErr = getPlayerAndRuntime(source)
    if not currentPlayer or currentRuntime ~= lockedRuntime then
      return false, errorResult(currentErr or 'player_not_loaded')
    end
    local changedFields = {}
    for statusName, delta in pairs(normalized) do
      local definition = config().status[statusName]
      local current = tonumber(currentPlayer.metadata[statusName]) or tonumber(definition.default) or 0
      local nextValue = math.floor(current + delta)
      if nextValue < definition.min then nextValue = definition.min end
      if nextValue > definition.max then nextValue = definition.max end
      if nextValue ~= current then
        currentPlayer.metadata[statusName] = nextValue
        changedFields[#changedFields + 1] = statusName
      end
    end
    if #changedFields == 0 then
      return true, successResult(lockedRuntime, buildSnapshot(currentPlayer, lockedRuntime), false, 'unchanged')
    end
    table.sort(changedFields)
    lockedRuntime.revision = lockedRuntime.revision + 1
    for _, field in ipairs(changedFields) do markDirty(lockedRuntime, field) end
    syncPresentation(source, 'status_patch')
    return true, successResult(lockedRuntime, buildSnapshot(currentPlayer, lockedRuntime), true, nil, {
      changedFields = changedFields
    })
  end)
end

function MZPlayerStateService.applyObservedVitals(source, observedHealth, observedArmor)
  if not featureEnabled() then return false, errorResult('feature_disabled') end
  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  if runtime.unloading then return unloadingError(source, 'observed_vitals', { internal = true }, runtime) end

  local ok, result = withLock(source, 'observed_vitals', false, function(lockedRuntime)
    local currentPlayer, currentRuntime, currentErr = getPlayerAndRuntime(source)
    if not currentPlayer or currentRuntime ~= lockedRuntime then
      return false, errorResult(currentErr or 'player_not_loaded')
    end

    local deathState = tostring(currentPlayer.metadata.deathState or 'alive')
    if deathState == 'dead' or deathState == 'respawning' then
      return true, successResult(lockedRuntime, buildSnapshot(currentPlayer, lockedRuntime), false, 'state_ignored')
    end

    local nextHealth = observedHealth ~= nil and math.floor(tonumber(observedHealth) or -1) or nil
    local nextArmor = observedArmor ~= nil and math.floor(tonumber(observedArmor) or -1) or nil
    local healthDef = config().status.health
    local armorDef = config().status.armor
    if nextHealth ~= nil and (nextHealth < healthDef.min or nextHealth > healthDef.max) then
      return false, errorResult('invalid_value', { statusName = 'health' })
    end
    if nextArmor ~= nil and (nextArmor < armorDef.min or nextArmor > armorDef.max) then
      return false, errorResult('invalid_value', { statusName = 'armor' })
    end

    local currentHealth = tonumber(currentPlayer.metadata.health) or healthDef.default
    local currentArmor = tonumber(currentPlayer.metadata.armor) or armorDef.default
    if (nextHealth ~= nil and nextHealth > currentHealth) or (nextArmor ~= nil and nextArmor > currentArmor) then
      return false, errorResult('invalid_value', { reason = 'observed_increase' })
    end

    local changed = false
    local previousHealth, previousArmor = currentHealth, currentArmor
    if nextHealth ~= nil and nextHealth < currentHealth and nextHealth > 0 then
      currentPlayer.metadata.health = nextHealth
      markDirty(lockedRuntime, 'health')
      changed = true
    end
    if nextArmor ~= nil and nextArmor < currentArmor then
      currentPlayer.metadata.armor = nextArmor
      markDirty(lockedRuntime, 'armor')
      changed = true
    end
    if not changed then
      return true, successResult(lockedRuntime, buildSnapshot(currentPlayer, lockedRuntime), false, 'unchanged')
    end

    lockedRuntime.revision = lockedRuntime.revision + 1
    syncPresentation(source, 'vitals_observed')
    return true, successResult(lockedRuntime, buildSnapshot(currentPlayer, lockedRuntime), true, nil, {
      vitalChange = {
        kind = 'damage',
        cause = 'observed_vitals',
        healthDelta = math.max(0, previousHealth - (tonumber(currentPlayer.metadata.health) or previousHealth)),
        armorDelta = math.max(0, previousArmor - (tonumber(currentPlayer.metadata.armor) or previousArmor)),
        fatal = false,
        deathState = deathState
      }
    })
  end)
  local vitalChange = type(result) == 'table' and result.vitalChange or nil
  if vitalChange then
    result.vitalChange = nil
    emitVitalChanged(source, vitalChange)
  end
  return ok, result
end

local function boundedStatusValue(name, value, fallback)
  local definition = config().status[name] or {}
  local number = tonumber(value)
  if not number or number ~= number or number == math.huge or number == -math.huge then
    number = tonumber(fallback) or tonumber(definition.default) or 0
  end
  return math.max(tonumber(definition.min) or 0, math.min(tonumber(definition.max) or number, math.floor(number)))
end

local function applyDeathMetadata(metadata, nextState, operation, context)
  local timestamp = os.time()
  context = type(context) == 'table' and context or {}
  metadata.deathState = nextState
  local legacy = MZPlayerStateNormalizer.getLegacyFlags(nextState)
  metadata.isdead = legacy.isdead
  metadata.inlaststand = legacy.inlaststand
  local changedFields = { 'deathState', 'isdead', 'inlaststand' }
  if operation == 'mark_downed' then
    metadata.downedAt = timestamp
    metadata.health = math.max(
      tonumber(config().status.health.min) or 0,
      tonumber(config().death.downedHealth) or 1
    )
    metadata.armor = config().status.armor.min
    metadata.downedExpiresAt = nil
    metadata.deadAt, metadata.respawnAvailableAt = nil, nil
    metadata.reviveAt, metadata.respawnStartedAt, metadata.respawnCompletedAt = nil, nil, nil
    changedFields[#changedFields + 1] = 'downedAt'
    changedFields[#changedFields + 1] = 'downedExpiresAt'
    changedFields[#changedFields + 1] = 'health'
    changedFields[#changedFields + 1] = 'armor'
  elseif operation == 'mark_dead' then
    metadata.deadAt = timestamp
    metadata.downedExpiresAt = nil
    metadata.respawnAvailableAt = nil
    metadata.health = config().status.health.min
    metadata.armor = config().status.armor.min
    metadata.reviveAt, metadata.respawnStartedAt, metadata.respawnCompletedAt = nil, nil, nil
    changedFields[#changedFields + 1] = 'deadAt'
    changedFields[#changedFields + 1] = 'downedExpiresAt'
    changedFields[#changedFields + 1] = 'respawnAvailableAt'
    changedFields[#changedFields + 1] = 'health'
    changedFields[#changedFields + 1] = 'armor'
  elseif operation == 'revive' then
    metadata.reviveAt = timestamp
    metadata.health = boundedStatusValue('health', context.reviveHealth, config().status.health.default)
    metadata.armor = boundedStatusValue('armor', context.reviveArmor, config().status.armor.min)
    metadata.downedExpiresAt, metadata.respawnAvailableAt = nil, nil
    changedFields[#changedFields + 1] = 'reviveAt'
    changedFields[#changedFields + 1] = 'health'
    changedFields[#changedFields + 1] = 'armor'
    changedFields[#changedFields + 1] = 'downedExpiresAt'
    changedFields[#changedFields + 1] = 'respawnAvailableAt'
  elseif operation == 'begin_respawn' then
    metadata.respawnStartedAt = timestamp
    metadata.armor = config().status.armor.min
    changedFields[#changedFields + 1] = 'respawnStartedAt'
    changedFields[#changedFields + 1] = 'armor'
  elseif operation == 'abort_respawn' then
    metadata.health = config().status.health.min
    metadata.armor = config().status.armor.min
    metadata.respawnStartedAt = nil
    changedFields[#changedFields + 1] = 'health'
    changedFields[#changedFields + 1] = 'armor'
    changedFields[#changedFields + 1] = 'respawnStartedAt'
  elseif operation == 'complete_respawn' then
    metadata.respawnCompletedAt = timestamp
    metadata.health = boundedStatusValue('health', context.respawnHealth, config().status.health.default)
    metadata.armor = boundedStatusValue('armor', context.respawnArmor, config().status.armor.min)
    metadata.downedExpiresAt, metadata.respawnAvailableAt = nil, nil
    changedFields[#changedFields + 1] = 'respawnCompletedAt'
    changedFields[#changedFields + 1] = 'health'
    changedFields[#changedFields + 1] = 'armor'
    changedFields[#changedFields + 1] = 'downedExpiresAt'
    changedFields[#changedFields + 1] = 'respawnAvailableAt'
  end
  return changedFields, timestamp
end

function MZPlayerStateService.applyHealthDamage(source, amount, context)
  if not featureEnabled() then return false, errorResult('feature_disabled') end
  if not MZPlayerStateNormalizer.isFiniteNumber(amount) or tonumber(amount) <= 0 then
    return false, errorResult('invalid_value', { statusName = 'health' })
  end
  amount = math.max(1, math.floor(tonumber(amount)))
  local authorized, authErr = authorize(source, 'damage', context)
  if not authorized then return false, authErr end
  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  if runtime.unloading then return unloadingError(source, 'health_damage', context, runtime) end

  local ok, result = withLock(source, 'health_damage', false, function(lockedRuntime)
    local currentPlayer, currentRuntime, currentErr = getPlayerAndRuntime(source)
    if not currentPlayer or currentRuntime ~= lockedRuntime then
      return false, errorResult(currentErr or 'player_not_loaded')
    end
    if tostring(currentPlayer.metadata.deathState or 'alive') ~= 'alive' then
      return false, errorResult('invalid_state', { deathState = currentPlayer.metadata.deathState })
    end
    local definition = config().status.health
    local previousHealth = tonumber(currentPlayer.metadata.health) or definition.default
    local nextHealth = math.max(definition.min, previousHealth - amount)
    local cause = type(context) == 'table' and tostring(context.cause or context.reason or 'damage'):sub(1, 48) or 'damage'
    if nextHealth > definition.min then
      currentPlayer.metadata.health = nextHealth
      lockedRuntime.revision = lockedRuntime.revision + 1
      markDirty(lockedRuntime, 'health')
      syncPresentation(source, 'health_damage')
      return true, successResult(lockedRuntime, buildSnapshot(currentPlayer, lockedRuntime), true, nil, {
        vitalChange = {
          kind = 'damage', cause = cause, healthDelta = previousHealth - nextHealth,
          armorDelta = 0, fatal = false, deathState = 'alive'
        }
      })
    end

    local nextState = config().death and config().death.lastStandEnabled ~= false and 'downed' or 'dead'
    local operation = nextState == 'downed' and 'mark_downed' or 'mark_dead'
    local changedFields, timestamp = applyDeathMetadata(currentPlayer.metadata, nextState, operation, context)
    lockedRuntime.revision = lockedRuntime.revision + 1
    for _, field in ipairs(changedFields) do markDirty(lockedRuntime, field) end
    lockedRuntime.lastCriticalTransitionId = nextAuditId()
    lockedRuntime.lastCriticalTransitionAt = timestamp
    syncPresentation(source, 'fatal_health_damage', { forcePhysicalApply = true })
    safeLog('death_transition', source, {
      auditId = lockedRuntime.lastCriticalTransitionId,
      operation = operation,
      previousDeathState = 'alive',
      nextDeathState = nextState,
      reason = cause,
      invokingResource = context and context.invokingResource,
      actorSource = context and context.actorSource,
      result = 'changed',
      revision = lockedRuntime.revision
    })
    local vitalChange = {
      kind = 'damage', cause = cause, healthDelta = previousHealth,
      armorDelta = 0, fatal = true, deathState = nextState
    }
    local persisted, persistenceErr = criticalFlushLocked(source, currentPlayer, lockedRuntime, 'fatal_health_damage')
    if not persisted then
      persistenceErr.vitalChange = vitalChange
      return false, persistenceErr
    end
    return true, successResult(lockedRuntime, buildSnapshot(currentPlayer, lockedRuntime), true, nil, {
      vitalChange = vitalChange,
      deathChange = {
        previousState = 'alive',
        nextState = nextState,
        operation = operation,
        revision = lockedRuntime.revision,
        sessionId = lockedRuntime.sessionId,
        timestamp = timestamp
      }
    })
  end)
  local vitalChange = type(result) == 'table' and result.vitalChange or nil
  local deathChange = type(result) == 'table' and result.deathChange or nil
  if vitalChange then
    result.vitalChange = nil
    emitVitalChanged(source, vitalChange)
  end
  if deathChange then
    result.deathChange = nil
    emitDeathStateChanged(source, deathChange)
  end
  return ok, result
end

function MZPlayerStateService.applyHealing(source, amount, context)
  if not featureEnabled() then return false, errorResult('feature_disabled') end
  if not MZPlayerStateNormalizer.isFiniteNumber(amount) or tonumber(amount) <= 0 then
    return false, errorResult('invalid_value', { statusName = 'health' })
  end
  amount = math.max(1, math.floor(tonumber(amount)))
  local authorized, authErr = authorize(source, 'healing', context)
  if not authorized then return false, authErr end
  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  if runtime.unloading then return unloadingError(source, 'health_healing', context, runtime) end

  return withLock(source, 'health_healing', false, function(lockedRuntime)
    local currentPlayer, currentRuntime, currentErr = getPlayerAndRuntime(source)
    if not currentPlayer or currentRuntime ~= lockedRuntime then
      return false, errorResult(currentErr or 'player_not_loaded')
    end
    if tostring(currentPlayer.metadata.deathState or 'alive') ~= 'alive' then
      return false, errorResult('invalid_state', { deathState = currentPlayer.metadata.deathState })
    end
    local definition = config().status.health
    local current = tonumber(currentPlayer.metadata.health) or definition.default
    local nextValue = math.min(definition.max, current + amount)
    if nextValue == current then
      return false, errorResult('no_benefit', { statusName = 'health' })
    end
    currentPlayer.metadata.health = nextValue
    lockedRuntime.revision = lockedRuntime.revision + 1
    markDirty(lockedRuntime, 'health')
    syncPresentation(source, 'health_healing')
    return true, successResult(lockedRuntime, buildSnapshot(currentPlayer, lockedRuntime), true)
  end)
end

local function transitionDeath(source, nextState, operation, context)
  if not featureEnabled() then return false, errorResult('feature_disabled') end
  context = type(context) == 'table' and context or {}
  local authorizationKind = 'medical'
  if operation == 'revive' and context.administrative == true then authorizationKind = 'administrative' end
  local authorized, authErr = authorize(source, authorizationKind, context)
  if not authorized then return false, authErr end
  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  if runtime.unloading then return unloadingError(source, operation, context, runtime) end

  local ok, result = withLock(source, operation, false, function(lockedRuntime)
    local currentPlayer, currentRuntime, currentErr = getPlayerAndRuntime(source)
    if not currentPlayer or currentRuntime ~= lockedRuntime then return false, errorResult(currentErr or 'player_not_loaded') end
    if context.expectedRevision ~= nil and tonumber(context.expectedRevision) ~= tonumber(lockedRuntime.revision) then
      if MZPlayerStateObservability then
        MZPlayerStateObservability.record('player_state_transition_rejected', {
          source = source, citizenid = currentPlayer.citizenid, revision = lockedRuntime.revision,
          reason = context.reason, result = 'rejected', error = 'revision_mismatch',
          previousState = currentPlayer.metadata.deathState, nextState = nextState,
          operationId = context.operationId
        }, 'mz_core')
      end
      return false, errorResult('revision_mismatch', {
        expectedRevision = tonumber(context.expectedRevision), actualRevision = lockedRuntime.revision
      })
    end
    local previousState = currentPlayer.metadata.deathState
    if previousState == nextState then
      return true, successResult(lockedRuntime, buildSnapshot(currentPlayer, lockedRuntime), false, 'already_in_state')
    end

    local transitionAllowed = TRANSITIONS[previousState] and TRANSITIONS[previousState][nextState] == true
    if previousState == 'alive' and nextState == 'dead' and config().death.allowImmediateDeath == false then
      transitionAllowed = false
    end
    if previousState == 'dead' and nextState == 'alive' then
      transitionAllowed = context.administrative == true and config().death.allowAdministrativeReviveFromDead == true
    end
    if not transitionAllowed then
      safeLog('death_transition_rejected', source, {
        operation = operation, previousDeathState = previousState, nextDeathState = nextState,
        reason = context.reason, invokingResource = context.invokingResource, actorSource = context.actorSource,
        result = 'rejected', error = 'invalid_transition', revision = lockedRuntime.revision
      })
      if MZPlayerStateObservability then
        MZPlayerStateObservability.record('player_state_transition_rejected', {
          source = source, citizenid = currentPlayer.citizenid, revision = lockedRuntime.revision,
          previousState = previousState, nextState = nextState, reason = context.reason,
          result = 'rejected', error = 'invalid_transition', operationId = context.operationId
        }, 'mz_core')
      end
      return false, errorResult('invalid_transition', {
        previousDeathState = previousState,
        nextDeathState = nextState
      })
    end

    local changedFields, timestamp = applyDeathMetadata(currentPlayer.metadata, nextState, operation, context)
    lockedRuntime.revision = lockedRuntime.revision + 1
    for _, field in ipairs(changedFields) do markDirty(lockedRuntime, field) end
    lockedRuntime.lastCriticalTransitionId = nextAuditId()
    lockedRuntime.lastCriticalTransitionAt = timestamp
    syncPresentation(source, operation, { forcePhysicalApply = true })
    safeLog('death_transition', source, {
      auditId = lockedRuntime.lastCriticalTransitionId,
      operation = operation, previousDeathState = previousState, nextDeathState = nextState,
      reason = context.reason, invokingResource = context.invokingResource, actorSource = context.actorSource,
      result = 'changed', revision = lockedRuntime.revision
    })
    if MZPlayerStateObservability then
      MZPlayerStateObservability.playerTransition(source, previousState, nextState)
      MZPlayerStateObservability.record('player_state_transition', {
        auditId = lockedRuntime.lastCriticalTransitionId,
        operationId = context.operationId,
        source = source,
        target = source,
        citizenid = currentPlayer.citizenid,
        session = tostring(lockedRuntime.sessionId or ''),
        revision = lockedRuntime.revision,
        previousState = previousState,
        nextState = nextState,
        reason = context.reason,
        result = 'changed'
      }, 'mz_core')
    end

    local persisted, persistenceErr = criticalFlushLocked(source, currentPlayer, lockedRuntime, operation)
    if not persisted then return false, persistenceErr end
    return true, successResult(lockedRuntime, buildSnapshot(currentPlayer, lockedRuntime), true, nil, {
      deathChange = {
        previousState = previousState,
        nextState = nextState,
        operation = operation,
        revision = lockedRuntime.revision,
        sessionId = lockedRuntime.sessionId,
        timestamp = timestamp
      }
    })
  end)
  local deathChange = type(result) == 'table' and result.deathChange or nil
  if deathChange then
    result.deathChange = nil
    emitDeathStateChanged(source, deathChange)
  end
  return ok, result
end

function MZPlayerStateService.markDowned(source, context)
  return transitionDeath(source, 'downed', 'mark_downed', context)
end

function MZPlayerStateService.markDead(source, context)
  return transitionDeath(source, 'dead', 'mark_dead', context)
end

function MZPlayerStateService.revive(source, context)
  return transitionDeath(source, 'alive', 'revive', context)
end

function MZPlayerStateService.beginRespawn(source, context)
  return transitionDeath(source, 'respawning', 'begin_respawn', context)
end

function MZPlayerStateService.completeRespawn(source, context)
  return transitionDeath(source, 'alive', 'complete_respawn', context)
end

function MZPlayerStateService.abortRespawn(source, context)
  return transitionDeath(source, 'dead', 'abort_respawn', context)
end

function MZPlayerStateService.setDeathDeadline(source, deadlineKind, deadline, context)
  if not featureEnabled() then return false, errorResult('feature_disabled') end
  context = type(context) == 'table' and context or {}
  local authorized, authErr = authorize(source, 'medical', context)
  if not authorized then return false, authErr end

  local definitions = {
    downed = { state = 'downed', field = 'downedExpiresAt' },
    respawn = { state = 'dead', field = 'respawnAvailableAt' }
  }
  local definition = definitions[tostring(deadlineKind or '')]
  deadline = tonumber(deadline)
  if not definition or not deadline or deadline ~= deadline or deadline == math.huge or deadline == -math.huge then
    return false, errorResult('invalid_deadline')
  end
  deadline = math.floor(deadline)
  local maximum = os.time() + 86400
  if deadline < os.time() - 60 or deadline > maximum then
    return false, errorResult('invalid_deadline')
  end

  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  if runtime.unloading then return unloadingError(source, 'set_death_deadline', context, runtime) end

  return withLock(source, 'set_death_deadline', false, function(lockedRuntime)
    local currentPlayer, currentRuntime, currentErr = getPlayerAndRuntime(source)
    if not currentPlayer or currentRuntime ~= lockedRuntime then
      return false, errorResult(currentErr or 'player_not_loaded')
    end
    local currentState = tostring(currentPlayer.metadata.deathState or 'alive')
    if currentState ~= definition.state then
      return false, errorResult('invalid_state', { deathState = currentState })
    end
    local currentDeadline = tonumber(currentPlayer.metadata[definition.field])
    if currentDeadline then
      if math.floor(currentDeadline) == deadline then
        return true, successResult(lockedRuntime, buildSnapshot(currentPlayer, lockedRuntime), false, 'already_in_state')
      end
      return false, errorResult('invalid_deadline', { reason = 'deadline_already_set' })
    end

    currentPlayer.metadata[definition.field] = deadline
    lockedRuntime.revision = lockedRuntime.revision + 1
    markDirty(lockedRuntime, definition.field)
    syncPresentation(source, 'death_deadline_set')
    local persisted, persistenceErr = criticalFlushLocked(source, currentPlayer, lockedRuntime, 'death_deadline_set')
    if not persisted then return false, persistenceErr end
    return true, successResult(lockedRuntime, buildSnapshot(currentPlayer, lockedRuntime), true)
  end)
end

function MZPlayerStateService.canPerformAction(source, action)
  action = tostring(action or '')
  local registered = false
  for _, configuredAction in ipairs(config().actions or {}) do
    if configuredAction == action then registered = true break end
  end
  if not registered then return false, errorResult('invalid_action', { action = action }) end
  local ok, result = MZPlayerStateService.getState(source)
  if not ok then return false, result end
  return true, {
    revision = result.revision,
    action = action,
    allowed = result.state.deathState == 'alive',
    deathState = result.state.deathState
  }
end

function MZPlayerStateService.flush(source, reason, force, context)
  if config().enabled == false then return false, errorResult('feature_disabled') end
  context = type(context) == 'table' and context or {}
  local authorized, authErr = authorize(source, 'persistence', context)
  if not authorized then return false, authErr end
  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  if runtime.unloading and reason == 'periodic' then return unloadingError(source, 'periodic_flush', context, runtime) end
  if runtime.unloading and context.internal ~= true then return unloadingError(source, 'flush', context, runtime) end
  if force ~= true and runtime.dirtySince then
    local debounce = tonumber(config().persistence and config().persistence.debounceMs) or 5000
    if nowMs() - runtime.dirtySince < debounce then
      return true, successResult(runtime, buildSnapshot(player, runtime), false, 'debounced')
    end
  end
  return withLock(source, 'flush', context.internal == true, function(lockedRuntime)
    return flushLocked(source, player, lockedRuntime, reason or 'manual')
  end)
end

function MZPlayerStateService.setGenericMetadata(source, key, value, context)
  if PROTECTED_METADATA[key] then
    safeLog('protected_metadata_blocked', source, {
      operation = 'set_metadata', statusName = key, reason = context and context.reason,
      invokingResource = context and context.invokingResource, actorSource = context and context.actorSource,
      result = 'rejected', error = 'protected_metadata'
    })
    safeSuspiciousActivity(source, {
      operation = 'set_metadata', statusName = key, reason = context and context.reason,
      invokingResource = context and context.invokingResource, actorSource = context and context.actorSource,
      result = 'rejected', error = 'protected_metadata', attemptedValue = value
    })
    return false, errorResult('protected_metadata', { key = key, use = PROTECTED_METADATA[key] })
  end
  if type(key) ~= 'string' or key == '' then return false, errorResult('invalid_value', { field = 'key' }) end
  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  if runtime.unloading then return unloadingError(source, 'set_metadata', context, runtime) end
  return withLock(source, 'set_metadata', false, function(lockedRuntime)
    if player.metadata[key] == value then
      return true, successResult(lockedRuntime, buildSnapshot(player, lockedRuntime), false, 'unchanged')
    end
    player.metadata[key] = clone(value)
    markDirty(lockedRuntime, key)
    local persisted, persistResult = flushLocked(source, player, lockedRuntime, 'legacy_metadata_set')
    if not persisted then return false, errorResult('persistence_pending', { persistenceError = persistResult }) end
    if MZPlayerHUDService and MZPlayerHUDService.syncToClient then
      MZPlayerHUDService.syncToClient(source)
    end
    return true, successResult(lockedRuntime, buildSnapshot(player, lockedRuntime), true)
  end)
end

function MZPlayerStateService.applyBridgeMetadataPatch(source, patch, context)
  if type(patch) ~= 'table' then return false, errorResult('invalid_value') end
  for key in pairs(patch) do
    if PROTECTED_METADATA[key] and not (config().status and config().status[key]) then
      safeLog('protected_metadata_blocked', source, {
        operation = 'bridge_metadata_patch', statusName = key,
        reason = context and context.reason,
        invokingResource = context and context.invokingResource,
        actorSource = context and context.actorSource,
        result = 'rejected', error = 'protected_metadata'
      })
      safeSuspiciousActivity(source, {
        operation = 'bridge_metadata_patch', statusName = key,
        reason = context and context.reason,
        invokingResource = context and context.invokingResource,
        actorSource = context and context.actorSource,
        result = 'rejected', error = 'protected_metadata', attemptedValue = patch[key]
      })
      return false, errorResult('protected_metadata', { key = key, use = PROTECTED_METADATA[key] })
    end
    local definition = config().status and config().status[key]
    if definition then
      local authorized, authErr = authorize(source, statusAuthorization(key), context)
      if not authorized then
        return false, authErr
      end
      if not MZPlayerStateNormalizer.isFiniteNumber(patch[key]) then
        return false, errorResult('invalid_value', { statusName = key })
      end
    end
  end
  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  if runtime.unloading then return unloadingError(source, 'bridge_metadata_patch', context, runtime) end
  return withLock(source, 'bridge_metadata_patch', false, function(lockedRuntime)
    local changed, stateChanged = false, false
    for key, value in pairs(patch) do
      local definition = config().status and config().status[key]
      local nextValue = clone(value)
      if definition then
        nextValue = math.floor(tonumber(value))
        if nextValue < definition.min then nextValue = definition.min end
        if nextValue > definition.max then nextValue = definition.max end
      end
      if player.metadata[key] ~= nextValue then
        player.metadata[key] = nextValue
        markDirty(lockedRuntime, key)
        changed = true
        stateChanged = stateChanged or definition ~= nil
      end
    end
    if not changed then return true, successResult(lockedRuntime, buildSnapshot(player, lockedRuntime), false, 'unchanged') end
    if stateChanged then lockedRuntime.revision = lockedRuntime.revision + 1 end
    local persisted, persistResult = flushLocked(source, player, lockedRuntime, 'qb_metadata_patch')
    if not persisted then return false, errorResult('persistence_pending', { persistenceError = persistResult }) end
    if stateChanged then
      syncPresentation(source, 'bridge_status_patch')
    elseif MZPlayerHUDService and MZPlayerHUDService.syncToClient then
      MZPlayerHUDService.syncToClient(source)
    end
    return true, successResult(lockedRuntime, buildSnapshot(player, lockedRuntime), true)
  end)
end

function MZPlayerStateService.getSyncIdentity(source)
  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  if runtime.unloading then return false, errorResult('unloading') end
  return true, {
    revision = runtime.revision,
    sessionToken = runtime.syncSessionToken,
    observationToken = runtime.observationToken
  }
end

function MZPlayerStateService.getRuntimeIdentity(source)
  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  if runtime.unloading then return false, errorResult('unloading') end
  if runtime.sessionId == nil then return false, errorResult('session_unavailable') end
  return true, {
    sessionId = tostring(runtime.sessionId),
    revision = runtime.revision
  }
end

function MZPlayerStateService.authorizeClientResync(source)
  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  if runtime.unloading then return false, errorResult('unloading') end

  local current = nowMs()
  local cooldown = tonumber(config().sync and config().sync.resyncCooldownMs) or 5000
  if runtime.clientSync.lastResyncAt and current - runtime.clientSync.lastResyncAt < cooldown then
    return false, errorResult('invalid_value', { reason = 'rate_limited' })
  end

  runtime.clientSync.lastResyncAt = current
  runtime.observationToken = opaqueToken('observation', source)
  runtime.clientSync.reportWindowStartedAt = nil
  runtime.clientSync.reportCount = 0
  runtime.clientSync.lastSequence = 0
  runtime.clientSync.fatalCandidateStartedAt = nil
  runtime.clientSync.fatalCandidateCount = 0
  runtime.clientSync.lastFatalCandidateAt = nil
  return true, {
    sessionToken = runtime.syncSessionToken,
    observationToken = runtime.observationToken,
    revision = runtime.revision
  }
end

function MZPlayerStateService.validateObservationEnvelope(source, envelope)
  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  if runtime.unloading then return false, errorResult('unloading') end
  if type(envelope) ~= 'table'
    or envelope.sessionToken ~= runtime.syncSessionToken
    or envelope.observationToken ~= runtime.observationToken then
    return false, errorResult('invalid_value', { reason = 'invalid_session' })
  end

  local sequence = tonumber(envelope.sequence)
  local localRevision = tonumber(envelope.localRevision)
  if not sequence or sequence ~= math.floor(sequence) or sequence <= runtime.clientSync.lastSequence then
    return false, errorResult('invalid_value', { reason = 'stale_sequence' })
  end
  if not localRevision or localRevision ~= runtime.revision then
    return false, errorResult('invalid_value', { reason = 'stale_revision' })
  end

  runtime.clientSync.lastSequence = sequence
  return true, { revision = runtime.revision }
end

function MZPlayerStateService.consumeClientEventAttempt(source, bucket, maximum, windowMs)
  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  if runtime.unloading then return false, errorResult('unloading') end
  bucket = tostring(bucket or '')
  if bucket ~= 'resync' and bucket ~= 'observation' then
    return false, errorResult('invalid_value', { reason = 'invalid_bucket' })
  end
  maximum = math.max(1, math.floor(tonumber(maximum) or 1))
  windowMs = math.max(1000, math.floor(tonumber(windowMs) or 10000))
  local current = nowMs()
  local window = runtime.clientSync.eventWindows[bucket]
  if not window or current - window.startedAt >= windowMs then
    window = { startedAt = current, count = 0 }
    runtime.clientSync.eventWindows[bucket] = window
  end
  if window.count >= maximum then
    return false, errorResult('invalid_value', { reason = 'rate_limited' })
  end
  window.count = window.count + 1
  return true, { remaining = maximum - window.count }
end

function MZPlayerStateService.registerFatalCandidate(source, serverConfirmed)
  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  if runtime.unloading then return false, errorResult('unloading') end
  if tostring(player.metadata.deathState or 'alive') ~= 'alive' then
    return true, { transition = false, code = 'state_ignored', revision = runtime.revision }
  end

  if serverConfirmed == true then
    runtime.clientSync.fatalCandidateStartedAt = nil
    runtime.clientSync.fatalCandidateCount = 0
    return true, { transition = true, confirmedByServer = true, revision = runtime.revision }
  end

  local current = nowMs()
  local reconciliation = config().reconciliation or {}
  local minimumInterval = tonumber(reconciliation.fatalServerMinimumIntervalMs) or 500
  if runtime.clientSync.lastFatalCandidateAt
    and current - runtime.clientSync.lastFatalCandidateAt < minimumInterval then
    return true, { transition = false, code = 'fatal_cooldown', revision = runtime.revision }
  end
  runtime.clientSync.lastFatalCandidateAt = current
  local windowMs = tonumber(reconciliation.fatalCandidateWindowMs) or 5000
  local required = math.max(2, math.floor(tonumber(reconciliation.requiredFatalReportsWithoutServerConfirmation) or 2))
  if not runtime.clientSync.fatalCandidateStartedAt
    or current - runtime.clientSync.fatalCandidateStartedAt > windowMs then
    runtime.clientSync.fatalCandidateStartedAt = current
    runtime.clientSync.fatalCandidateCount = 0
  end
  runtime.clientSync.fatalCandidateCount = runtime.clientSync.fatalCandidateCount + 1
  local transition = runtime.clientSync.fatalCandidateCount >= required
  if transition then
    runtime.clientSync.fatalCandidateStartedAt = nil
    runtime.clientSync.fatalCandidateCount = 0
  end
  return true, {
    transition = transition,
    confirmedByServer = false,
    candidateCount = transition and required or runtime.clientSync.fatalCandidateCount,
    required = required,
    revision = runtime.revision
  }
end

function MZPlayerStateService.shouldLogClientSyncRejection(source, cooldownMs)
  local _, runtime = getPlayerAndRuntime(source)
  if not runtime then return false end
  local current = nowMs()
  local cooldown = tonumber(cooldownMs) or 3000
  if runtime.clientSync.lastRejectLogAt and current - runtime.clientSync.lastRejectLogAt < cooldown then
    return false
  end
  runtime.clientSync.lastRejectLogAt = current
  return true
end

function MZPlayerStateService.beginUnload(source, reason)
  local player, runtime, playerErr = getPlayerAndRuntime(source)
  if not player or not runtime then return false, errorResult(playerErr) end
  runtime.unloading = true
  local ok, result = withLock(source, 'unload_flush', true, function(lockedRuntime)
    return flushLocked(source, player, lockedRuntime, reason or 'unload')
  end)
  if not ok then
    safeLog('final_flush_failed', source, {
      operation = 'unload_flush', reason = reason, result = 'failed',
      error = result and result.code or 'persistence_failed', revision = runtime.revision
    })
  end
  return ok, result
end

function MZPlayerStateService.finalizeUnload(source)
  if MZPlayerStateObservability then MZPlayerStateObservability.playerUnloaded(source) end
  RuntimeStates[tonumber(source)] = nil
end

function MZPlayerStateService.beginShutdown()
  shuttingDown = true
end

function MZPlayerStateService.clearRuntime()
  RuntimeStates = {}
end

function MZPlayerStateService.internalContext(reason, extra)
  local context = clone(type(extra) == 'table' and extra or {})
  context.reason = context.reason or reason
  context.internal = true
  context.invokingResource = GetCurrentResourceName and GetCurrentResourceName() or 'mz_core'
  return context
end

function MZPlayerStateService.isProtectedMetadataKey(key)
  return PROTECTED_METADATA[key] ~= nil, PROTECTED_METADATA[key]
end

if rawget(_G, 'MZ_PLAYER_STATE_TESTING') == true then
  MZPlayerStateService._test = {
    getRuntime = function(source) return RuntimeStates[tonumber(source)] end,
    setLock = function(source, value) RuntimeStates[tonumber(source)].lock = value end,
    markDirty = markDirty,
    resetShutdown = function() shuttingDown = false end
  }
end

if type(CreateThread) == 'function' then
  CreateThread(function()
    while true do
      local interval = tonumber(config().persistence and config().persistence.flushIntervalMs) or 30000
      Wait(interval)
      if not shuttingDown and config().enabled ~= false then
        local sources = {}
        for source, runtime in pairs(RuntimeStates) do
          if runtime.unloading ~= true and next(runtime.dirty) ~= nil then sources[#sources + 1] = source end
        end
        table.sort(sources)
        for _, source in ipairs(sources) do
          local ok, err = xpcall(function()
            MZPlayerStateService.flush(source, 'periodic', false, MZPlayerStateService.internalContext('periodic'))
          end, debug.traceback)
          if not ok then
            safeLog('periodic_flush_failed', source, {
              operation = 'periodic_flush', result = 'failed', error = 'internal_error'
            })
            print(('[mz_core][player_state][periodic_flush_failed] source=%s error=%s'):format(tostring(source), tostring(err)))
          end
        end
      end
    end
  end)
end
