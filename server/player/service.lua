MZPlayerService = {}

local CORE_READY_WAIT_STEP_MS = 50
local CORE_READY_WAIT_TIMEOUT_MS = 15000
local LOAD_IN_FLIGHT_WAIT_TIMEOUT_MS = 15000
local MAX_METADATA_BYTES = 65536
local LoadInFlightBySource = {}

local function finiteNumber(value)
  value = tonumber(value)
  if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
  return value
end

local function databaseBoolean(value)
  return value == true or tonumber(value) == 1
end

local function normalizePersistedPosition(coords)
  if type(coords) ~= 'table' then return nil end
  local x = finiteNumber(coords.x)
  local y = finiteNumber(coords.y)
  local z = finiteNumber(coords.z)
  local heading = finiteNumber(coords.heading or 0.0)
  if not x or not y or not z or not heading then return nil end
  if math.abs(x) > 20000.0 or math.abs(y) > 20000.0 or z < -2000.0 or z > 3000.0 then return nil end
  heading = heading % 360.0
  return { x = x, y = y, z = z, heading = heading }
end

local function buildPlayerData(source, row)
  local metadata, metadataChanged, metadataCorrections, metadataDecodeInvalid =
    MZPlayerStateNormalizer.decodeAndNormalize(row.metadata)

  return {
    source = source,
    accountId = tonumber(row.account_id),
    characterId = tonumber(row.id),
    metadataVersion = row.metadata_version_exact,
    citizenid = row.citizenid,
    charinfo = {
      firstname = row.firstname,
      lastname = row.lastname,
      birthdate = row.birthdate,
      gender = row.gender,
      nationality = row.nationality,
      phone = row.phone
    },
    metadata = metadata,
    state = {
      loaded = true,
      loadedAt = os.time(),
      lastSeenAt = os.time()
    },
    session = nil
  }, {
    changed = metadataChanged,
    corrections = metadataCorrections,
    decodeInvalid = metadataDecodeInvalid
  }
end

local function buildSessionData(source, player, sessionRow)
  if not sessionRow then return nil end

  return {
    id = tonumber(sessionRow.id or sessionRow.sessionId),
    sessionId = tonumber(sessionRow.id or sessionRow.sessionId),
    source = source,
    accountId = tonumber(sessionRow.accountId or sessionRow.account_id or player.accountId),
    characterId = tonumber(sessionRow.characterId or sessionRow.character_id or player.characterId),
    activeCharacterId = tonumber(sessionRow.activeCharacterId or sessionRow.active_character_id or player.characterId),
    citizenid = player.citizenid,
    joinedAt = sessionRow.joinedAt or sessionRow.joined_at,
    lastSeenAt = sessionRow.lastSeenAt or sessionRow.last_seen_at,
    lifecycle = tostring(sessionRow.lifecycle or 'CHARACTER_ACTIVATING'),
    revision = tonumber(sessionRow.revision) or 1,
    isActive = sessionRow.isActive == true or databaseBoolean(sessionRow.is_active)
  }
end

local function refreshSessionState(player, sessionRow)
  if not player then return end

  player.state = player.state or {}
  player.state.loaded = true
  player.state.loadedAt = player.state.loadedAt or os.time()
  player.state.lastSeenAt = os.time()
  player.session = buildSessionData(player.source, player, sessionRow)
end

local function waitForCoreReady(timeoutMs)
  if not MZCoreState or MZCoreState.ready == true then
    return true
  end

  local waited = 0
  local maxWait = tonumber(timeoutMs) or CORE_READY_WAIT_TIMEOUT_MS

  while true do
    if MZCoreState and MZCoreState.ready == true then
      return true
    end

    if MZCoreState and MZCoreState.prepareDone == true and MZCoreState.prepareOk ~= true then
      return false, 'core_prepare_failed'
    end

    if MZCoreState and MZCoreState.seedDone == true and MZCoreState.seedOk ~= true then
      return false, 'core_seed_failed'
    end

    if waited >= maxWait then
      return false, 'core_not_ready'
    end

    Wait(CORE_READY_WAIT_STEP_MS)
    waited = waited + CORE_READY_WAIT_STEP_MS
  end
end

local function waitForLoadInFlight(source, timeoutMs, attempt)
  local waited = 0
  local maxWait = tonumber(timeoutMs) or LOAD_IN_FLIGHT_WAIT_TIMEOUT_MS

  while LoadInFlightBySource[source] == attempt do
    if waited >= maxWait then
      return false, 'load_player_timeout'
    end

    Wait(CORE_READY_WAIT_STEP_MS)
    waited = waited + CORE_READY_WAIT_STEP_MS
  end

  local cached = MZCache.playersBySource[source]
  if cached then
    if not cached.state or cached.state.loaded ~= true then return false, 'player_cleanup_pending' end
    return true, cached
  end

  return false, 'load_player_failed'
end

function MZPlayerService.loadCharacter(source, row, session)
  local cached = MZCache.playersBySource[source]
  if cached then
    if cached._activationPending then return nil, 'activation_in_progress' end
    if not cached.state or cached.state.loaded ~= true then return nil, 'player_cleanup_pending' end
    if tonumber(cached.characterId) == tonumber(row and row.id)
      and cached.session and session and tonumber(cached.session.id) == tonumber(session.id) then
      MZPlayerService.touchPlayer(source)
      local current = MZIdentityService.getSession(source)
      if MZCache.playersBySource[source] ~= cached or not current or tonumber(current.id) ~= tonumber(session.id) then
        return nil, 'session_changed'
      end
      return cached
    end
    return nil, 'different_character_already_loaded'
  end

  local readyOk, readyErr = waitForCoreReady(CORE_READY_WAIT_TIMEOUT_MS)
  if not readyOk then
    return nil, readyErr
  end

  local inFlight = LoadInFlightBySource[source]
  if inFlight and session and inFlight.sessionId == tonumber(session.id) then
    local waitOk, resultOrErr = waitForLoadInFlight(source, LOAD_IN_FLIGHT_WAIT_TIMEOUT_MS, inFlight)
    if waitOk then
      if tonumber(resultOrErr.characterId) ~= tonumber(row and row.id)
        or not resultOrErr.session or not session or tonumber(resultOrErr.session.id) ~= tonumber(session.id) then
        return nil, 'session_changed'
      end
      return resultOrErr
    end

    return nil, resultOrErr
  end

  if inFlight then
    local current = MZIdentityService.getSession(source)
    if not current or not session or tonumber(current.id) ~= tonumber(session.id) then return nil, 'session_changed' end
  end
  local loadAttempt = { sessionId = session and tonumber(session.id) }
  LoadInFlightBySource[source] = loadAttempt

  local attemptPlayer, reserved
  local function sessionMatches()
    local current = MZIdentityService.getSession(source)
    return current and current.isActive == true and session and tonumber(current.id) == tonumber(session.id)
      and tonumber(current.accountId) == tonumber(session.accountId)
      and tonumber(current.activeCharacterId) == tonumber(row and row.id)
  end
  local ok, playerData, err = xpcall(function()
    if type(row) ~= 'table' or not row.id or not row.account_id or not row.citizenid then
      return nil, 'invalid_character'
    end
    if type(session) ~= 'table' or tonumber(session.accountId) ~= tonumber(row.account_id)
      or tonumber(session.activeCharacterId) ~= tonumber(row.id) then
      return nil, 'invalid_session_binding'
    end
    if not sessionMatches() then return nil, 'session_changed' end

    local admitted, admissionErr = MZPlayerStateService.reservePlayer(session.accountId, row.id, row.citizenid, session.id, source)
    if not admitted then return nil, admissionErr end
    reserved = true

    local fencedRow, barrierErr = MZPlayerRepository.establishMetadataBarrier(session.accountId, row.id, session.id)
    if not fencedRow then return nil, barrierErr or 'barrier_unconfirmed' end
    if not sessionMatches() then return nil, 'session_changed' end
    row = fencedRow
    if type(row.metadata) == 'string' and #row.metadata > MAX_METADATA_BYTES then return nil, 'player_state_too_large' end
    if type(row.metadata) == 'table' then
      local encodedOk, encoded = pcall(MZUtils.jsonEncode, row.metadata)
      if not encodedOk or type(encoded) ~= 'string' or #encoded > MAX_METADATA_BYTES then return nil, 'player_state_too_large' end
    end

    local playerData, metadataNormalization = buildPlayerData(source, row)
    attemptPlayer = playerData
    playerData._activationPending = session.lifecycle == 'CHARACTER_ACTIVATING'
    refreshSessionState(playerData, session)

    MZCache.playersBySource[source] = playerData
    MZCache.playersByCitizenId[playerData.citizenid] = playerData
    MZCache.playersByCharacterId[playerData.characterId] = playerData

    local stateInitialized, stateInitResult = MZPlayerStateService.initializePlayer(
      source,
      metadataNormalization.changed and metadataNormalization.corrections or nil
    )
    if not stateInitialized then
      print(('[mz_core][player_state] initialization incomplete source=%s code=%s'):format(
        tostring(source),
        tostring(stateInitResult and stateInitResult.code or 'unknown')
      ))
    end
    if not sessionMatches() or MZCache.playersBySource[source] ~= playerData then return nil, 'session_changed' end

    local stateReady, stateReadyResult = MZPlayerStateService.getState(source, true)
    if not stateReady then
      return nil, stateReadyResult and stateReadyResult.code or 'player_state_initialization_failed'
    end

    MZLogService.createDetailed('player', 'loaded', {
      actor = MZLogService.makeActor('player', playerData.citizenid, {
        source = source,
      }),
      target = MZLogService.makeTarget('session', session and session.id or 'unknown', {
        citizenid = playerData.citizenid
      }),
      context = {
        source = source,
      },
      after = {
        state = playerData.state,
        session = playerData.session
      },
      meta = {
        event = 'load_player'
      }
    })

    if not sessionMatches() or MZCache.playersBySource[source] ~= playerData then return nil, 'session_changed' end
    return playerData
  end, debug.traceback)

  if LoadInFlightBySource[source] == loadAttempt then LoadInFlightBySource[source] = nil end

  if (not ok or not playerData) and attemptPlayer then
    if MZCache.playersBySource[source] == attemptPlayer then
      if MZPlayerStateService.markDisconnecting then MZPlayerStateService.markDisconnecting(attemptPlayer) end
      local flushCall, flushOk = pcall(MZPlayerStateService.beginUnload, source, 'activation_failed')
      if flushCall then
        local finalized, cleared = pcall(MZPlayerStateService.finalizeUnload, source, attemptPlayer.session and attemptPlayer.session.id)
        if finalized and cleared ~= false then
          if MZCache.playersBySource[source] == attemptPlayer then MZCache.playersBySource[source] = nil end
        else
          attemptPlayer.state.loaded = false
          print(('[mz_core][player_state][activation_cleanup_failed] source=%s'):format(tostring(source)))
        end
      else
        attemptPlayer.state.loaded = false
        print(('[mz_core][player_state][activation_cleanup_pending] source=%s citizenid=%s'):format(
          tostring(source), tostring(attemptPlayer.citizenid)))
      end
    end
    if MZCache.playersBySource[source] ~= attemptPlayer then
      if MZCache.playersByCitizenId[attemptPlayer.citizenid] == attemptPlayer then
        MZCache.playersByCitizenId[attemptPlayer.citizenid] = nil
      end
      if MZCache.playersByCharacterId[attemptPlayer.characterId] == attemptPlayer then
        MZCache.playersByCharacterId[attemptPlayer.characterId] = nil
      end
    end
  end

  if (not ok or not playerData) and reserved then
    MZPlayerStateService.releasePlayer(row.id, session.id)
  end

  if not ok then
    print(('[mz_core] loadCharacter failed for source %s: %s'):format(tostring(source), tostring(playerData)))
    return nil, playerData
  end

  return playerData, err
end

function MZPlayerService.touchPlayer(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false end

  player.state = player.state or {}
  player.state.lastSeenAt = os.time()

  if player.session and player.session.id then
    MZIdentityRepository.touchSession(player.session.id, source)
    player.session.lastSeenAt = os.date('!%Y-%m-%d %H:%M:%S')
  end

  return true
end

function MZPlayerService.getPlayer(source)
  return MZCache.playersBySource[source]
end

function MZPlayerService.getPlayerByCitizenId(citizenid)
  local player = MZCache.playersByCitizenId[citizenid]
  return player and not player._activationPending and player or nil
end

local function cloneSnapshotValue(value, depth)
  if type(value) ~= 'table' then return value end
  depth = (tonumber(depth) or 0) + 1
  if depth > 5 then return nil end
  local result = {}
  for key, item in pairs(value) do
    if type(key) == 'string' or type(key) == 'number' then
      result[key] = cloneSnapshotValue(item, depth)
    end
  end
  return result
end

local function playerSnapshot(player)
  if type(player) ~= 'table' then return nil end
  if player._activationPending then return nil end
  return {
    source = tonumber(player.source),
    accountId = tonumber(player.accountId),
    characterId = tonumber(player.characterId),
    citizenid = tostring(player.citizenid or ''),
    charinfo = cloneSnapshotValue(player.charinfo or {}, 0),
    state = cloneSnapshotValue(player.state or {}, 0),
    session = player.session and {
      id = player.session.id,
      sessionId = player.session.id,
      source = tonumber(player.session.source),
      accountId = tonumber(player.session.accountId),
      characterId = tonumber(player.session.characterId),
      activeCharacterId = tonumber(player.session.activeCharacterId),
      citizenid = tostring(player.session.citizenid or ''),
      joinedAt = player.session.joinedAt,
      lastSeenAt = player.session.lastSeenAt,
      lifecycle = tostring(player.session.lifecycle or ''),
      revision = tonumber(player.session.revision) or 1,
      isActive = player.session.isActive == true
    } or nil
  }
end

function MZPlayerService.getPlayerSnapshot(source)
  if not MZPlayerService.isPlayerLoaded(source) then return nil end
  return playerSnapshot(MZPlayerService.getPlayer(source))
end

function MZPlayerService.getPlayerByCitizenIdSnapshot(citizenid)
  local player = MZPlayerService.getPlayerByCitizenId(citizenid)
  if not player or not MZPlayerService.isPlayerLoaded(player.source) then return nil end
  return playerSnapshot(player)
end

function MZPlayerService.getSourceByCitizenId(citizenid)
  local player = MZPlayerService.getPlayerByCitizenId(citizenid)
  return player and player.source or nil
end

function MZPlayerService.getPlayerSession(source)
  return MZIdentityService.getSession(source)
end

function MZPlayerService.isPlayerLoaded(source)
  local player = MZPlayerService.getPlayer(source)
  local session = MZIdentityService.getSession(source)
  return player ~= nil and player.state ~= nil and player.state.loaded == true
    and not player._activationPending
    and session ~= nil and session.isActive == true
    and player.session ~= nil and tonumber(player.session.id) == tonumber(session.id)
    and tonumber(player.accountId) == tonumber(session.accountId)
    and tonumber(session.activeCharacterId) == tonumber(player.characterId)
end

function MZPlayerService.publishPlayerLoaded(source, player)
  local session = MZIdentityService.getSession(source)
  if not player or not session or session.isActive ~= true
    or MZCache.playersBySource[source] ~= player
    or not player.session or tonumber(player.session.id) ~= tonumber(session.id)
    or tonumber(player.accountId) ~= tonumber(session.accountId)
    or not session.activeCharacterId
    or tonumber(session.activeCharacterId) ~= tonumber(player.characterId) then
    return false, 'active_character_required'
  end

  local identityOk, syncIdentity = MZPlayerStateService.getSyncIdentity(source)
  if not identityOk then
    local code = syncIdentity and syncIdentity.code or 'player_state_not_ready'
    print(('[mz_core][player_state][player_loaded_blocked] source=%s code=%s'):format(
      tostring(source), tostring(code)
    ))
    return false, code
  end
  TriggerClientEvent(
    'mz_core:client:playerLoaded',
    source,
    MZPlayerService.getPlayerSnapshot(source),
    syncIdentity.sessionToken
  )
  TriggerEvent('mz_core:server:playerLoaded', source, MZPlayerService.getPlayerSnapshot(source))
  MZIdentityService.debugLifecycle('playerLoadedPublished', source, session, player.characterId)
  if MZPlayerStateSyncService and MZPlayerStateSyncService.sync then
    MZPlayerStateSyncService.sync(source, 'character_activated', {
      forcePhysicalApply = true,
      sessionReset = true
    })
  end
  return true
end

function MZPlayerService.validateCharinfo(charinfo, requireIdentity)
  if type(charinfo) ~= 'table' then return false end
  local limits = { firstname = 64, lastname = 64, birthdate = 32, gender = 16, nationality = 64, phone = 32 }
  for field, value in pairs(charinfo) do
    if not limits[field] or type(value) ~= 'string' or #value > limits[field] or value:find('%z') then return false end
  end
  if requireIdentity then
    for _, field in ipairs({ 'firstname', 'lastname', 'birthdate', 'gender', 'nationality' }) do
      if type(charinfo[field]) ~= 'string' or not charinfo[field]:match('%S') then return false end
    end
  end
  return true
end

function MZPlayerService.setCharinfo(source, charinfo)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, 'player_not_loaded' end
  if not MZPlayerService.validateCharinfo(charinfo, false) then return false, 'invalid_charinfo' end
  local updated = {}
  for field, value in pairs(player.charinfo or {}) do updated[field] = value end
  for field, value in pairs(charinfo) do
    updated[field] = value
  end
  local ok = pcall(MZPlayerRepository.updateCharinfo, player.citizenid, updated)
  if not ok then return false, 'database_error' end
  if MZCache.playersBySource[source] ~= player then return false, 'session_changed' end
  player.charinfo = updated
  MZPlayerService.touchPlayer(source)
  return true, player.charinfo
end

function MZPlayerService.detachForSourceReuse(source, expectedSessionId)
  local player = MZCache.playersBySource[source]
  if not player then return true end
  if not player.session or tonumber(player.session.id) ~= tonumber(expectedSessionId) then
    return false, 'session_changed'
  end
  player.state = player.state or {}
  if MZPlayerStateService.markDisconnecting then MZPlayerStateService.markDisconnecting(player) end
  local ok, detached = pcall(MZPlayerStateService.finalizeUnload, source, expectedSessionId)
  if not ok or detached ~= true then
    player.state.loaded = false
    print(('[mz_core][player_state][source_reuse_retention_failed] source=%s sessionId=%s'):format(tostring(source), tostring(expectedSessionId)))
    return false, 'retention_failed'
  end
  player.state.loaded = false
  if MZCache.playersBySource[source] == player then MZCache.playersBySource[source] = nil end
  if MZCache.playersByCitizenId[player.citizenid] == player then MZCache.playersByCitizenId[player.citizenid] = nil end
  if MZCache.playersByCharacterId[player.characterId] == player then MZCache.playersByCharacterId[player.characterId] = nil end
  return true
end

function MZPlayerService.unloadPlayer(source, reason, statePrepared, preparedFlushOk, preparedFlushResult, expectedPlayer)
  local player = MZCache.playersBySource[source]
  if not player then return end
  if expectedPlayer and player ~= expectedPlayer then return false, { code = 'session_changed' } end
  if MZPlayerStateService.markDisconnecting then MZPlayerStateService.markDisconnecting(player) end

  local flushOk, flushResult = preparedFlushOk, preparedFlushResult
  if statePrepared ~= true then
    flushOk, flushResult = MZPlayerStateService.beginUnload(source, reason or 'unload')
  end

  local sessionId = player.session and player.session.id or nil
  if MZCache.playersBySource[source] ~= player then return false, { code = 'session_changed' } end
  player.state = player.state or {}
  player.state.loaded = false
  local finalized, cleared = pcall(MZPlayerStateService.finalizeUnload, source, sessionId)
  if not finalized or cleared == false then
    print(('[mz_core][player_state][unload_retention_failed] accountId=%s characterId=%s sessionId=%s')
      :format(tostring(player.accountId), tostring(player.characterId), tostring(sessionId)))
    return false, { code = 'retention_failed' }
  end
  local before = {
    state = player.state,
    session = player.session
  }

  player.state.lastSeenAt = os.time()

  if MZPlayerStateSyncService and MZPlayerStateSyncService.clearStateBags then
    MZPlayerStateSyncService.clearStateBags(source)
  end

  local logged, logErr = pcall(MZLogService.createDetailed, 'player', 'unloaded', {
    actor = MZLogService.makeActor('player', player.citizenid, {
      source = source,
    }),
    target = MZLogService.makeTarget('session', sessionId or 'unknown', {
      citizenid = player.citizenid
    }),
    context = {
      source = source,
      reason = reason or ''
    },
    before = before,
    after = {
      state = player.state,
      session = player.session
    },
    meta = {
      event = 'unload_player'
    }
  })
  if not logged then print(('[mz_core][player][unload_log_failed] sessionId=%s error=%s'):format(tostring(sessionId), tostring(logErr))) end

  if MZCache.playersByCitizenId[player.citizenid] == player then MZCache.playersByCitizenId[player.citizenid] = nil end
  if MZCache.playersByCharacterId[player.characterId] == player then MZCache.playersByCharacterId[player.characterId] = nil end
  if MZCache.playersBySource[source] == player then MZCache.playersBySource[source] = nil end
  return flushOk, flushResult
end


function MZPlayerService.getLastPosition(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then return nil end

  local row = MZPlayerRepository.getByCitizenId(player.citizenid)
  if not row then return nil end

  if not row.pos_x or not row.pos_y or not row.pos_z then
    return nil
  end

  if tonumber(row.pos_x) == 0 and tonumber(row.pos_y) == 0 and tonumber(row.pos_z) == 0 then
    return nil
  end

  return normalizePersistedPosition({
    x = tonumber(row.pos_x),
    y = tonumber(row.pos_y),
    z = tonumber(row.pos_z),
    heading = tonumber(row.heading or 0.0)
  })
end

function MZPlayerService.savePosition(source, coords)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, 'player_not_loaded' end
  local normalized = normalizePersistedPosition(coords)
  if not normalized then return false, 'invalid_coords' end

  MZPlayerRepository.updatePosition(player.citizenid, {
    x = normalized.x,
    y = normalized.y,
    z = normalized.z,
    heading = normalized.heading
  })

  return true
end
