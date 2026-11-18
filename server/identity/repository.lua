MZIdentityRepository = {}

function MZIdentityRepository.getAccountByIdentifier(provider, identifier)
  return MySQL.single.await([[
    SELECT a.account_id, a.status, a.character_slots
    FROM mz_account_identifiers i
    INNER JOIN mz_accounts a ON a.account_id = i.account_id
    WHERE i.provider = ? AND i.identifier = ?
    LIMIT 1
  ]], { provider, identifier })
end

function MZIdentityRepository.hasOtherLicense(accountId, identifier)
  local count = MySQL.scalar.await([[
    SELECT COUNT(*) FROM mz_account_identifiers
    WHERE account_id = ? AND provider = 'license' AND identifier <> ?
  ]], { accountId, identifier })
  assert(tonumber(count), 'license lookup failed')
  return tonumber(count) > 0
end

function MZIdentityRepository.createAccount(slots)
  return MySQL.insert.await([[
    INSERT INTO mz_accounts (status, character_slots) VALUES ('active', ?)
  ]], { slots })
end

function MZIdentityRepository.attachIdentifier(accountId, provider, identifier)
  return MySQL.insert.await([[
    INSERT INTO mz_account_identifiers (account_id, provider, identifier)
    VALUES (?, ?, ?)
    ON DUPLICATE KEY UPDATE account_id = account_id
  ]], { accountId, provider, identifier })
end

function MZIdentityRepository.getAccount(accountId)
  return MySQL.single.await([[
    SELECT account_id, status, character_slots, created_at, updated_at
    FROM mz_accounts WHERE account_id = ? LIMIT 1
  ]], { accountId })
end

function MZIdentityRepository.createSession(data)
  local sessionId = MySQL.insert.await([[
    INSERT INTO mz_player_sessions (
      account_id, character_id, active_character_id, citizenid,
      source, lifecycle, revision, disconnect_reason, is_active
    ) VALUES (?, NULL, NULL, NULL, ?, 'CHARACTER_SELECTION', 1, '', 1)
  ]], { data.accountId, data.source })
  return sessionId and MZIdentityRepository.getSessionById(sessionId) or nil
end

function MZIdentityRepository.getSessionById(sessionId)
  return MySQL.single.await([[
    SELECT * FROM mz_player_sessions WHERE id = ? LIMIT 1
  ]], { sessionId })
end

function MZIdentityRepository.getSessionIdWatermark()
  local value = MySQL.scalar.await('SELECT COALESCE(MAX(id), 0) FROM mz_player_sessions')
  assert(tonumber(value), 'session watermark unavailable')
  return tonumber(value)
end

function MZIdentityRepository.closeSessionsBySource(source, reason, watermark)
  assert(type(watermark) == 'number' and watermark >= 0 and watermark % 1 == 0, 'invalid session watermark')
  local affected = MySQL.update.await([[
    UPDATE mz_player_sessions
    SET dropped_at = CURRENT_TIMESTAMP,
        last_seen_at = CURRENT_TIMESTAMP,
        disconnect_reason = ?,
        session_seconds = TIMESTAMPDIFF(SECOND, joined_at, CURRENT_TIMESTAMP),
        is_active = 0,
        active_character_id = NULL,
        lifecycle = 'DISCONNECTED',
        revision = revision + 1
    WHERE source = ? AND is_active = 1 AND id <= ?
  ]], { reason or 'source_replaced', source, watermark })
  assert(tonumber(affected), 'session cleanup result unavailable')
  return tonumber(affected)
end

function MZIdentityRepository.closeSession(sessionId, reason)
  return MySQL.update.await([[
    UPDATE mz_player_sessions
    SET dropped_at = CURRENT_TIMESTAMP,
        last_seen_at = CURRENT_TIMESTAMP,
        disconnect_reason = ?,
        session_seconds = TIMESTAMPDIFF(SECOND, joined_at, CURRENT_TIMESTAMP),
        is_active = 0,
        active_character_id = NULL,
        lifecycle = 'DISCONNECTED',
        revision = revision + 1
    WHERE id = ? AND is_active = 1
  ]], { reason or '', sessionId }) or 0
end

function MZIdentityRepository.touchSession(sessionId, source)
  return MySQL.update.await([[
    UPDATE mz_player_sessions
    SET source = ?, last_seen_at = CURRENT_TIMESTAMP
    WHERE id = ? AND is_active = 1
  ]], { source, sessionId }) or 0
end

function MZIdentityRepository.setSessionLifecycle(sessionId, lifecycle)
  return MySQL.update.await([[
    UPDATE mz_player_sessions
    SET lifecycle = ?, revision = revision + 1, last_seen_at = CURRENT_TIMESTAMP
    WHERE id = ? AND is_active = 1
  ]], { lifecycle, sessionId }) or 0
end

function MZIdentityRepository.setPendingCharacter(sessionId, accountId, characterId, citizenid)
  return MySQL.update.await([[
    UPDATE mz_player_sessions
    SET character_id = ?, citizenid = ?, lifecycle = 'CHARACTER_CREATING',
        revision = revision + 1, last_seen_at = CURRENT_TIMESTAMP
    WHERE id = ? AND account_id = ? AND is_active = 1
      AND active_character_id IS NULL
  ]], { characterId, citizenid, sessionId, accountId }) or 0
end

function MZIdentityRepository.bindCharacter(sessionId, accountId, characterId, citizenid)
  return MySQL.update.await([[
    UPDATE mz_player_sessions
    SET character_id = ?, active_character_id = ?, citizenid = ?,
        lifecycle = 'CHARACTER_ACTIVATING', revision = revision + 1,
        last_seen_at = CURRENT_TIMESTAMP
    WHERE id = ? AND account_id = ? AND is_active = 1
      AND (active_character_id IS NULL OR active_character_id = ?)
  ]], { characterId, characterId, citizenid, sessionId, accountId, characterId }) or 0
end

function MZIdentityRepository.markCharacterActive(sessionId)
  return MySQL.update.await([[
    UPDATE mz_player_sessions
    SET lifecycle = 'CHARACTER_ACTIVE', revision = revision + 1,
        last_seen_at = CURRENT_TIMESTAMP
    WHERE id = ? AND is_active = 1 AND active_character_id IS NOT NULL
  ]], { sessionId }) or 0
end

function MZIdentityRepository.unbindCharacter(sessionId, lifecycle)
  return MySQL.update.await([[
    UPDATE mz_player_sessions
    SET active_character_id = NULL, character_id = NULL, citizenid = NULL,
        lifecycle = ?, revision = revision + 1,
        last_seen_at = CURRENT_TIMESTAMP
    WHERE id = ? AND is_active = 1
  ]], { lifecycle or 'CHARACTER_SELECTION', sessionId }) or 0
end

function MZIdentityRepository.recoverStaleSessions(reason)
  return MySQL.update.await([[
    UPDATE mz_player_sessions
    SET dropped_at = CURRENT_TIMESTAMP,
        last_seen_at = CURRENT_TIMESTAMP,
        disconnect_reason = ?,
        session_seconds = TIMESTAMPDIFF(SECOND, joined_at, CURRENT_TIMESTAMP),
        is_active = 0,
        active_character_id = NULL,
        lifecycle = 'DISCONNECTED',
        revision = revision + 1
    WHERE is_active = 1
  ]], { reason or 'core_restart_recovery' }) or 0
end

function MZIdentityRepository.getCharactersForAccount(accountId, includeCreating)
  local statuses = includeCreating and "('active','creating')" or "('active')"
  return MySQL.query.await(([[
    SELECT id, account_id, citizenid, firstname, lastname, birthdate, gender,
           nationality, phone, metadata, character_status, archived_at,
           pos_x, pos_y, pos_z, heading, created_at, updated_at
    FROM mz_players
    WHERE account_id = ? AND character_status IN %s
    ORDER BY id ASC
  ]]):format(statuses), { accountId }) or {}
end

function MZIdentityRepository.getCharacter(characterId)
  return MySQL.single.await([[
    SELECT * FROM mz_players WHERE id = ? LIMIT 1
  ]], { characterId })
end

function MZIdentityRepository.getCharacterForAccount(accountId, characterId)
  return MySQL.single.await([[
    SELECT * FROM mz_players
    WHERE id = ? AND account_id = ? AND character_status IN ('active','creating')
    LIMIT 1
  ]], { characterId, accountId })
end

function MZIdentityRepository.searchCharacters(search, limit, offset)
  search = tostring(search or ''):gsub('%c', ' '):gsub('[%%_]', ''):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if #search < 2 then return {}, 0 end
  limit = math.max(1, math.min(50, math.floor(tonumber(limit) or 25)))
  offset = math.max(0, math.floor(tonumber(offset) or 0))
  local like = '%' .. search .. '%'
  local where = [[
    character_status = 'active'
    AND (
      citizenid LIKE ?
      OR firstname LIKE ?
      OR lastname LIKE ?
      OR CONCAT_WS(' ', firstname, lastname) LIKE ?
    )
  ]]
  local parameters = { like, like, like, like }
  local total = tonumber(MySQL.scalar.await(
    'SELECT COUNT(*) FROM mz_players WHERE ' .. where,
    parameters
  )) or 0
  local queryParameters = { like, like, like, like, limit, offset }
  local rows = MySQL.query.await([[
    SELECT id, account_id, citizenid, firstname, lastname, character_status
    FROM mz_players
    WHERE ]] .. where .. [[
    ORDER BY firstname ASC, lastname ASC, id ASC
    LIMIT ? OFFSET ?
  ]], queryParameters) or {}
  return rows, total
end

function MZIdentityRepository.claimCharacterDraft(data)
  local result, failure
  local function affected(value)
    if type(value) == 'number' then return value end
    return type(value) == 'table' and tonumber(value.affectedRows or value.changedRows) or 0
  end
  local ok, committed = pcall(MySQL.startTransaction, function(query)
    local account = query('SELECT character_slots FROM mz_accounts WHERE account_id = ? FOR UPDATE', { data.accountId })
    if not account or not account[1] then failure = 'account_unavailable'; return false end
    local sessions = query([[
      SELECT id, character_id, lifecycle FROM mz_player_sessions
      WHERE account_id = ? AND is_active = 1 FOR UPDATE
    ]], { data.accountId })
    if type(sessions) ~= 'table' then failure = 'database_error'; return false end
    local current
    for _, session in ipairs(sessions) do
      if tonumber(session.id) == data.sessionId then current = session end
    end
    if not current then failure = 'session_changed'; return false end
    if current.lifecycle ~= 'CHARACTER_SELECTION' and current.lifecycle ~= 'CHARACTER_CREATING' then
      failure = 'session_changed'; return false
    end

    local row, replay
    if data.requestKey then
      local requests = query([[
        SELECT character_id FROM mz_character_requests
        WHERE account_id = ? AND request_key = ? AND operation = 'create' LIMIT 1
      ]], { data.accountId, data.requestKey })
      if type(requests) ~= 'table' then failure = 'database_error'; return false end
      if requests[1] then
        local rows = query('SELECT * FROM mz_players WHERE account_id = ? AND id = ? LIMIT 1 FOR UPDATE',
          { data.accountId, requests[1].character_id })
        row = type(rows) == 'table' and rows[1]
        if not row or row.character_status ~= 'creating' then failure = 'request_already_consumed'; return false end
        replay = true
      end
    end
    if data.requestKey and not replay and current.lifecycle == 'CHARACTER_CREATING' then
      failure = 'character_creation_in_progress'; return false
    end
    if not row then
      local rows = query([[
        SELECT * FROM mz_players WHERE account_id = ? AND character_status = 'creating' ORDER BY id ASC FOR UPDATE
      ]], { data.accountId })
      if type(rows) ~= 'table' then failure = 'database_error'; return false end
      for _, candidate in ipairs(rows) do
        local occupied = false
        for _, session in ipairs(sessions) do
          if tonumber(session.id) ~= data.sessionId and tonumber(session.character_id) == tonumber(candidate.id) then
            occupied = true; break
          end
        end
        if not occupied and (not current.character_id or tonumber(current.character_id) == tonumber(candidate.id)) then
          row = candidate; break
        end
      end
      if not row and #rows > 0 then
        if data.requestKey then failure = 'character_creation_in_progress'; return false end
        return true
      end
    end
    if row then
      for _, session in ipairs(sessions) do
        if tonumber(session.id) ~= data.sessionId and tonumber(session.character_id) == tonumber(row.id) then
          failure = 'character_creation_in_progress'; return false
        end
      end
      if current.character_id and tonumber(current.character_id) ~= tonumber(row.id) then
        failure = 'character_creation_in_progress'; return false
      end
    elseif data.requestKey then
      local count = query([[
        SELECT COUNT(*) AS used FROM mz_players WHERE account_id = ? AND character_status IN ('active','creating')
      ]], { data.accountId })
      if not count or not count[1] or not tonumber(count[1].used) then failure = 'database_error'; return false end
      if tonumber(count[1].used) >= math.min(tonumber(account[1].character_slots) or 0, data.maximumSlots) then
        failure = 'character_slots_exhausted'; return false
      end
      local inserted = query([[
        INSERT INTO mz_players (account_id, citizenid, firstname, lastname, birthdate, gender, nationality, phone, metadata, character_status)
        VALUES (?, ?, '', '', '', '', '', '', ?, 'creating')
      ]], { data.accountId, data.citizenid, data.metadata })
      if affected(inserted) ~= 1 then failure = 'character_create_failed'; return false end
      local rows = query('SELECT * FROM mz_players WHERE account_id = ? AND citizenid = ? LIMIT 1',
        { data.accountId, data.citizenid })
      row = type(rows) == 'table' and rows[1]
      if not row then failure = 'character_create_failed'; return false end
    else
      return true
    end
    if data.requestKey and not replay then
      local inserted = query([[
        INSERT INTO mz_character_requests (account_id, request_key, operation, character_id, status)
        VALUES (?, ?, 'create', ?, 'completed')
      ]], { data.accountId, data.requestKey, row.id })
      if affected(inserted) ~= 1 then failure = 'database_error'; return false end
    end
    if current.lifecycle ~= 'CHARACTER_CREATING' or tonumber(current.character_id) ~= tonumber(row.id) then
      local bound = query([[
        UPDATE mz_player_sessions SET character_id = ?, citizenid = ?, lifecycle = 'CHARACTER_CREATING',
          revision = revision + 1, last_seen_at = CURRENT_TIMESTAMP
        WHERE id = ? AND account_id = ? AND is_active = 1 AND active_character_id IS NULL
      ]], { row.id, row.citizenid, data.sessionId, data.accountId })
      if affected(bound) ~= 1 then failure = 'session_changed'; return false end
    end
    result = { row = row, replay = replay }
    return true
  end)
  if not ok or committed ~= true then return nil, failure or 'database_error' end
  return result
end

function MZIdentityRepository.finalizeCharacter(accountId, characterId, charinfo, metadata)
  return MySQL.update.await([[
    UPDATE mz_players
    SET firstname = ?, lastname = ?, birthdate = ?, gender = ?,
        nationality = ?, phone = ?, metadata = ?, character_status = 'active',
        archived_at = NULL
    WHERE id = ? AND account_id = ? AND character_status = 'creating'
  ]], {
    charinfo.firstname or '', charinfo.lastname or '', charinfo.birthdate or '',
    charinfo.gender or '', charinfo.nationality or '', charinfo.phone or '',
    MZUtils.jsonEncode(metadata or MZPlayerStateNormalizer.buildDefaults()),
    characterId, accountId
  }) or 0
end

function MZIdentityRepository.archiveDraft(accountId, characterId)
  return MySQL.update.await([[
    UPDATE mz_players
    SET character_status = 'archived', archived_at = CURRENT_TIMESTAMP
    WHERE id = ? AND account_id = ? AND character_status = 'creating'
  ]], { characterId, accountId }) or 0
end

function MZIdentityRepository.getCharacterRequest(accountId, requestKey, operation)
  return MySQL.single.await([[
    SELECT * FROM mz_character_requests
    WHERE account_id = ? AND request_key = ? AND operation = ? LIMIT 1
  ]], { accountId, requestKey, operation })
end

function MZIdentityRepository.recordCharacterRequest(accountId, requestKey, operation, characterId)
  return MySQL.insert.await([[
    INSERT INTO mz_character_requests (
      account_id, request_key, operation, character_id, status
    ) VALUES (?, ?, ?, ?, 'completed')
    ON DUPLICATE KEY UPDATE character_id = character_id
  ]], { accountId, requestKey, operation, characterId })
end
