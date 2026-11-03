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

function MZIdentityRepository.closeSessionsBySource(source, reason)
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
    WHERE source = ? AND is_active = 1
  ]], { reason or 'source_replaced', source }) or 0
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

function MZIdentityRepository.createCharacterDraft(data)
  local characterId = MySQL.insert.await([[
    INSERT INTO mz_players (
      account_id, citizenid, firstname, lastname, birthdate,
      gender, nationality, phone, metadata, character_status
    ) VALUES (?, ?, '', '', '', '', '', '', ?, 'creating')
  ]], {
    data.accountId, data.citizenid,
    MZUtils.jsonEncode(data.metadata or MZPlayerStateNormalizer.buildDefaults())
  })
  return characterId and MZIdentityRepository.getCharacter(characterId) or nil
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
    WHERE id = ? AND account_id = ? AND character_status IN ('creating','active')
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
