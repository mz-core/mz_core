MZPlayerRepository = {}

function MZPlayerRepository.getByLicense(license)
  return MySQL.single.await('SELECT * FROM mz_players WHERE license = ? LIMIT 1', { license })
end

function MZPlayerRepository.getByCitizenId(citizenid)
  return MySQL.single.await('SELECT * FROM mz_players WHERE citizenid = ? LIMIT 1', { citizenid })
end

function MZPlayerRepository.create(data)
  MySQL.insert.await([[
    INSERT INTO mz_players (
      license, citizenid, firstname, lastname, birthdate, gender, nationality, phone, metadata
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    data.license,
    data.citizenid,
    data.firstname or '',
    data.lastname or '',
    data.birthdate or '',
    data.gender or '',
    data.nationality or '',
    data.phone or '',
    MZUtils.jsonEncode(data.metadata or Config.Player.defaultMetadata or {})
  })

  return MZPlayerRepository.getByCitizenId(data.citizenid)
end

function MZPlayerRepository.updateMetadata(citizenid, metadata)
  MySQL.update.await('UPDATE mz_players SET metadata = ? WHERE citizenid = ?', {
    MZUtils.jsonEncode(metadata or {}),
    citizenid
  })
end

function MZPlayerRepository.updateCharinfo(citizenid, charinfo)
  MySQL.update.await([[
    UPDATE mz_players
    SET firstname = ?, lastname = ?, birthdate = ?, gender = ?, nationality = ?, phone = ?
    WHERE citizenid = ?
  ]], {
    charinfo.firstname or '',
    charinfo.lastname or '',
    charinfo.birthdate or '',
    charinfo.gender or '',
    charinfo.nationality or '',
    charinfo.phone or '',
    citizenid
  })
end

function MZPlayerRepository.ensureAccount(citizenid)
  MySQL.insert.await([[
    INSERT INTO mz_player_accounts (citizenid, wallet, bank, dirty)
    VALUES (?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE citizenid = citizenid
  ]], {
    citizenid,
    Config.StarterMoney.wallet,
    Config.StarterMoney.bank,
    Config.StarterMoney.dirty
  })
end

function MZPlayerRepository.getAccount(citizenid)
  return MySQL.single.await('SELECT * FROM mz_player_accounts WHERE citizenid = ? LIMIT 1', { citizenid })
end


function MZPlayerRepository.createSession(data)
  local sessionId = MySQL.insert.await([[
    INSERT INTO mz_player_sessions (
      citizenid, license, source, disconnect_reason, is_active
    ) VALUES (?, ?, ?, ?, 1)
  ]], {
    data.citizenid,
    data.license,
    data.source or 0,
    data.disconnectReason or ''
  })

  return sessionId and MZPlayerRepository.getSessionById(sessionId) or nil
end

function MZPlayerRepository.getSessionById(sessionId)
  return MySQL.single.await('SELECT * FROM mz_player_sessions WHERE id = ? LIMIT 1', { sessionId })
end

function MZPlayerRepository.getActiveSession(citizenid)
  return MySQL.single.await([[SELECT * FROM mz_player_sessions WHERE citizenid = ? AND is_active = 1 ORDER BY id DESC LIMIT 1]], { citizenid })
end

function MZPlayerRepository.touchSession(sessionId, source)
  if not sessionId then return false end

  MySQL.update.await([[
    UPDATE mz_player_sessions
    SET source = ?, last_seen_at = CURRENT_TIMESTAMP
    WHERE id = ?
  ]], {
    source or 0,
    sessionId
  })

  return true
end

function MZPlayerRepository.closeSession(sessionId, reason)
  if not sessionId then return false end

  MySQL.update.await([[
    UPDATE mz_player_sessions
    SET
      dropped_at = CURRENT_TIMESTAMP,
      last_seen_at = CURRENT_TIMESTAMP,
      disconnect_reason = ?,
      session_seconds = TIMESTAMPDIFF(SECOND, joined_at, CURRENT_TIMESTAMP),
      is_active = 0
    WHERE id = ?
  ]], {
    reason or '',
    sessionId
  })

  return true
end

function MZPlayerRepository.updatePosition(citizenid, coords)
  MySQL.update.await([[
    UPDATE mz_players
    SET pos_x = ?, pos_y = ?, pos_z = ?, heading = ?
    WHERE citizenid = ?
  ]], {
    coords.x or 0.0,
    coords.y or 0.0,
    coords.z or 0.0,
    coords.heading or 0.0,
    citizenid
  })
end