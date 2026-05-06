MZInventoryRepository = {}

local function metadataMatches(leftMetadata, rightMetadata)
  return json.encode(leftMetadata or {}) == json.encode(rightMetadata or {})
end

local function encodeMetadata(metadata)
  return MZUtils.jsonEncode(metadata or {})
end

local function decodeRows(rows)
  local out = {}
  for _, row in ipairs(rows or {}) do
    row.amount = tonumber(row.amount) or 0
    row.slot = tonumber(row.slot) or 0
    row.metadata = MZUtils.jsonDecode(row.metadata, {})
    out[#out + 1] = row
  end
  return out
end

function MZInventoryRepository.getInventory(ownerType, ownerId, inventoryType)
  local rows = MySQL.query.await([[
    SELECT *
    FROM mz_inventory_items
    WHERE owner_type = ? AND owner_id = ? AND inventory_type = ?
    ORDER BY slot ASC
  ]], { ownerType, ownerId, inventoryType }) or {}

  return decodeRows(rows)
end

function MZInventoryRepository.getSlot(ownerType, ownerId, inventoryType, slot)
  local row = MySQL.single.await([[
    SELECT *
    FROM mz_inventory_items
    WHERE owner_type = ? AND owner_id = ? AND inventory_type = ? AND slot = ?
    LIMIT 1
  ]], { ownerType, ownerId, inventoryType, slot })

  if not row then return nil end
  row.amount = tonumber(row.amount) or 0
  row.slot = tonumber(row.slot) or 0
  row.metadata = MZUtils.jsonDecode(row.metadata, {})
  return row
end

function MZInventoryRepository.getByInstanceUid(instanceUid)
  local row = MySQL.single.await([[
    SELECT *
    FROM mz_inventory_items
    WHERE instance_uid = ?
    LIMIT 1
  ]], { instanceUid })

  if not row then return nil end
  row.amount = tonumber(row.amount) or 0
  row.slot = tonumber(row.slot) or 0
  row.metadata = MZUtils.jsonDecode(row.metadata, {})
  return row
end

function MZInventoryRepository.getPlayerHotbar(citizenid)
  citizenid = tostring(citizenid or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if citizenid == '' then
    return {}
  end

  return MySQL.query.await([[
    SELECT citizenid, hotbar_slot, instance_uid, created_at, updated_at
    FROM mz_player_hotbar
    WHERE citizenid = ?
    ORDER BY hotbar_slot ASC
  ]], { citizenid }) or {}
end

function MZInventoryRepository.setPlayerHotbarSlot(citizenid, hotbarSlot, instanceUid)
  citizenid = tostring(citizenid or ''):gsub('^%s+', ''):gsub('%s+$', '')
  hotbarSlot = tonumber(hotbarSlot)
  instanceUid = tostring(instanceUid or ''):gsub('^%s+', ''):gsub('%s+$', '')

  if citizenid == '' or not hotbarSlot or hotbarSlot <= 0 or instanceUid == '' then
    return false, 'invalid_hotbar_bind'
  end

  local ok = MySQL.transaction.await({
    {
      query = [[
        DELETE FROM mz_player_hotbar
        WHERE citizenid = ? AND instance_uid = ? AND hotbar_slot <> ?
      ]],
      parameters = { citizenid, instanceUid, hotbarSlot }
    },
    {
      query = [[
        INSERT INTO mz_player_hotbar (citizenid, hotbar_slot, instance_uid)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE
          instance_uid = VALUES(instance_uid),
          updated_at = CURRENT_TIMESTAMP
      ]],
      parameters = { citizenid, hotbarSlot, instanceUid }
    }
  })

  if ok == false then
    return false, 'hotbar_save_failed'
  end

  return true
end

function MZInventoryRepository.clearPlayerHotbarSlot(citizenid, hotbarSlot)
  citizenid = tostring(citizenid or ''):gsub('^%s+', ''):gsub('%s+$', '')
  hotbarSlot = tonumber(hotbarSlot)
  if citizenid == '' or not hotbarSlot or hotbarSlot <= 0 then
    return false, 'invalid_hotbar_slot'
  end

  return MySQL.update.await([[
    DELETE FROM mz_player_hotbar
    WHERE citizenid = ? AND hotbar_slot = ?
  ]], { citizenid, hotbarSlot }) or 0
end

function MZInventoryRepository.clearPlayerHotbarByInstanceUid(citizenid, instanceUid)
  citizenid = tostring(citizenid or ''):gsub('^%s+', ''):gsub('%s+$', '')
  instanceUid = tostring(instanceUid or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if citizenid == '' or instanceUid == '' then
    return false, 'invalid_hotbar_instance'
  end

  return MySQL.update.await([[
    DELETE FROM mz_player_hotbar
    WHERE citizenid = ? AND instance_uid = ?
  ]], { citizenid, instanceUid }) or 0
end

function MZInventoryRepository.clearInvalidPlayerHotbarRefs(citizenid)
  citizenid = tostring(citizenid or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if citizenid == '' then
    return 0
  end

  return MySQL.update.await([[
    DELETE hb
    FROM mz_player_hotbar hb
    LEFT JOIN mz_inventory_items ii
      ON ii.instance_uid = hb.instance_uid
      AND ii.owner_type = 'player'
      AND ii.owner_id = hb.citizenid
      AND ii.inventory_type = 'main'
    WHERE hb.citizenid = ? AND ii.id IS NULL
  ]], { citizenid }) or 0
end

function MZInventoryRepository.findStackableSlot(ownerType, ownerId, inventoryType, itemName, metadata)
  local rows = MySQL.query.await([[
    SELECT *
    FROM mz_inventory_items
    WHERE owner_type = ? AND owner_id = ? AND inventory_type = ? AND item = ? AND (instance_uid IS NULL OR instance_uid = '')
    ORDER BY slot ASC
  ]], { ownerType, ownerId, inventoryType, itemName }) or {}

  for _, row in ipairs(rows) do
    row.amount = tonumber(row.amount) or 0
    row.slot = tonumber(row.slot) or 0
    row.metadata = MZUtils.jsonDecode(row.metadata, {})

    if metadataMatches(row.metadata, metadata) then
      return row
    end
  end

  return nil
end

function MZInventoryRepository.findItemRows(ownerType, ownerId, inventoryType, itemName)
  local rows = MySQL.query.await([[
    SELECT *
    FROM mz_inventory_items
    WHERE owner_type = ? AND owner_id = ? AND inventory_type = ? AND item = ?
    ORDER BY slot ASC
  ]], { ownerType, ownerId, inventoryType, itemName }) or {}

  return decodeRows(rows)
end

function MZInventoryRepository.findFreeSlot(ownerType, ownerId, inventoryType, maxSlots)
  local rows = MySQL.query.await([[
    SELECT slot
    FROM mz_inventory_items
    WHERE owner_type = ? AND owner_id = ? AND inventory_type = ?
    ORDER BY slot ASC
  ]], { ownerType, ownerId, inventoryType }) or {}

  local used = {}
  for _, row in ipairs(rows) do
    used[tonumber(row.slot)] = true
  end

  for slot = 1, maxSlots do
    if not used[slot] then
      return slot
    end
  end

  return nil
end

function MZInventoryRepository.buildSetSlotStatement(data)
  return {
    query = [[
      INSERT INTO mz_inventory_items (
        owner_type, owner_id, inventory_type, slot, item, amount, metadata, instance_uid
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON DUPLICATE KEY UPDATE
        item = VALUES(item),
        amount = VALUES(amount),
        metadata = VALUES(metadata),
        instance_uid = VALUES(instance_uid),
        updated_at = CURRENT_TIMESTAMP
    ]],
    parameters = {
      data.owner_type,
      data.owner_id,
      data.inventory_type,
      data.slot,
      data.item,
      data.amount,
      encodeMetadata(data.metadata),
      data.instance_uid
    }
  }
end

function MZInventoryRepository.buildDeleteSlotStatement(ownerType, ownerId, inventoryType, slot)
  return {
    query = [[
      DELETE FROM mz_inventory_items
      WHERE owner_type = ? AND owner_id = ? AND inventory_type = ? AND slot = ?
    ]],
    parameters = { ownerType, ownerId, inventoryType, slot }
  }
end

function MZInventoryRepository.buildUpdateAmountBySlotStatement(ownerType, ownerId, inventoryType, slot, amount)
  return {
    query = [[
      UPDATE mz_inventory_items
      SET amount = ?, updated_at = CURRENT_TIMESTAMP
      WHERE owner_type = ? AND owner_id = ? AND inventory_type = ? AND slot = ?
    ]],
    parameters = { amount, ownerType, ownerId, inventoryType, slot }
  }
end

function MZInventoryRepository.buildUpdateMetadataBySlotStatement(ownerType, ownerId, inventoryType, slot, metadata)
  return {
    query = [[
      UPDATE mz_inventory_items
      SET metadata = ?, updated_at = CURRENT_TIMESTAMP
      WHERE owner_type = ? AND owner_id = ? AND inventory_type = ? AND slot = ?
    ]],
    parameters = {
      encodeMetadata(metadata),
      ownerType,
      ownerId,
      inventoryType,
      slot
    }
  }
end

function MZInventoryRepository.runTransaction(statements)
  if type(statements) ~= 'table' or #statements == 0 then
    return true
  end

  local transactionStatements = {}

  for _, statement in ipairs(statements) do
    if type(statement) == 'table' and type(statement.query) == 'string' and statement.query ~= '' then
      transactionStatements[#transactionStatements + 1] = {
        query = statement.query,
        parameters = statement.parameters or statement.values or {}
      }
    end
  end

  if #transactionStatements == 0 then
    return true
  end

  local ok, result = pcall(function()
    return MySQL.transaction.await(transactionStatements)
  end)

  if not ok or result == false then
    return false, ok and 'inventory_transaction_failed' or tostring(result)
  end

  return true
end

function MZInventoryRepository.setSlot(data)
  local statement = MZInventoryRepository.buildSetSlotStatement(data)
  MySQL.insert.await(statement.query, statement.parameters)
end

function MZInventoryRepository.deleteSlot(ownerType, ownerId, inventoryType, slot)
  local statement = MZInventoryRepository.buildDeleteSlotStatement(ownerType, ownerId, inventoryType, slot)
  MySQL.query.await(statement.query, statement.parameters)
end

function MZInventoryRepository.clearInventory(ownerType, ownerId, inventoryType)
  return MySQL.update.await([[
    DELETE FROM mz_inventory_items
    WHERE owner_type = ? AND owner_id = ? AND inventory_type = ?
  ]], {
    ownerType,
    ownerId,
    inventoryType
  })
end

function MZInventoryRepository.updateAmountBySlot(ownerType, ownerId, inventoryType, slot, amount)
  local statement = MZInventoryRepository.buildUpdateAmountBySlotStatement(ownerType, ownerId, inventoryType, slot, amount)
  MySQL.update.await(statement.query, statement.parameters)
end

function MZInventoryRepository.updateMetadataBySlot(ownerType, ownerId, inventoryType, slot, metadata)
  local statement = MZInventoryRepository.buildUpdateMetadataBySlotStatement(ownerType, ownerId, inventoryType, slot, metadata)
  MySQL.update.await(statement.query, statement.parameters)
end
