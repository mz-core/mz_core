MZPlayerRepository = {}

function MZPlayerRepository.getByCharacterId(characterId)
  return MySQL.single.await('SELECT * FROM mz_players WHERE id = ? LIMIT 1', { characterId })
end

function MZPlayerRepository.getByCitizenId(citizenid)
  return MySQL.single.await('SELECT * FROM mz_players WHERE citizenid = ? LIMIT 1', { citizenid })
end

local function validMetadataVersion(version)
  return type(version) == 'string' and version:match('^%d+$')
    and (#version < 20 or #version == 20 and version <= '18446744073709551614')
    and (version == '0' or version:sub(1, 1) ~= '0')
end

local function nextMetadataVersion(version)
  local prefix, digit = version:match('^(.-)(%d)9*$')
  local nines = #version - #prefix - 1
  return prefix .. tostring(tonumber(digit) + 1) .. ('0'):rep(nines)
end

function MZPlayerRepository.updateMetadata(accountId, characterId, citizenid, version, metadata, onEncoded)
  if not validMetadataVersion(version) then return false, 'invalid_version' end
  if type(json) ~= 'table' or type(json.encode) ~= 'function' then return false, 'error' end
  local encodedOk, encoded = pcall(json.encode, metadata or {})
  if not encodedOk or type(encoded) ~= 'string' then return false, 'error' end
  if type(onEncoded) == 'function' then onEncoded(encoded) end
  local ok, affected = pcall(MySQL.update.await, [[
    UPDATE mz_players SET metadata = ?, metadata_version = metadata_version + 1
    WHERE account_id = ? AND id = ? AND citizenid = ? AND metadata_version = CAST(? AS UNSIGNED)
  ]], { encoded, accountId, characterId, citizenid, version })
  if not ok or affected == nil then return false, 'unknown' end
  if tonumber(affected) == 0 then return false, 'conflict' end
  if tonumber(affected) ~= 1 then return false, 'error' end
  return true, nextMetadataVersion(version)
end

function MZPlayerRepository.recoverPendingMetadata(entry, latestEncoded)
  local attempt = entry.runtime.pendingWrite
  local expected = attempt and attempt.expectedVersion or entry.runtime.metadataVersion
  if not validMetadataVersion(expected) or type(latestEncoded) ~= 'string' then return false, 'invalid_state' end
  if attempt and type(attempt.encoded) ~= 'string' then return false, 'snapshot_unavailable' end
  local nextVersion = nextMetadataVersion(expected)
  if not validMetadataVersion(nextVersion) then return false, 'invalid_version' end
  local maximum = nextVersion
  for _ = 1, entry.recoveryAttempts or 0 do
    if not validMetadataVersion(maximum) then return false, 'invalid_version' end
    maximum = nextMetadataVersion(maximum)
  end
  local function withinRecoveryRange(value)
    local function lessOrEqual(left, right)
      return #left < #right or #left == #right and left <= right
    end
    return lessOrEqual(expected, value) and lessOrEqual(value, maximum)
  end
  local failure = 'unknown'
  local ok, committed = pcall(MySQL.startTransaction, function(query)
    local rows = query([[
      SELECT CAST(metadata_version AS CHAR) AS version,
             BINARY metadata = BINARY ? AS attempted_match,
             BINARY metadata = BINARY ? AS latest_match
      FROM mz_players WHERE account_id = ? AND id = ? AND citizenid = ? AND character_status = 'active'
      LIMIT 1 FOR UPDATE
    ]], { attempt and attempt.encoded or '', latestEncoded, entry.accountId, entry.characterId, entry.citizenid })
    local row = type(rows) == 'table' and rows[1] or nil
    if not row or not validMetadataVersion(row.version) then failure = 'invalid_state'; return false end
    local current = row.version
    local attemptedMatch = tonumber(row.attempted_match) == 1
    local latestMatch = tonumber(row.latest_match) == 1
    if current ~= expected and not (current == nextVersion and attemptedMatch and attempt and attempt.outcome == 'confirmed')
      and not (entry.recoveryAttempted and latestMatch and withinRecoveryRange(current)) then
      failure = 'conflict'; return false
    end
    local updated = query([[
      UPDATE mz_players SET metadata = ?, metadata_version = metadata_version + 1
      WHERE account_id = ? AND id = ? AND citizenid = ? AND metadata_version = CAST(? AS UNSIGNED)
    ]], { latestEncoded, entry.accountId, entry.characterId, entry.citizenid, current })
    local affected = type(updated) == 'table' and tonumber(updated.affectedRows) or tonumber(updated)
    if affected ~= 1 then failure = 'conflict'; return false end
    return true
  end)
  if not ok or committed ~= true then return false, failure end
  return true
end

function MZPlayerRepository.establishMetadataBarrier(accountId, characterId, sessionId)
  local row
  local ok, committed = pcall(MySQL.startTransaction, function(query)
    local updated = query([[
      UPDATE mz_players p INNER JOIN mz_player_sessions s ON s.account_id = p.account_id
      SET p.metadata_version = p.metadata_version + 1
      WHERE p.account_id = ? AND p.id = ? AND p.character_status = 'active'
        AND s.id = ? AND s.is_active = 1 AND s.active_character_id = p.id
        AND p.metadata_version < 18446744073709551615
    ]], { accountId, characterId, sessionId })
    local affected = type(updated) == 'table' and tonumber(updated.affectedRows) or tonumber(updated)
    if affected ~= 1 then return false end
    local rows = query([[
      SELECT p.*, CAST(p.metadata_version AS CHAR) AS metadata_version_exact FROM mz_players p
      WHERE p.account_id = ? AND p.id = ? LIMIT 1 FOR UPDATE
    ]], { accountId, characterId })
    row = type(rows) == 'table' and rows[1] or nil
    if not row or not validMetadataVersion(row.metadata_version_exact) then return false end
    return true
  end)
  if not ok or committed ~= true then return nil, 'barrier_unconfirmed' end
  return row
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

function MZPlayerRepository.updatePhone(citizenid, phone)
  MySQL.update.await('UPDATE mz_players SET phone = ? WHERE citizenid = ?', {
    phone or '',
    citizenid
  })
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
