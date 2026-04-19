MZInventoryRepository = {}

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

function MZInventoryRepository.findStackableSlot(ownerType, ownerId, inventoryType, itemName)
  local row = MySQL.single.await([[
    SELECT *
    FROM mz_inventory_items
    WHERE owner_type = ? AND owner_id = ? AND inventory_type = ? AND item = ? AND (instance_uid IS NULL OR instance_uid = '')
    ORDER BY slot ASC
    LIMIT 1
  ]], { ownerType, ownerId, inventoryType, itemName })

  if not row then return nil end
  row.amount = tonumber(row.amount) or 0
  row.slot = tonumber(row.slot) or 0
  row.metadata = MZUtils.jsonDecode(row.metadata, {})
  return row
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

function MZInventoryRepository.setSlot(data)
  MySQL.insert.await([[
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
  ]], {
    data.owner_type,
    data.owner_id,
    data.inventory_type,
    data.slot,
    data.item,
    data.amount,
    MZUtils.jsonEncode(data.metadata or {}),
    data.instance_uid
  })
end

function MZInventoryRepository.deleteSlot(ownerType, ownerId, inventoryType, slot)
  MySQL.query.await([[
    DELETE FROM mz_inventory_items
    WHERE owner_type = ? AND owner_id = ? AND inventory_type = ? AND slot = ?
  ]], { ownerType, ownerId, inventoryType, slot })
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
  MySQL.update.await([[
    UPDATE mz_inventory_items
    SET amount = ?, updated_at = CURRENT_TIMESTAMP
    WHERE owner_type = ? AND owner_id = ? AND inventory_type = ? AND slot = ?
  ]], { amount, ownerType, ownerId, inventoryType, slot })
end

function MZInventoryRepository.updateMetadataBySlot(ownerType, ownerId, inventoryType, slot, metadata)
  MySQL.update.await([[
    UPDATE mz_inventory_items
    SET metadata = ?, updated_at = CURRENT_TIMESTAMP
    WHERE owner_type = ? AND owner_id = ? AND inventory_type = ? AND slot = ?
  ]], {
    MZUtils.jsonEncode(metadata or {}),
    ownerType, ownerId, inventoryType, slot
  })
end