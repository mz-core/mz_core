MZPlayerRepository = {}

function MZPlayerRepository.getByCharacterId(characterId)
  return MySQL.single.await('SELECT * FROM mz_players WHERE id = ? LIMIT 1', { characterId })
end

function MZPlayerRepository.getByCitizenId(citizenid)
  return MySQL.single.await('SELECT * FROM mz_players WHERE citizenid = ? LIMIT 1', { citizenid })
end

function MZPlayerRepository.updateMetadata(citizenid, metadata)
  local affected = MySQL.update.await('UPDATE mz_players SET metadata = ? WHERE citizenid = ?', {
    MZUtils.jsonEncode(metadata or {}),
    citizenid
  })
  return affected ~= nil
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
