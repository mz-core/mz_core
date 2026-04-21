MZInventoryService = {}

local ItemUseHandlers = {}

local function getItemDefinition(itemName)
  return MZItems and MZItems[itemName] or nil
end

local function getPlayerBySource(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then
    return nil, 'player_not_loaded'
  end
  return player
end


local function getPlayerOrg(source, orgCode)
  local player, err = getPlayerBySource(source)
  if not player then
    return nil, err
  end

  if not orgCode or orgCode == '' then
    return nil, 'invalid_org'
  end

  local org = nil
  if MZOrgService.getOrgByCode then
    org = MZOrgService.getOrgByCode(orgCode)
  elseif MZOrgService.getOrg then
    org = MZOrgService.getOrg(orgCode)
  end

  if not org then
    return nil, 'org_not_found'
  end

  local membership = nil

  -- 1) tenta pelos métodos do service, se existirem
  if MZOrgService.getPlayerMembershipByOrgId then
    membership = MZOrgService.getPlayerMembershipByOrgId(player.citizenid, org.id)
  elseif MZOrgService.getPlayerMembershipByOrg then
    membership = MZOrgService.getPlayerMembershipByOrg(player.citizenid, orgCode)
  elseif MZOrgService.getPlayerMembership then
    membership = MZOrgService.getPlayerMembership(player.citizenid, org.id)
      or MZOrgService.getPlayerMembership(player.citizenid, orgCode)
  elseif MZOrgService.getMembershipByCitizenIdAndOrg then
    membership = MZOrgService.getMembershipByCitizenIdAndOrg(player.citizenid, org.id)
      or MZOrgService.getMembershipByCitizenIdAndOrg(player.citizenid, orgCode)
  end

  -- 2) fallback direto no repository/banco
  if not membership and MZOrgRepository and MZOrgRepository.getPlayerOrgMembership then
    membership = MZOrgRepository.getPlayerOrgMembership(player.citizenid, org.id)
  end

  if not membership and MZOrgRepository and MZOrgRepository.getPlayerOrgByCitizenIdAndOrgId then
    membership = MZOrgRepository.getPlayerOrgByCitizenIdAndOrgId(player.citizenid, org.id)
  end

  if not membership and MZOrgRepository and MZOrgRepository.getMembershipByCitizenIdAndOrgId then
    membership = MZOrgRepository.getMembershipByCitizenIdAndOrgId(player.citizenid, org.id)
  end

  if not membership then
    local rows = MySQL.query.await([[
      SELECT id, citizenid, org_id, grade_id, is_primary, active, duty, expires_at, joined_at, updated_at
      FROM mz_player_orgs
      WHERE citizenid = ? AND org_id = ? AND active = 1
      LIMIT 1
    ]], { player.citizenid, org.id })

    if rows and rows[1] then
      membership = rows[1]
    end
  end

  if not membership then
    return nil, 'not_in_org'
  end

  return {
    player = player,
    membership = membership,
    org = org
  }
end


local function getPlayerInventoryContext(source)
  local player, err = getPlayerBySource(source)
  if not player then
    return nil, err
  end

  return {
    label = 'player_main',
    ownerType = 'player',
    ownerId = player.citizenid,
    inventoryType = MZConstants.InventoryTypes.MAIN,
    maxSlots = (Config.Inventory and Config.Inventory.defaultSlots) or 40,
    maxWeight = (Config.Inventory and Config.Inventory.defaultWeight) or 50000,
    player = player
  }
end

local function getPersonalStashContext(source)
  local player, err = getPlayerBySource(source)
  if not player then
    return nil, err
  end

  local stashConfig = (Config.Inventory and Config.Inventory.personalStash) or {}

  return {
    label = 'personal_stash',
    ownerType = 'stash',
    ownerId = ('personal:%s'):format(player.citizenid),
    inventoryType = MZConstants.InventoryTypes.STASH,
    maxSlots = tonumber(stashConfig.slots) or 40,
    maxWeight = tonumber(stashConfig.weight) or 75000,
    player = player
  }
end

local function getOrgStashContext(source, orgCode)
  local orgData, err = getPlayerOrg(source, orgCode)
  if not orgData then
    return nil, err
  end

  local orgStashConfig = (Config.Inventory and Config.Inventory.orgStash) or {}

  return {
    label = 'org_stash',
    ownerType = 'org',
    ownerId = tostring(orgData.org.code),
    inventoryType = MZConstants.InventoryTypes.STASH,
    maxSlots = tonumber(orgStashConfig.slots) or 80,
    maxWeight = tonumber(orgStashConfig.weight) or 200000,
    player = orgData.player,
    membership = orgData.membership,
    org = orgData.org
  }
end

local function getVehicleTrunkContext(source, plate)
  plate = tostring(plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
  if plate == '' then
    return nil, 'invalid_plate'
  end

  local accessOk, vehicleOrErr = MZVehicleService.canAccessVehicle(source, plate)
  if not accessOk then
    return nil, vehicleOrErr
  end

  local trunkConfig = (Config.Inventory and Config.Inventory.trunk) or {}

  return {
    label = 'vehicle_trunk',
    ownerType = 'vehicle',
    ownerId = plate,
    inventoryType = 'trunk',
    maxSlots = tonumber(trunkConfig.slots) or 30,
    maxWeight = tonumber(trunkConfig.weight) or 120000,
    vehicle = vehicleOrErr
  }
end

local function getVehicleGloveboxContext(source, plate)
  plate = tostring(plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
  if plate == '' then
    return nil, 'invalid_plate'
  end

  local accessOk, vehicleOrErr = MZVehicleService.canAccessVehicle(source, plate)
  if not accessOk then
    return nil, vehicleOrErr
  end

  local gloveboxConfig = (Config.Inventory and Config.Inventory.glovebox) or {}

  return {
    label = 'vehicle_glovebox',
    ownerType = 'vehicle',
    ownerId = plate,
    inventoryType = 'glovebox',
    maxSlots = tonumber(gloveboxConfig.slots) or 8,
    maxWeight = tonumber(gloveboxConfig.weight) or 15000,
    vehicle = vehicleOrErr
  }
end

local function generateWorldDropUid()
  return MZUtils.generateInstanceUid('DROP')
end

local function normalizeWorldCoords(coords)
  if type(coords) ~= 'table' then
    return {
      x = 0,
      y = 0,
      z = 0
    }
  end

  return {
    x = tonumber(coords.x) or tonumber(coords[1]) or 0,
    y = tonumber(coords.y) or tonumber(coords[2]) or 0,
    z = tonumber(coords.z) or tonumber(coords[3]) or 0
  }
end

local function getWorldDropContext(dropUid)
  dropUid = tostring(dropUid or '')
  if dropUid == '' then
    return nil, 'invalid_drop_uid'
  end

  local drop = MZWorldDropRepository.getByUid(dropUid)
  if not drop then
    return nil, 'drop_not_found'
  end

  return {
    label = 'world_drop',
    ownerType = 'world',
    ownerId = dropUid,
    inventoryType = 'drop',
    maxSlots = 40,
    maxWeight = 1000000,
    drop = drop
  }
end

local function isDropEmpty(dropUid)
  local rows = MZInventoryRepository.getInventory('world', dropUid, 'drop')
  return type(rows) ~= 'table' or #rows == 0
end

local function cleanupDropIfEmpty(dropUid)
  if isDropEmpty(dropUid) then
    MZWorldDropRepository.deleteByUid(dropUid)
    return true
  end

  return false
end

local function computeRowWeight(row)
  local def = getItemDefinition(row.item)
  if not def then return 0 end
  local amount = tonumber(row.amount) or 0
  local weight = tonumber(def.weight) or 0
  return weight * amount
end

local function getInventoryWeight(ownerType, ownerId, inventoryType)
  local rows = MZInventoryRepository.getInventory(ownerType, ownerId, inventoryType)
  local total = 0
  for _, row in ipairs(rows) do
    total = total + computeRowWeight(row)
  end
  return total
end


local function cloneTable(value)
  if type(value) ~= 'table' then
    return value
  end

  local out = {}
  for k, v in pairs(value) do
    out[k] = cloneTable(v)
  end
  return out
end

local function buildInventoryActor(player, source)
  if player and player.citizenid then
    return {
      type = 'player',
      id = tostring(player.citizenid),
      source = source
    }
  end

  if tonumber(source) == 0 then
    return {
      type = 'console',
      id = 'console'
    }
  end

  if source ~= nil then
    return {
      type = 'source',
      id = tostring(source)
    }
  end

  return {
    type = 'system',
    id = 'system'
  }
end

local function buildInventoryTarget(ctx)
  return {
    type = 'inventory',
    id = ('%s:%s:%s'):format(tostring(ctx and ctx.ownerType or 'unknown'), tostring(ctx and ctx.ownerId or 'unknown'), tostring(ctx and ctx.inventoryType or 'unknown'))
  }
end

local function buildInventoryContext(ctx, extra)
  local context = cloneTable(extra or {})
  if ctx then
    context.inventory_label = tostring(ctx.label or '')
    context.owner_type = tostring(ctx.ownerType or '')
    context.owner_id = tostring(ctx.ownerId or '')
    context.inventory_type = tostring(ctx.inventoryType or '')
    context.max_slots = tonumber(ctx.maxSlots) or 0
    context.max_weight = tonumber(ctx.maxWeight) or 0

    if ctx.org then
      context.org_code = tostring(ctx.org.code or '')
      context.org_id = tonumber(ctx.org.id) or ctx.org.id
    end

    if ctx.vehicle then
      context.vehicle_id = tonumber(ctx.vehicle.id) or ctx.vehicle.id
      context.plate = tostring(ctx.vehicle.plate or '')
      context.model = tostring(ctx.vehicle.model or '')
    end

    if ctx.drop then
      context.drop_uid = tostring(ctx.drop.drop_uid or ctx.ownerId or '')
      context.coords = cloneTable(ctx.drop.coords_json or ctx.drop.coords or {})
    end
  end
  return context
end

local function buildSlotSnapshot(row, slot)
  if not row then
    return { slot = tonumber(slot) or slot }
  end

  return {
    slot = tonumber(slot) or tonumber(row.slot) or row.slot,
    item = tostring(row.item or ''),
    amount = tonumber(row.amount) or 0,
    instance_uid = row.instance_uid and tostring(row.instance_uid) or nil,
    metadata = cloneTable(type(row.metadata) == 'table' and row.metadata or {})
  }
end

local function logInventoryAction(action, source, player, targetCtx, payload)
  if not MZLogService then
    return
  end

  payload = payload or {}

  MZLogService.createDetailed('inventory', action, {
    actor = payload.actor or buildInventoryActor(player, source),
    target = payload.target or buildInventoryTarget(targetCtx),
    context = payload.context or buildInventoryContext(targetCtx),
    before = payload.before or {},
    after = payload.after or {},
    meta = payload.meta or {}
  })
end

local function canCarry(ownerType, ownerId, inventoryType, itemName, amount, maxWeight)
  local def = getItemDefinition(itemName)
  if not def then
    return false, 'item_not_found'
  end

  local currentWeight = getInventoryWeight(ownerType, ownerId, inventoryType)
  local itemWeight = (tonumber(def.weight) or 0) * amount

  if currentWeight + itemWeight > maxWeight then
    return false, 'inventory_full'
  end

  return true
end

local function buildItemMetadata(itemDef, metadata, citizenid, itemName)
  local out = MZUtils.tableClone(metadata or {})

  if itemDef.unique then
    out.uid = out.uid or MZUtils.generateInstanceUid('MZINV')
  end

  if itemDef.generateSerial then
    out.serial = out.serial or MZUtils.generateItemSerial(itemName)
  end

  if itemDef.bindOnReceive and citizenid then
    out.owner = out.owner or citizenid
    out.bound = true
  end

  if itemDef.hasDurability and out.durability == nil then
    out.durability = 100
  end

  return out
end

local function isValidSlotNumber(slot, maxSlots)
  slot = tonumber(slot)
  if not slot then
    return false
  end

  if slot < 1 or slot > maxSlots then
    return false
  end

  return true
end

local function getInventoryRowsFromContext(ctx)
  return MZInventoryRepository.getInventory(ctx.ownerType, ctx.ownerId, ctx.inventoryType)
end

local function getInventoryWeightFromContext(ctx)
  return getInventoryWeight(ctx.ownerType, ctx.ownerId, ctx.inventoryType)
end

local function canCarryInContext(ctx, itemName, amount)
  return canCarry(ctx.ownerType, ctx.ownerId, ctx.inventoryType, itemName, amount, ctx.maxWeight)
end

local function setRowInContext(ctx, slot, itemName, amount, metadata, instanceUid)
  MZInventoryRepository.setSlot({
    owner_type = ctx.ownerType,
    owner_id = ctx.ownerId,
    inventory_type = ctx.inventoryType,
    slot = slot,
    item = itemName,
    amount = amount,
    metadata = metadata or {},
    instance_uid = instanceUid
  })
end

local function deleteRowInContext(ctx, slot)
  MZInventoryRepository.deleteSlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, slot)
end

local function updateAmountInContext(ctx, slot, amount)
  MZInventoryRepository.updateAmountBySlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, slot, amount)
end

local function getSlotInContext(ctx, slot)
  return MZInventoryRepository.getSlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, slot)
end

local function metadataMatches(leftMetadata, rightMetadata)
  return json.encode(leftMetadata or {}) == json.encode(rightMetadata or {})
end

local function findStackableSlotInContext(ctx, itemName, metadata)
  return MZInventoryRepository.findStackableSlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, itemName, metadata)
end

local function canMergeRows(itemDef, fromRow, toRow)
  if not itemDef or itemDef.unique then
    return false
  end

  if not fromRow or not toRow then
    return false
  end

  if fromRow.item ~= toRow.item then
    return false
  end

  local fromMetadata = fromRow.metadata or {}
  local toMetadata = toRow.metadata or {}

  return metadataMatches(fromMetadata, toMetadata)
end

local function moveBetweenContexts(actorPlayer, fromCtx, toCtx, fromSlot, toSlot, amount)
  local actorSource = actorPlayer and actorPlayer.source or nil
  fromSlot = tonumber(fromSlot)
  toSlot = tonumber(toSlot)
  amount = tonumber(amount)

  if not isValidSlotNumber(fromSlot, fromCtx.maxSlots) then
    return false, 'invalid_from_slot'
  end

  if not isValidSlotNumber(toSlot, toCtx.maxSlots) then
    return false, 'invalid_to_slot'
  end

  if fromCtx.ownerType == toCtx.ownerType
  and fromCtx.ownerId == toCtx.ownerId
  and fromCtx.inventoryType == toCtx.inventoryType
  and fromSlot == toSlot then
    return false, 'same_slot'
  end

  local fromRow = getSlotInContext(fromCtx, fromSlot)
  if not fromRow then
    return false, 'source_slot_empty'
  end

  local itemDef = getItemDefinition(fromRow.item)
  if not itemDef then
    return false, 'item_not_found'
  end

  local fromAmount = tonumber(fromRow.amount) or 0
  if fromAmount <= 0 then
    return false, 'invalid_source_amount'
  end

  if itemDef.unique then
    amount = 1
  else
    if amount == nil then
      amount = fromAmount
    end

    if amount <= 0 or amount > fromAmount then
      return false, 'invalid_amount'
    end
  end

  local toRow = getSlotInContext(toCtx, toSlot)

  if not toRow and itemDef.stack and amount < fromAmount then
    local stackableSlot = findStackableSlotInContext(toCtx, fromRow.item, fromRow.metadata or {})
    if stackableSlot and tonumber(stackableSlot.slot) ~= toSlot then
      toSlot = tonumber(stackableSlot.slot)
      toRow = getSlotInContext(toCtx, toSlot)
    end
  end

  local carryOk, carryErr = canCarryInContext(toCtx, fromRow.item, amount)
  if not carryOk then
    return false, carryErr
  end

  if not toRow then
    if itemDef.unique or amount >= fromAmount then
      deleteRowInContext(fromCtx, fromSlot)

      setRowInContext(
        toCtx,
        toSlot,
        fromRow.item,
        itemDef.unique and 1 or fromRow.amount,
        fromRow.metadata or {},
        fromRow.instance_uid
      )
    else
      updateAmountInContext(fromCtx, fromSlot, fromAmount - amount)

      setRowInContext(
        toCtx,
        toSlot,
        fromRow.item,
        amount,
        fromRow.metadata or {},
        fromRow.instance_uid
      )
    end

    if actorPlayer then
      logInventoryAction('move_between_inventories', actorSource, actorPlayer, toCtx, {
        context = {
          from_inventory = buildInventoryContext(fromCtx, { slot = tonumber(fromSlot) or fromSlot }),
          to_inventory = buildInventoryContext(toCtx, { slot = tonumber(toSlot) or toSlot }),
          mode = 'move_between_inventories'
        },
        before = {
          from_slot = buildSlotSnapshot(fromRow, fromSlot),
          to_slot = buildSlotSnapshot(toRow, toSlot)
        },
        after = {
          moved_item = buildSlotSnapshot({ item = fromRow.item, amount = amount, metadata = fromRow.metadata, instance_uid = fromRow.instance_uid }, toSlot)
        },
        meta = {
          requested_amount = amount,
          item = fromRow.item
        }
      })
    end

    return true
  end

  if canMergeRows(itemDef, fromRow, toRow) then
    local toAmount = tonumber(toRow.amount) or 0

    if amount >= fromAmount then
      updateAmountInContext(toCtx, toSlot, toAmount + fromAmount)
      deleteRowInContext(fromCtx, fromSlot)
    else
      updateAmountInContext(fromCtx, fromSlot, fromAmount - amount)
      updateAmountInContext(toCtx, toSlot, toAmount + amount)
    end

    if actorPlayer then
      logInventoryAction('merge_between_inventories', actorSource, actorPlayer, toCtx, {
        context = {
          from_inventory = buildInventoryContext(fromCtx, { slot = tonumber(fromSlot) or fromSlot }),
          to_inventory = buildInventoryContext(toCtx, { slot = tonumber(toSlot) or toSlot }),
          mode = 'merge_between_inventories'
        },
        before = {
          from_slot = buildSlotSnapshot(fromRow, fromSlot),
          to_slot = buildSlotSnapshot(toRow, toSlot)
        },
        after = {
          merged_item = buildSlotSnapshot({ item = fromRow.item, amount = amount, metadata = fromRow.metadata, instance_uid = fromRow.instance_uid }, toSlot)
        },
        meta = {
          requested_amount = amount,
          item = fromRow.item
        }
      })
    end

    return true
  end

  if amount < fromAmount then
    return false, 'partial_move_blocked'
  end

  deleteRowInContext(fromCtx, fromSlot)
  deleteRowInContext(toCtx, toSlot)

  setRowInContext(
    fromCtx,
    fromSlot,
    toRow.item,
    toRow.amount,
    toRow.metadata or {},
    toRow.instance_uid
  )

  setRowInContext(
    toCtx,
    toSlot,
    fromRow.item,
    fromRow.amount,
    fromRow.metadata or {},
    fromRow.instance_uid
  )

  if actorPlayer then
    logInventoryAction('swap_between_inventories', actorSource, actorPlayer, toCtx, {
      context = {
        from_inventory = buildInventoryContext(fromCtx, { slot = tonumber(fromSlot) or fromSlot }),
        to_inventory = buildInventoryContext(toCtx, { slot = tonumber(toSlot) or toSlot }),
        mode = 'swap_between_inventories'
      },
      before = {
        from_slot = buildSlotSnapshot(fromRow, fromSlot),
        to_slot = buildSlotSnapshot(toRow, toSlot)
      },
      after = {
        from_slot = buildSlotSnapshot(toRow, fromSlot),
        to_slot = buildSlotSnapshot(fromRow, toSlot)
      },
      meta = {
        from_item = fromRow.item,
        to_item = toRow.item
      }
    })
  end

  return true
end

local function normalizeMetadataTable(metadata)
  if type(metadata) ~= 'table' then
    return {}
  end

  return metadata
end

local function normalizeUseResult(result)
  if result == nil then
    return {
      ok = true,
      consume = false
    }
  end

  if type(result) == 'boolean' then
    return {
      ok = result,
      consume = false
    }
  end

  if type(result) ~= 'table' then
    return {
      ok = false,
      error = 'invalid_use_result'
    }
  end

  return {
    ok = result.ok ~= false,
    consume = result.consume == true,
    amount = tonumber(result.amount) or 1,
    error = result.error,
    data = result.data
  }
end

function MZInventoryService.getItemDefinition(itemName)
  return getItemDefinition(itemName)
end

function MZInventoryService.registerItemUseHandler(itemName, handler)
  if type(itemName) ~= 'string' or itemName == '' then
    return false, 'invalid_item'
  end

  if type(handler) ~= 'function' then
    return false, 'invalid_handler'
  end

  ItemUseHandlers[itemName] = handler
  return true
end

function MZInventoryService.getPlayerInventory(source)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then return false, err end

  local rows = MZInventoryRepository.getInventory(ctx.ownerType, ctx.ownerId, ctx.inventoryType)
  return true, rows
end

function MZInventoryService.getPlayerWeight(source)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then return false, err end

  local weight = getInventoryWeight(ctx.ownerType, ctx.ownerId, ctx.inventoryType)
  return true, weight, ctx.maxWeight
end

function MZInventoryService.getPersonalStash(source)
  local ctx, err = getPersonalStashContext(source)
  if not ctx then
    return false, err
  end

  local rows = getInventoryRowsFromContext(ctx)
  return true, rows
end

function MZInventoryService.getPersonalStashWeight(source)
  local ctx, err = getPersonalStashContext(source)
  if not ctx then
    return false, err
  end

  local weight = getInventoryWeightFromContext(ctx)
  return true, weight, ctx.maxWeight
end

function MZInventoryService.movePlayerToPersonalStash(source, fromSlot, toSlot, amount)
  local playerCtx, err = getPlayerInventoryContext(source)
  if not playerCtx then
    return false, err
  end

  local stashCtx, stashErr = getPersonalStashContext(source)
  if not stashCtx then
    return false, stashErr
  end

  return moveBetweenContexts(playerCtx.player, playerCtx, stashCtx, fromSlot, toSlot, amount)
end

function MZInventoryService.movePersonalStashToPlayer(source, fromSlot, toSlot, amount)
  local playerCtx, err = getPlayerInventoryContext(source)
  if not playerCtx then
    return false, err
  end

  local stashCtx, stashErr = getPersonalStashContext(source)
  if not stashCtx then
    return false, stashErr
  end

  return moveBetweenContexts(playerCtx.player, stashCtx, playerCtx, fromSlot, toSlot, amount)
end

function MZInventoryService.getOrgStash(source, orgCode)
  local ctx, err = getOrgStashContext(source, orgCode)
  if not ctx then
    return false, err
  end

  local rows = getInventoryRowsFromContext(ctx)
  return true, rows
end

function MZInventoryService.getOrgStashWeight(source, orgCode)
  local ctx, err = getOrgStashContext(source, orgCode)
  if not ctx then
    return false, err
  end

  local weight = getInventoryWeightFromContext(ctx)
  return true, weight, ctx.maxWeight
end

function MZInventoryService.movePlayerToOrgStash(source, orgCode, fromSlot, toSlot, amount)
  local playerCtx, err = getPlayerInventoryContext(source)
  if not playerCtx then
    return false, err
  end

  local orgCtx, orgErr = getOrgStashContext(source, orgCode)
  if not orgCtx then
    return false, orgErr
  end

  return moveBetweenContexts(playerCtx.player, playerCtx, orgCtx, fromSlot, toSlot, amount)
end

function MZInventoryService.moveOrgStashToPlayer(source, orgCode, fromSlot, toSlot, amount)
  local playerCtx, err = getPlayerInventoryContext(source)
  if not playerCtx then
    return false, err
  end

  local orgCtx, orgErr = getOrgStashContext(source, orgCode)
  if not orgCtx then
    return false, orgErr
  end

  return moveBetweenContexts(playerCtx.player, orgCtx, playerCtx, fromSlot, toSlot, amount)
end

function MZInventoryService.getVehicleTrunk(source, plate)
  local ctx, err = getVehicleTrunkContext(source, plate)
  if not ctx then
    return false, err
  end

  local rows = getInventoryRowsFromContext(ctx)
  return true, rows
end

function MZInventoryService.getVehicleTrunkWeight(source, plate)
  local ctx, err = getVehicleTrunkContext(source, plate)
  if not ctx then
    return false, err
  end

  local weight = getInventoryWeightFromContext(ctx)
  return true, weight, ctx.maxWeight
end

function MZInventoryService.movePlayerToVehicleTrunk(source, plate, fromSlot, toSlot, amount)
  local playerCtx, err = getPlayerInventoryContext(source)
  if not playerCtx then
    return false, err
  end

  local trunkCtx, trunkErr = getVehicleTrunkContext(source, plate)
  if not trunkCtx then
    return false, trunkErr
  end

  return moveBetweenContexts(playerCtx.player, playerCtx, trunkCtx, fromSlot, toSlot, amount)
end

function MZInventoryService.moveVehicleTrunkToPlayer(source, plate, fromSlot, toSlot, amount)
  local playerCtx, err = getPlayerInventoryContext(source)
  if not playerCtx then
    return false, err
  end

  local trunkCtx, trunkErr = getVehicleTrunkContext(source, plate)
  if not trunkCtx then
    return false, trunkErr
  end

  return moveBetweenContexts(playerCtx.player, trunkCtx, playerCtx, fromSlot, toSlot, amount)
end

function MZInventoryService.getVehicleGlovebox(source, plate)
  local ctx, err = getVehicleGloveboxContext(source, plate)
  if not ctx then
    return false, err
  end

  local rows = getInventoryRowsFromContext(ctx)
  return true, rows
end

function MZInventoryService.getVehicleGloveboxWeight(source, plate)
  local ctx, err = getVehicleGloveboxContext(source, plate)
  if not ctx then
    return false, err
  end

  local weight = getInventoryWeightFromContext(ctx)
  return true, weight, ctx.maxWeight
end

function MZInventoryService.movePlayerToVehicleGlovebox(source, plate, fromSlot, toSlot, amount)
  local playerCtx, err = getPlayerInventoryContext(source)
  if not playerCtx then
    return false, err
  end

  local gloveboxCtx, gloveboxErr = getVehicleGloveboxContext(source, plate)
  if not gloveboxCtx then
    return false, gloveboxErr
  end

  return moveBetweenContexts(playerCtx.player, playerCtx, gloveboxCtx, fromSlot, toSlot, amount)
end

function MZInventoryService.moveVehicleGloveboxToPlayer(source, plate, fromSlot, toSlot, amount)
  local playerCtx, err = getPlayerInventoryContext(source)
  if not playerCtx then
    return false, err
  end

  local gloveboxCtx, gloveboxErr = getVehicleGloveboxContext(source, plate)
  if not gloveboxCtx then
    return false, gloveboxErr
  end

  return moveBetweenContexts(playerCtx.player, gloveboxCtx, playerCtx, fromSlot, toSlot, amount)
end

function MZInventoryService.createWorldDrop(coords, label, metadata)
  local dropUid = generateWorldDropUid()
  local pos = normalizeWorldCoords(coords)

  local okId = MZWorldDropRepository.create({
    drop_uid = dropUid,
    x = pos.x,
    y = pos.y,
    z = pos.z,
    label = tostring(label or 'Drop'),
    metadata_json = metadata or {}
  })

  if not okId then
    return false, 'drop_create_failed'
  end

  local drop = MZWorldDropRepository.getByUid(dropUid)
  if not drop then
    return false, 'drop_not_found'
  end

  return true, drop
end

function MZInventoryService.deleteWorldDrop(dropUid)
  dropUid = tostring(dropUid or '')
  if dropUid == '' then
    return false, 'invalid_drop_uid'
  end

  MZInventoryRepository.clearInventory('world', dropUid, 'drop')
  MZWorldDropRepository.deleteByUid(dropUid)

  return true
end

function MZInventoryService.getWorldDrop(dropUid)
  local ctx, err = getWorldDropContext(dropUid)
  if not ctx then
    return false, err
  end

  local rows = getInventoryRowsFromContext(ctx)
  return true, rows, ctx.drop
end

function MZInventoryService.getWorldDropWeight(dropUid)
  local ctx, err = getWorldDropContext(dropUid)
  if not ctx then
    return false, err
  end

  local weight = getInventoryWeightFromContext(ctx)
  return true, weight, ctx.maxWeight, ctx.drop
end

function MZInventoryService.movePlayerToWorldDrop(source, dropUid, fromSlot, toSlot, amount)
  local playerCtx, err = getPlayerInventoryContext(source)
  if not playerCtx then
    return false, err
  end

  local dropCtx, dropErr = getWorldDropContext(dropUid)
  if not dropCtx then
    return false, dropErr
  end

  return moveBetweenContexts(playerCtx.player, playerCtx, dropCtx, fromSlot, toSlot, amount)
end

function MZInventoryService.moveWorldDropToPlayer(source, dropUid, fromSlot, toSlot, amount)
  local playerCtx, err = getPlayerInventoryContext(source)
  if not playerCtx then
    return false, err
  end

  local dropCtx, dropErr = getWorldDropContext(dropUid)
  if not dropCtx then
    return false, dropErr
  end

  local ok, result = moveBetweenContexts(playerCtx.player, dropCtx, playerCtx, fromSlot, toSlot, amount)
  if not ok then
    return false, result
  end

  cleanupDropIfEmpty(dropUid)

  return true
end

function MZInventoryService.listWorldDrops()
  return true, MZWorldDropRepository.listAll()
end

function MZInventoryService.hasPlayerItem(source, itemName, amount)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then return false, err end

  local needed = tonumber(amount) or 1
  local rows = MZInventoryRepository.findItemRows(ctx.ownerType, ctx.ownerId, ctx.inventoryType, itemName)
  local total = 0

  for _, row in ipairs(rows) do
    total = total + (tonumber(row.amount) or 0)
  end

  return total >= needed, total
end

function MZInventoryService.addPlayerItem(source, itemName, amount, metadata)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then return false, err end

  local itemDef = getItemDefinition(itemName)
  if not itemDef then return false, 'item_not_found' end

  amount = tonumber(amount) or 1
  if amount <= 0 then return false, 'invalid_amount' end

  local canCarryOk, carryErr = canCarry(ctx.ownerType, ctx.ownerId, ctx.inventoryType, itemName, amount, ctx.maxWeight)
  if not canCarryOk then
    return false, carryErr
  end

  if itemDef.unique then
    local uniqueCount = math.floor(amount)
    local usedSlots = {}
    local rows = getInventoryRowsFromContext(ctx)

    for _, row in ipairs(rows) do
      local slotNumber = tonumber(row.slot)
      if slotNumber then
        usedSlots[slotNumber] = true
      end
    end

    local freeSlots = 0
    for slotNumber = 1, ctx.maxSlots do
      if not usedSlots[slotNumber] then
        freeSlots = freeSlots + 1
      end
    end

    if freeSlots < uniqueCount then
      return false, 'no_free_slot'
    end

    for _ = 1, uniqueCount do
      local slot = MZInventoryRepository.findFreeSlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, ctx.maxSlots)
      if not slot then
        return false, 'no_free_slot'
      end

      local finalMetadata = buildItemMetadata(itemDef, metadata, ctx.player.citizenid, itemName)

      MZInventoryRepository.setSlot({
        owner_type = ctx.ownerType,
        owner_id = ctx.ownerId,
        inventory_type = ctx.inventoryType,
        slot = slot,
        item = itemName,
        amount = 1,
        metadata = finalMetadata,
        instance_uid = finalMetadata.uid
      })

      logInventoryAction('add_unique_item', source, ctx.player, ctx, {
        before = {},
        after = {
          slot = buildSlotSnapshot({ item = itemName, amount = 1, metadata = finalMetadata, instance_uid = finalMetadata.uid }, slot)
        },
        meta = {
          item = itemName,
          unique = true
        }
      })
    end

    return true
  end

  local stackSlot = itemDef.stack and MZInventoryRepository.findStackableSlot(
    ctx.ownerType,
    ctx.ownerId,
    ctx.inventoryType,
    itemName,
    metadata or {}
  ) or nil

  if stackSlot then
    MZInventoryRepository.updateAmountBySlot(
      ctx.ownerType,
      ctx.ownerId,
      ctx.inventoryType,
      stackSlot.slot,
      (tonumber(stackSlot.amount) or 0) + amount
    )

    logInventoryAction('stack_item', source, ctx.player, ctx, {
      before = {
        slot = buildSlotSnapshot(stackSlot, stackSlot.slot)
      },
      after = {
        slot = buildSlotSnapshot({ item = itemName, amount = (tonumber(stackSlot.amount) or 0) + amount, metadata = stackSlot.metadata, instance_uid = stackSlot.instance_uid }, stackSlot.slot)
      },
      meta = {
        item = itemName,
        delta = amount
      }
    })

    return true
  end

  local slot = MZInventoryRepository.findFreeSlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, ctx.maxSlots)
  if not slot then
    return false, 'no_free_slot'
  end

  MZInventoryRepository.setSlot({
    owner_type = ctx.ownerType,
    owner_id = ctx.ownerId,
    inventory_type = ctx.inventoryType,
    slot = slot,
    item = itemName,
    amount = amount,
    metadata = metadata or {},
    instance_uid = nil
  })

  logInventoryAction('add_item', source, ctx.player, ctx, {
    after = {
      slot = buildSlotSnapshot({ item = itemName, amount = amount, metadata = metadata or {} }, slot)
    },
    meta = {
      item = itemName,
      delta = amount
    }
  })

  return true
end

function MZInventoryService.removePlayerItem(source, itemName, amount)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then return false, err end

  local itemDef = getItemDefinition(itemName)
  if not itemDef then return false, 'item_not_found' end

  amount = tonumber(amount) or 1
  if amount <= 0 then return false, 'invalid_amount' end

  local rows = MZInventoryRepository.findItemRows(ctx.ownerType, ctx.ownerId, ctx.inventoryType, itemName)
  local total = 0
  for _, row in ipairs(rows) do
    total = total + (tonumber(row.amount) or 0)
  end

  if total < amount then
    return false, 'not_enough_items'
  end

  local remaining = amount

  for _, row in ipairs(rows) do
    if remaining <= 0 then break end

    local rowAmount = tonumber(row.amount) or 0
    if rowAmount <= remaining then
      MZInventoryRepository.deleteSlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, row.slot)
      remaining = remaining - rowAmount
    else
      MZInventoryRepository.updateAmountBySlot(
        ctx.ownerType, ctx.ownerId, ctx.inventoryType, row.slot, rowAmount - remaining
      )
      remaining = 0
    end
  end

  logInventoryAction('remove_item', source, ctx.player, ctx, {
    meta = {
      item = itemName,
      delta = amount
    }
  })

  return true
end

function MZInventoryService.setPlayerSlot(source, slot, item, amount, metadata)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then return false, err end

  local def = getItemDefinition(item)
  if not def then return false, 'item_not_found' end

  slot = tonumber(slot)
  amount = tonumber(amount) or 1

  if not slot or slot < 1 or slot > ctx.maxSlots then
    return false, 'invalid_slot'
  end

  local finalMetadata = def.unique and buildItemMetadata(def, metadata, ctx.player.citizenid, item) or (metadata or {})

  MZInventoryRepository.setSlot({
    owner_type = ctx.ownerType,
    owner_id = ctx.ownerId,
    inventory_type = ctx.inventoryType,
    slot = slot,
    item = item,
    amount = def.unique and 1 or amount,
    metadata = finalMetadata,
    instance_uid = finalMetadata.uid
  })

  return true
end

function MZInventoryService.clearPlayerSlot(source, slot)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then return false, err end

  MZInventoryRepository.deleteSlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, tonumber(slot))
  return true
end

function MZInventoryService.movePlayerSlot(source, fromSlot, toSlot, amount)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then
    return false, err
  end

  fromSlot = tonumber(fromSlot)
  toSlot = tonumber(toSlot)
  amount = tonumber(amount)

  if not isValidSlotNumber(fromSlot, ctx.maxSlots) or not isValidSlotNumber(toSlot, ctx.maxSlots) then
    return false, 'invalid_slot'
  end

  if fromSlot == toSlot then
    return false, 'same_slot'
  end

  local fromRow = MZInventoryRepository.getSlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, fromSlot)
  if not fromRow then
    return false, 'source_slot_empty'
  end

  local toRow = MZInventoryRepository.getSlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, toSlot)
  local itemDef = getItemDefinition(fromRow.item)
  if not itemDef then
    return false, 'item_not_found'
  end

  local fromAmount = tonumber(fromRow.amount) or 0
  if fromAmount <= 0 then
    return false, 'invalid_source_amount'
  end

  if itemDef.unique then
    amount = 1
  else
    if amount == nil then
      amount = fromAmount
    end

    if amount <= 0 or amount > fromAmount then
      return false, 'invalid_amount'
    end
  end

  if not toRow then
    if itemDef.unique or amount >= fromAmount then
      MZInventoryRepository.deleteSlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, fromSlot)

      MZInventoryRepository.setSlot({
        owner_type = ctx.ownerType,
        owner_id = ctx.ownerId,
        inventory_type = ctx.inventoryType,
        slot = toSlot,
        item = fromRow.item,
        amount = itemDef.unique and 1 or fromRow.amount,
        metadata = fromRow.metadata or {},
        instance_uid = fromRow.instance_uid
      })
    else
      MZInventoryRepository.updateAmountBySlot(
        ctx.ownerType,
        ctx.ownerId,
        ctx.inventoryType,
        fromSlot,
        fromAmount - amount
      )

      MZInventoryRepository.setSlot({
        owner_type = ctx.ownerType,
        owner_id = ctx.ownerId,
        inventory_type = ctx.inventoryType,
        slot = toSlot,
        item = fromRow.item,
        amount = amount,
        metadata = fromRow.metadata or {},
        instance_uid = fromRow.instance_uid
      })
    end

    logInventoryAction('move_slot', source, ctx.player, ctx, {
      before = {
        from_slot = buildSlotSnapshot(fromRow, fromSlot),
        to_slot = buildSlotSnapshot(toRow, toSlot)
      },
      after = {
        to_slot = buildSlotSnapshot({ item = fromRow.item, amount = amount, metadata = fromRow.metadata, instance_uid = fromRow.instance_uid }, toSlot)
      },
      meta = {
        item = fromRow.item,
        requested_amount = amount
      }
    })

    return true
  end

  if canMergeRows(itemDef, fromRow, toRow) then
    local toAmount = tonumber(toRow.amount) or 0

    if amount >= fromAmount then
      MZInventoryRepository.updateAmountBySlot(
        ctx.ownerType,
        ctx.ownerId,
        ctx.inventoryType,
        toSlot,
        toAmount + fromAmount
      )

      MZInventoryRepository.deleteSlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, fromSlot)
    else
      MZInventoryRepository.updateAmountBySlot(
        ctx.ownerType,
        ctx.ownerId,
        ctx.inventoryType,
        fromSlot,
        fromAmount - amount
      )

      MZInventoryRepository.updateAmountBySlot(
        ctx.ownerType,
        ctx.ownerId,
        ctx.inventoryType,
        toSlot,
        toAmount + amount
      )
    end

    logInventoryAction('merge_slot', source, ctx.player, ctx, {
      before = {
        from_slot = buildSlotSnapshot(fromRow, fromSlot),
        to_slot = buildSlotSnapshot(toRow, toSlot)
      },
      after = {
        to_slot = buildSlotSnapshot({ item = fromRow.item, amount = toAmount + math.min(amount, fromAmount), metadata = toRow.metadata, instance_uid = toRow.instance_uid }, toSlot)
      },
      meta = {
        item = fromRow.item,
        requested_amount = amount
      }
    })

    return true
  end

  if amount < fromAmount then
    return false, 'partial_move_blocked'
  end

  MZInventoryRepository.deleteSlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, fromSlot)
  MZInventoryRepository.deleteSlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, toSlot)

  MZInventoryRepository.setSlot({
    owner_type = ctx.ownerType,
    owner_id = ctx.ownerId,
    inventory_type = ctx.inventoryType,
    slot = fromSlot,
    item = toRow.item,
    amount = toRow.amount,
    metadata = toRow.metadata or {},
    instance_uid = toRow.instance_uid
  })

  MZInventoryRepository.setSlot({
    owner_type = ctx.ownerType,
    owner_id = ctx.ownerId,
    inventory_type = ctx.inventoryType,
    slot = toSlot,
    item = fromRow.item,
    amount = fromRow.amount,
    metadata = fromRow.metadata or {},
    instance_uid = fromRow.instance_uid
  })

  logInventoryAction('swap_slot', source, ctx.player, ctx, {
    before = {
      from_slot = buildSlotSnapshot(fromRow, fromSlot),
      to_slot = buildSlotSnapshot(toRow, toSlot)
    },
    after = {
      from_slot = buildSlotSnapshot(toRow, fromSlot),
      to_slot = buildSlotSnapshot(fromRow, toSlot)
    },
    meta = {
      from_item = fromRow.item,
      to_item = toRow.item
    }
  })

  return true
end

function MZInventoryService.setPlayerSlotMetadata(source, slot, metadata, mode)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then
    return false, err
  end

  slot = tonumber(slot)
  if not isValidSlotNumber(slot, ctx.maxSlots) then
    return false, 'invalid_slot'
  end

  local row = MZInventoryRepository.getSlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, slot)
  if not row then
    return false, 'slot_empty'
  end

  local itemDef = getItemDefinition(row.item)
  if not itemDef then
    return false, 'item_not_found'
  end

  metadata = normalizeMetadataTable(metadata)
  mode = tostring(mode or 'merge'):lower()

  local currentMetadata = normalizeMetadataTable(row.metadata)
  local nextMetadata = {}

  if mode == 'replace' then
    nextMetadata = metadata
  elseif mode == 'merge' then
    for k, v in pairs(currentMetadata) do
      nextMetadata[k] = v
    end

    for k, v in pairs(metadata) do
      nextMetadata[k] = v
    end
  else
    return false, 'invalid_mode'
  end

  if row.instance_uid and not nextMetadata.uid then
    nextMetadata.uid = row.instance_uid
  end

  MZInventoryRepository.updateMetadataBySlot(
    ctx.ownerType,
    ctx.ownerId,
    ctx.inventoryType,
    slot,
    nextMetadata
  )

  logInventoryAction('set_slot_metadata', source, ctx.player, ctx, {
    before = {
      slot = buildSlotSnapshot(row, slot)
    },
    after = {
      slot = buildSlotSnapshot({ item = row.item, amount = row.amount, metadata = nextMetadata, instance_uid = row.instance_uid }, slot)
    },
    meta = {
      item = row.item,
      mode = mode
    }
  })

  return true, nextMetadata
end

function MZInventoryService.usePlayerItem(source, slot)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then
    return false, err
  end

  slot = tonumber(slot)
  if not isValidSlotNumber(slot, ctx.maxSlots) then
    return false, 'invalid_slot'
  end

  local row = MZInventoryRepository.getSlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, slot)
  if not row then
    return false, 'slot_empty'
  end

  local itemDef = getItemDefinition(row.item)
  if not itemDef then
    return false, 'item_not_found'
  end

  local handler = ItemUseHandlers[row.item]
  if not handler then
    return false, 'item_not_usable'
  end

  local payload = {
    source = source,
    slot = slot,
    item = row.item,
    amount = tonumber(row.amount) or 0,
    metadata = normalizeMetadataTable(row.metadata),
    definition = itemDef,
    player = ctx.player
  }

  local okCall, handlerResult = pcall(handler, payload)
  if not okCall then
    return false, 'use_handler_failed'
  end

  local result = normalizeUseResult(handlerResult)
  if not result.ok then
    return false, result.error or 'use_failed'
  end

  if result.consume then
    local consumeAmount = tonumber(result.amount) or 1
    if consumeAmount <= 0 then
      consumeAmount = 1
    end

    local currentAmount = tonumber(row.amount) or 0
    if currentAmount <= consumeAmount then
      MZInventoryRepository.deleteSlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, slot)
    else
      MZInventoryRepository.updateAmountBySlot(
        ctx.ownerType,
        ctx.ownerId,
        ctx.inventoryType,
        slot,
        currentAmount - consumeAmount
      )
    end
  end

  logInventoryAction('use_item', source, ctx.player, ctx, {
    before = {
      slot = buildSlotSnapshot(row, slot)
    },
    after = {
      slot = buildSlotSnapshot({ item = row.item, amount = result.consume and math.max((tonumber(row.amount) or 0) - (tonumber(result.amount) or 1), 0) or (tonumber(row.amount) or 0), metadata = row.metadata, instance_uid = row.instance_uid }, slot)
    },
    meta = {
      item = row.item,
      consume = result.consume == true,
      amount = result.amount or 1,
      handler_data = cloneTable(result.data or {})
    }
  })

  return true, result
end

MZInventoryService.registerItemUseHandler('water', function(payload)
  return {
    ok = true,
    consume = true,
    amount = 1
  }
end)

MZInventoryService.registerItemUseHandler('radio', function(payload)
  return {
    ok = true,
    consume = false,
    data = {
      opened = true,
      channel = payload.metadata.channel
    }
  }
end)
