MZWorldDropRepository = {}

local function decodeDropRow(row)
  if not row then
    return nil
  end

  row.id = tonumber(row.id)
  row.x = tonumber(row.x) or 0
  row.y = tonumber(row.y) or 0
  row.z = tonumber(row.z) or 0
  row.metadata_json = MZUtils.jsonDecode(row.metadata_json or '{}') or {}

  return row
end

local function decodeDropRows(rows)
  local out = {}
  for _, row in ipairs(rows or {}) do
    out[#out + 1] = decodeDropRow(row)
  end
  return out
end

function MZWorldDropRepository.create(data)
  return MySQL.insert.await([[
    INSERT INTO mz_world_drops (
      drop_uid,
      x,
      y,
      z,
      label,
      metadata_json
    ) VALUES (?, ?, ?, ?, ?, ?)
  ]], {
    data.drop_uid,
    tonumber(data.x) or 0,
    tonumber(data.y) or 0,
    tonumber(data.z) or 0,
    data.label,
    MZUtils.jsonEncode(data.metadata_json or {})
  })
end

function MZWorldDropRepository.getByUid(dropUid)
  local row = MySQL.single.await([[
    SELECT *
    FROM mz_world_drops
    WHERE drop_uid = ?
    LIMIT 1
  ]], { dropUid })

  return decodeDropRow(row)
end

function MZWorldDropRepository.listAll()
  local rows = MySQL.query.await([[
    SELECT *
    FROM mz_world_drops
    ORDER BY id DESC
  ]], {}) or {}

  return decodeDropRows(rows)
end

function MZWorldDropRepository.updateMetadataByUid(dropUid, metadata)
  return MySQL.update.await([[
    UPDATE mz_world_drops
    SET metadata_json = ?
    WHERE drop_uid = ?
  ]], {
    MZUtils.jsonEncode(metadata or {}),
    dropUid
  })
end

function MZWorldDropRepository.deleteByUid(dropUid)
  return MySQL.update.await([[
    DELETE FROM mz_world_drops
    WHERE drop_uid = ?
  ]], { dropUid })
end