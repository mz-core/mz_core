MZIdentityService = {}

local SessionLocks = {}
local AccountMutationLocks = {}
local ActivationLocks = {}
local RequestWindows = {}
local Recovered = false

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function clone(value, depth)
  if type(value) ~= 'table' then return value end
  depth = (depth or 0) + 1
  if depth > 5 then return nil end
  local out = {}
  for key, child in pairs(value) do
    if type(key) == 'string' or type(key) == 'number' then out[key] = clone(child, depth) end
  end
  return out
end

local function databaseBoolean(value)
  return value == true or tonumber(value) == 1
end

local function validSource(source)
  source = tonumber(source)
  return source and source > 0 and source % 1 == 0 and source or nil
end

local function validCharacterId(value)
  value = tonumber(value)
  return value and value > 0 and value % 1 == 0 and value or nil
end

local function validRequestKey(value)
  value = trim(value)
  if #value < 8 or #value > 96 or not value:match('^[%w%._:%-]+$') then return nil end
  return value
end

local function accountIdValue(value)
  value = tonumber(value)
  return value and value > 0 and value % 1 == 0 and value or nil
end

local function audit(action, source, data, outcome)
  if not MZLogService or not MZLogService.createDetailed then return end
  local session = MZCache.sessionsBySource[tonumber(source)]
  pcall(MZLogService.createDetailed, 'identity', action, {
    actor = {
      type = 'account',
      id = session and tostring(session.accountId) or ('source:%s'):format(tostring(source)),
      source = tonumber(source)
    },
    target = data and clone(data, 0) or { type = 'session', id = 'unknown' },
    context = { source = tonumber(source), sessionId = session and session.id or nil },
    meta = { result = outcome or 'success' }
  })
end

local function sessionSnapshot(session)
  if type(session) ~= 'table' then return nil end
  local sessionId = tonumber(session.id or session.sessionId)
  return {
    id = sessionId,
    source = tonumber(session.source),
    sessionId = sessionId,
    accountId = accountIdValue(session.accountId),
    activeCharacterId = validCharacterId(session.activeCharacterId),
    characterId = validCharacterId(session.characterId),
    citizenid = session.citizenid and tostring(session.citizenid) or nil,
    lifecycle = tostring(session.lifecycle or 'CHARACTER_SELECTION'),
    revision = tonumber(session.revision) or 1,
    joinedAt = session.joinedAt,
    lastSeenAt = session.lastSeenAt,
    isActive = session.isActive == true
  }
end

local function lifecycleDebugEnabled()
  return Config and Config.Multichar and Config.Multichar.debugLifecycle == true
end

function MZIdentityService.debugLifecycle(eventName, source, session, requestedCharacterId)
  if not lifecycleDebugEnabled() then return end
  session = type(session) == 'table' and session or MZCache.sessionsBySource[tonumber(source)]
  print(('[MZ_CORE][MULTICHAR][SERVER] %s source=%s accountId=%s characterId=%s sessionId=%s lifecycle=%s isActive=%s activeCharacterId=%s'):format(
    tostring(eventName),
    tostring(source),
    tostring(session and session.accountId or 'nil'),
    tostring(requestedCharacterId or (session and session.characterId) or 'nil'),
    tostring(session and session.id or 'nil'),
    tostring(session and session.lifecycle or 'nil'),
    tostring(session and session.isActive == true),
    tostring(session and session.activeCharacterId or 'nil')
  ))
end

local function sessionFromRow(source, row)
  if type(row) ~= 'table' then return nil end
  return {
    id = tonumber(row.id),
    source = tonumber(source),
    accountId = accountIdValue(row.account_id),
    characterId = validCharacterId(row.character_id),
    activeCharacterId = validCharacterId(row.active_character_id),
    citizenid = row.citizenid and tostring(row.citizenid) or nil,
    lifecycle = tostring(row.lifecycle or 'CHARACTER_SELECTION'),
    revision = tonumber(row.revision) or 1,
    joinedAt = row.joined_at,
    lastSeenAt = row.last_seen_at,
    droppedAt = row.dropped_at,
    disconnectReason = row.disconnect_reason,
    sessionSeconds = tonumber(row.session_seconds) or 0,
    isActive = databaseBoolean(row.is_active)
  }
end

local function characterSnapshot(row)
  if type(row) ~= 'table' then return nil end
  return {
    characterId = validCharacterId(row.id),
    accountId = accountIdValue(row.account_id),
    citizenid = tostring(row.citizenid or ''),
    status = tostring(row.character_status or 'active'),
    charinfo = {
      firstname = tostring(row.firstname or ''),
      lastname = tostring(row.lastname or ''),
      birthdate = tostring(row.birthdate or ''),
      gender = tostring(row.gender or ''),
      nationality = tostring(row.nationality or ''),
      phone = tostring(row.phone or '')
    },
    createdAt = row.created_at,
    updatedAt = row.updated_at
  }
end

local function identifiersForSource(source)
  local identifiers, primary = {}, nil
  for _, raw in ipairs(GetPlayerIdentifiers(source) or {}) do
    local provider, identifier = tostring(raw):match('^([^:]+):(.+)$')
    provider, identifier = trim(provider):lower(), trim(identifier)
    if provider ~= '' and identifier ~= '' and #provider <= 32 and #raw <= 191 then
      local canonical = provider .. ':' .. identifier
      identifiers[#identifiers + 1] = { provider = provider, identifier = canonical }
      if provider == 'license' and not primary then primary = canonical end
    end
  end
  return identifiers, primary
end

local function refreshSession(source, sessionId)
  local row = MZIdentityRepository.getSessionById(sessionId)
  local session = sessionFromRow(source, row)
  if session then MZCache.sessionsBySource[source] = session end
  return session
end

local function checkRateLimit(source)
  local config = Config.Multichar or {}
  local now = type(GetGameTimer) == 'function' and GetGameTimer() or math.floor(os.clock() * 1000)
  local windowMs = tonumber(config.requestWindowMs) or 10000
  local maximum = tonumber(config.maximumRequestsPerWindow) or 12
  local state = RequestWindows[source]
  if not state or now < state.startedAt or now - state.startedAt >= windowMs then
    state = { startedAt = now, count = 0 }
    RequestWindows[source] = state
  end
  state.count = state.count + 1
  return state.count <= maximum
end

local function withAccountMutationLock(accountId, operation)
  local lockKey = tostring(accountId)
  if AccountMutationLocks[lockKey] then return nil, 'account_operation_in_progress' end
  AccountMutationLocks[lockKey] = true
  local results = table.pack(xpcall(operation, debug.traceback))
  AccountMutationLocks[lockKey] = nil
  if results[1] ~= true then
    print(('[mz_core][identity] account mutation failed account=%s error=%s')
      :format(lockKey, tostring(results[2])))
    return nil, 'database_error'
  end
  return table.unpack(results, 2, results.n)
end

local function withActivationLock(source, operation)
  if ActivationLocks[source] then return nil, 'activation_in_progress' end
  ActivationLocks[source] = true
  local results = table.pack(xpcall(operation, debug.traceback))
  ActivationLocks[source] = nil
  if results[1] ~= true then
    print(('[mz_core][identity] activation failed source=%s error=%s')
      :format(tostring(source), tostring(results[2])))
    return nil, 'database_error'
  end
  return table.unpack(results, 2, results.n)
end

function MZIdentityService.recoverStaleSessions()
  if Recovered then return true, 0 end
  local count = MZIdentityRepository.recoverStaleSessions('core_restart_recovery')
  Recovered = true
  if tonumber(count) and tonumber(count) > 0 then
    print(('[mz_core][identity] recovered stale sessions count=%s'):format(tostring(count)))
  end
  return true, tonumber(count) or 0
end

function MZIdentityService.ensureSession(source)
  source = validSource(source)
  if not source then return nil, 'invalid_source' end
  local cached = MZCache.sessionsBySource[source]
  if cached and cached.isActive then
    MZIdentityRepository.touchSession(cached.id, source)
    return cached
  end
  if SessionLocks[source] then return nil, 'session_resolution_in_progress' end
  SessionLocks[source] = true
  local ok, result, err = xpcall(function()
    local identifiers, license = identifiersForSource(source)
    if not license then return nil, 'missing_license' end

    local account, resolvedAccountId
    for _, item in ipairs(identifiers) do
      local candidate = MZIdentityRepository.getAccountByIdentifier(item.provider, item.identifier)
      if candidate then
        local candidateId = accountIdValue(candidate.account_id)
        if resolvedAccountId and resolvedAccountId ~= candidateId then
          return nil, 'identifier_account_conflict'
        end
        account, resolvedAccountId = candidate, candidateId
      end
    end

    if not account then
      local slots = math.max(1, math.min(
        tonumber((Config.Multichar or {}).defaultSlots) or 3,
        tonumber((Config.Multichar or {}).maximumSlots) or 10
      ))
      resolvedAccountId = accountIdValue(MZIdentityRepository.createAccount(slots))
      if not resolvedAccountId then return nil, 'account_create_failed' end
      account = MZIdentityRepository.getAccount(resolvedAccountId)
      if not account then return nil, 'account_create_failed' end
    end

    if tostring(account.status or '') ~= 'active' then return nil, 'account_inactive' end
    for _, item in ipairs(identifiers) do
      MZIdentityRepository.attachIdentifier(resolvedAccountId, item.provider, item.identifier)
      local linked = MZIdentityRepository.getAccountByIdentifier(item.provider, item.identifier)
      if not linked or accountIdValue(linked.account_id) ~= resolvedAccountId then
        return nil, 'identifier_account_conflict'
      end
    end

    -- Consumers with source-keyed runtime state must clear it before this
    -- source is bound to a new session.
    TriggerEvent('mz_core:server:identitySessionClosed', source, nil, 'source_reused')
    MZIdentityRepository.closeSessionsBySource(source, 'source_reused')
    local row = MZIdentityRepository.createSession({
      accountId = resolvedAccountId,
      source = source
    })
    local session = sessionFromRow(source, row)
    if not session then return nil, 'session_create_failed' end
    MZCache.sessionsBySource[source] = session
    MZIdentityService.debugLifecycle('accountResolved', source, session)
    MZIdentityService.debugLifecycle('sessionCreated', source, session)
    audit('account_resolved', source, { type = 'account', id = tostring(resolvedAccountId) }, 'success')
    return session
  end, debug.traceback)
  SessionLocks[source] = nil
  if not ok then
    print(('[mz_core][identity] session resolution failed source=%s error=%s'):format(source, tostring(result)))
    return nil, 'database_error'
  end
  return result, err
end

function MZIdentityService.getSession(source)
  return MZCache.sessionsBySource[tonumber(source)]
end

function MZIdentityService.getSessionSnapshot(source)
  return sessionSnapshot(MZIdentityService.getSession(source))
end

function MZIdentityService.getAccountId(source)
  local session = MZIdentityService.getSession(source)
  return session and session.isActive and session.accountId or nil
end

function MZIdentityService.getActiveCharacterId(source)
  local session = MZIdentityService.getSession(source)
  return session and session.isActive and session.activeCharacterId or nil
end

function MZIdentityService.getCharacterSnapshot(characterId)
  characterId = validCharacterId(characterId)
  if not characterId then return nil end
  return characterSnapshot(MZIdentityRepository.getCharacter(characterId))
end

function MZIdentityService.getCharactersForAccount(accountId)
  accountId = accountIdValue(accountId)
  if not accountId then return {} end
  local result = {}
  for _, row in ipairs(MZIdentityRepository.getCharactersForAccount(accountId, false)) do
    result[#result + 1] = characterSnapshot(row)
  end
  return result
end

function MZIdentityService.getRosterForSource(source)
  source = validSource(source)
  if not source or not checkRateLimit(source) then return nil, 'rate_limited' end
  local session, err = MZIdentityService.ensureSession(source)
  if not session then return nil, err end
  local account = MZIdentityRepository.getAccount(session.accountId)
  local characters = MZIdentityService.getCharactersForAccount(session.accountId)
  audit('character_list_requested', source, { type = 'account', id = tostring(session.accountId) }, 'success')
  return {
    accountId = session.accountId,
    sessionId = session.id,
    lifecycle = session.lifecycle,
    slots = tonumber(account and account.character_slots) or 0,
    usedSlots = #MZIdentityRepository.getCharactersForAccount(session.accountId, true),
    characters = characters
  }
end

function MZIdentityService.createCharacterDraft(source, requestKey)
  source = validSource(source)
  requestKey = validRequestKey(requestKey)
  if not source or not requestKey then return nil, 'invalid_request' end
  if not checkRateLimit(source) then return nil, 'rate_limited' end
  local session, sessionErr = MZIdentityService.ensureSession(source)
  if not session then return nil, sessionErr end
  if session.activeCharacterId then return nil, 'character_already_active' end

  return withAccountMutationLock(session.accountId, function()
    local current = MZIdentityService.getSession(source)
    if not current or current.id ~= session.id or not current.isActive or current.activeCharacterId then
      return nil, 'session_changed'
    end

    local existing = MZIdentityRepository.getCharacterRequest(session.accountId, requestKey, 'create')
    if existing and existing.character_id then
      local row = MZIdentityRepository.getCharacterForAccount(session.accountId, existing.character_id)
      if row then return characterSnapshot(row), 'idempotent_replay' end
      return nil, 'request_already_consumed'
    end
    if current.lifecycle == 'CHARACTER_CREATING' and current.characterId then
      return nil, 'character_creation_in_progress'
    end

    local account = MZIdentityRepository.getAccount(session.accountId)
    local slots = math.min(
      tonumber(account and account.character_slots) or 0,
      tonumber((Config.Multichar or {}).maximumSlots) or 10
    )
    local used = #MZIdentityRepository.getCharactersForAccount(session.accountId, true)
    if used >= slots then return nil, 'character_slots_exhausted' end

    local citizenid
    repeat citizenid = MZUtils.generateCitizenId() until not MZPlayerRepository.getByCitizenId(citizenid)
    local row = MZIdentityRepository.createCharacterDraft({
      accountId = session.accountId,
      citizenid = citizenid,
      metadata = MZPlayerStateNormalizer.buildDefaults()
    })
    if not row then return nil, 'character_create_failed' end
    MZIdentityRepository.recordCharacterRequest(session.accountId, requestKey, 'create', row.id)
    if MZIdentityRepository.setPendingCharacter(session.id, session.accountId, row.id, row.citizenid) ~= 1 then
      MZIdentityRepository.archiveDraft(session.accountId, row.id)
      return nil, 'session_changed'
    end
    refreshSession(source, session.id)
    audit('character_creation_started', source, { type = 'character', id = tostring(row.id) }, 'success')
    return characterSnapshot(row)
  end)
end

function MZIdentityService.getPendingCharacterSnapshot(source)
  local session = MZIdentityService.getSession(source)
  if not session or session.lifecycle ~= 'CHARACTER_CREATING' or session.activeCharacterId then return nil end
  local row = MZIdentityRepository.getCharacterForAccount(session.accountId, session.characterId)
  return characterSnapshot(row)
end

function MZIdentityService.activateCharacter(source, characterId, requestKey)
  source, characterId = validSource(source), validCharacterId(characterId)
  requestKey = validRequestKey(requestKey)
  if not source or not characterId or not requestKey then return nil, 'invalid_request' end
  if not checkRateLimit(source) then return nil, 'rate_limited' end
  return withActivationLock(source, function()
  local session, sessionErr = MZIdentityService.ensureSession(source)
  if not session then return nil, sessionErr end
  MZIdentityService.debugLifecycle('activateCharacterStart', source, session, characterId)
  if session.activeCharacterId then
    if session.activeCharacterId == characterId then
      MZIdentityService.debugLifecycle('activateCharacterSuccess', source, session, characterId)
      return MZPlayerService.getPlayerSnapshot(source), 'idempotent_replay'
    end
    return nil, 'hot_switch_not_safe'
  end
  local row = MZIdentityRepository.getCharacterForAccount(session.accountId, characterId)
  if not row or tostring(row.character_status) ~= 'active' then
    audit('character_activation_rejected', source, { type = 'character', id = tostring(characterId) }, 'ownership_rejected')
    return nil, 'character_not_owned'
  end

  local bindOk, affected = pcall(MZIdentityRepository.bindCharacter,
    session.id, session.accountId, characterId, row.citizenid)
  if not bindOk then
    audit('character_activation_rejected', source, { type = 'character', id = tostring(characterId) }, 'duplicate_session')
    return nil, 'character_active_elsewhere'
  end
  if tonumber(affected) ~= 1 then return nil, 'session_changed' end
  session = refreshSession(source, session.id)
  MZCache.activeSourcesByCharacterId[characterId] = source
  audit('character_activation_started', source, { type = 'character', id = tostring(characterId) }, 'success')

  local player, loadErr = MZPlayerService.loadCharacter(source, row, session)
  if not player then
    MZCache.activeSourcesByCharacterId[characterId] = nil
    MZIdentityRepository.unbindCharacter(session.id, 'CHARACTER_SELECTION')
    refreshSession(source, session.id)
    audit('character_activation_failed', source, { type = 'character', id = tostring(characterId) }, loadErr or 'load_failed')
    return nil, loadErr or 'load_failed'
  end

  local markOk, marked = pcall(MZIdentityRepository.markCharacterActive, session.id)
  if not markOk or tonumber(marked) ~= 1 then
    MZCache.activeSourcesByCharacterId[characterId] = nil
    pcall(MZPlayerService.unloadPlayer, source, 'activation_commit_failed')
    pcall(MZIdentityRepository.unbindCharacter, session.id, 'CHARACTER_SELECTION')
    MZCache.playersByCitizenId[row.citizenid] = nil
    MZCache.playersByCharacterId[characterId] = nil
    MZCache.playersBySource[source] = nil
    audit('character_activation_failed', source, { type = 'character', id = tostring(characterId) }, 'activation_commit_failed')
    return nil, 'activation_commit_failed'
  end
  session = refreshSession(source, session.id)
  player.session = sessionSnapshot(session)
  MZIdentityService.debugLifecycle('activateCharacterSuccess', source, session, characterId)
  local requestRecorded, requestRecordErr = pcall(
    MZIdentityRepository.recordCharacterRequest,
    session.accountId, requestKey, 'activate', characterId
  )
  if not requestRecorded then
    print(('[mz_core][identity] activation correlation persistence failed session=%s error=%s')
      :format(tostring(session.id), tostring(requestRecordErr)))
  end
  local published, publishErr = MZPlayerService.publishPlayerLoaded(source, player)
  if not published then
    MZCache.activeSourcesByCharacterId[characterId] = nil
    if MZPlayerStateSyncService and MZPlayerStateSyncService.clearStateBags then
      pcall(MZPlayerStateSyncService.clearStateBags, source)
    end
    MZPlayerStateService.finalizeUnload(source)
    MZCache.playersByCitizenId[row.citizenid] = nil
    MZCache.playersByCharacterId[characterId] = nil
    MZCache.playersBySource[source] = nil
    pcall(MZIdentityRepository.unbindCharacter, session.id, 'CHARACTER_SELECTION')
    refreshSession(source, session.id)
    audit('character_activation_failed', source, { type = 'character', id = tostring(characterId) },
      publishErr or 'player_loaded_publish_failed')
    return nil, publishErr or 'player_loaded_publish_failed'
  end
  audit('character_activation_succeeded', source, { type = 'character', id = tostring(characterId) }, 'success')
  return MZPlayerService.getPlayerSnapshot(source)
  end)
end

function MZIdentityService.finalizePendingCharacter(source, charinfo, requestKey)
  source, requestKey = validSource(source), validRequestKey(requestKey)
  if not source or not requestKey or type(charinfo) ~= 'table' then return nil, 'invalid_request' end
  local session = MZIdentityService.getSession(source)
  if not session or session.lifecycle ~= 'CHARACTER_CREATING' or session.activeCharacterId then
    return nil, 'character_creation_not_active'
  end
  local row = MZIdentityRepository.getCharacterForAccount(session.accountId, session.characterId)
  if not row or (tostring(row.character_status) ~= 'creating' and tostring(row.character_status) ~= 'active') then
    return nil, 'draft_not_found'
  end
  local finalMetadata = MZPlayerStateNormalizer.buildDefaults()
  if tostring(row.character_status) == 'creating' then
    if MZIdentityRepository.finalizeCharacter(session.accountId, row.id, charinfo, finalMetadata) ~= 1 then
      return nil, 'character_finalize_failed'
    end
  end
  local player, activationErr = MZIdentityService.activateCharacter(source, row.id, requestKey)
  if player then return player, activationErr end

  -- Finalization is durable before runtime activation. Re-establish the pending
  -- link after any activation failure so creator retry/cancel remains possible.
  local recoverySession = MZIdentityService.getSession(source)
  if not recoverySession or not recoverySession.isActive then
    recoverySession = MZIdentityService.ensureSession(source)
  end
  if recoverySession and recoverySession.accountId == session.accountId
    and not recoverySession.activeCharacterId then
    MZIdentityRepository.setPendingCharacter(
      recoverySession.id, recoverySession.accountId, row.id, row.citizenid
    )
    refreshSession(source, recoverySession.id)
  end
  return nil, activationErr
end

function MZIdentityService.cancelPendingCharacter(source)
  source = validSource(source)
  local session = source and MZIdentityService.getSession(source) or nil
  if not session or session.lifecycle ~= 'CHARACTER_CREATING' or session.activeCharacterId then
    return false, 'character_creation_not_active'
  end
  MZIdentityRepository.archiveDraft(session.accountId, session.characterId)
  MZIdentityRepository.unbindCharacter(session.id, 'CHARACTER_SELECTION')
  refreshSession(source, session.id)
  audit('character_creation_cancelled', source, { type = 'character', id = tostring(session.characterId) }, 'success')
  TriggerClientEvent('mz_core:client:characterSelectionRequired', source)
  return true
end

function MZIdentityService.closeSession(source, reason)
  source = validSource(source)
  if not source then return false end
  local session = MZCache.sessionsBySource[source]
  if session then
    MZIdentityRepository.closeSession(session.id, reason or 'disconnected')
    if session.activeCharacterId then MZCache.activeSourcesByCharacterId[session.activeCharacterId] = nil end
    audit('session_closed', source, { type = 'session', id = tostring(session.id) }, 'success')
    TriggerEvent(
      'mz_core:server:identitySessionClosed',
      source,
      session.id,
      reason or 'disconnected'
    )
  end
  MZCache.sessionsBySource[source] = nil
  ActivationLocks[source] = nil
  RequestWindows[source] = nil
  return true
end

function MZIdentityService.resolvePlayerIdentity(source)
  source = validSource(source)
  local session = source and MZIdentityService.getSession(source) or nil
  if not session or not session.isActive then return { ok = false, error = 'session_not_found' } end
  if not session.activeCharacterId then
    return {
      ok = false,
      error = 'character_not_active',
      source = source,
      accountId = session.accountId,
      sessionId = session.id,
      active = false
    }
  end
  local player = MZPlayerService.getPlayerSnapshot(source)
  if not player then return { ok = false, error = 'player_not_loaded' } end
  return {
    ok = true,
    source = source,
    accountId = session.accountId,
    characterId = session.activeCharacterId,
    citizenid = player.citizenid,
    sessionId = session.id,
    active = session.lifecycle == 'CHARACTER_ACTIVE',
    firstname = player.charinfo and player.charinfo.firstname or '',
    lastname = player.charinfo and player.charinfo.lastname or '',
    phone = player.charinfo and player.charinfo.phone or ''
  }
end
