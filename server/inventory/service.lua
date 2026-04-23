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

local function normalizeStorageNumber(value)
  value = tonumber(value)
  if not value or value <= 0 then
    return nil
  end

  return math.floor(value)
end

local function normalizeStorageSection(section)
  if type(section) ~= 'table' then
    return nil
  end

  local slots = normalizeStorageNumber(section.slots)
  local weight = normalizeStorageNumber(section.weight)
  if not slots or not weight then
    return nil
  end

  return {
    slots = slots,
    weight = weight
  }
end

local function getCoreVehicleStorageFallback()
  local inventoryConfig = Config.Inventory or {}
  local trunkConfig = inventoryConfig.trunk or {}
  local gloveboxConfig = inventoryConfig.glovebox or {}

  return {
    trunk = {
      slots = tonumber(trunkConfig.slots) or 30,
      weight = tonumber(trunkConfig.weight) or 120000
    },
    glovebox = {
      slots = tonumber(gloveboxConfig.slots) or 8,
      weight = tonumber(gloveboxConfig.weight) or 15000
    },
    resolved_by = 'fallback',
    category = nil
  }
end

local function logCoreVehicleStorageResolution(stage, inventoryType, vehicle, storageProfile)
  vehicle = type(vehicle) == 'table' and vehicle or {}
  storageProfile = type(storageProfile) == 'table' and storageProfile or {}

  local trunk = type(storageProfile.trunk) == 'table' and storageProfile.trunk or {}
  local glovebox = type(storageProfile.glovebox) == 'table' and storageProfile.glovebox or {}

  print(('[mz_core][vehicle_storage][%s] inventory_type=%s | model=%s | category=%s | resolved_by=%s | trunk.slots=%s | trunk.weight=%s | glovebox.slots=%s | glovebox.weight=%s'):format(
    tostring(stage or 'snapshot'),
    tostring(inventoryType or ''),
    tostring(vehicle.model or ''),
    tostring(storageProfile.category or ''),
    tostring(storageProfile.resolved_by or ''),
    tostring(trunk.slots or ''),
    tostring(trunk.weight or ''),
    tostring(glovebox.slots or ''),
    tostring(glovebox.weight or '')
  ))
end

local function canUseVehicleStorageExports()
  return GetResourceState('mz_vehicles') == 'started'
end

local function resolveVehicleStorageFromDomain(model)
  local normalizedModel = tostring(model or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
  if normalizedModel == '' or not canUseVehicleStorageExports() then
    return nil
  end

  local ok, storageProfile = pcall(function()
    return exports['mz_vehicles']:ResolveVehicleStorage(normalizedModel)
  end)

  if not ok or type(storageProfile) ~= 'table' then
    return nil
  end

  local trunk = normalizeStorageSection(storageProfile.trunk)
  local glovebox = normalizeStorageSection(storageProfile.glovebox)
  if not trunk or not glovebox then
    return nil
  end

  return {
    trunk = trunk,
    glovebox = glovebox,
    resolved_by = tostring(storageProfile.resolved_by or 'category'),
    category = storageProfile.category and tostring(storageProfile.category) or nil
  }
end

local function getVehicleStorageProfile(vehicle)
  local storageProfile = resolveVehicleStorageFromDomain(type(vehicle) == 'table' and vehicle.model or nil)
  if storageProfile then
    logCoreVehicleStorageResolution('resolved', 'vehicle', vehicle, storageProfile)
    return storageProfile
  end

  local fallbackProfile = getCoreVehicleStorageFallback()
  logCoreVehicleStorageResolution('resolved', 'vehicle', vehicle, fallbackProfile)
  return fallbackProfile
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

  local storageProfile = getVehicleStorageProfile(vehicleOrErr)
  logCoreVehicleStorageResolution('context', 'trunk', vehicleOrErr, storageProfile)

  return {
    label = 'vehicle_trunk',
    ownerType = 'vehicle',
    ownerId = plate,
    inventoryType = 'trunk',
    maxSlots = storageProfile.trunk.slots,
    maxWeight = storageProfile.trunk.weight,
    vehicle = vehicleOrErr,
    storage = storageProfile
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

  local storageProfile = getVehicleStorageProfile(vehicleOrErr)
  logCoreVehicleStorageResolution('context', 'glovebox', vehicleOrErr, storageProfile)

  return {
    label = 'vehicle_glovebox',
    ownerType = 'vehicle',
    ownerId = plate,
    inventoryType = 'glovebox',
    maxSlots = storageProfile.glovebox.slots,
    maxWeight = storageProfile.glovebox.weight,
    vehicle = vehicleOrErr,
    storage = storageProfile
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

local InventoryMutationLocks = {}
local InventoryMutationLockTimeoutMs = 5000

local function buildContainerLockKey(ctx)
  return ('%s:%s:%s'):format(
    tostring(ctx and ctx.ownerType or ''),
    tostring(ctx and ctx.ownerId or ''),
    tostring(ctx and ctx.inventoryType or '')
  )
end

local function isSameInventoryContext(leftCtx, rightCtx)
  return leftCtx ~= nil
    and rightCtx ~= nil
    and tostring(leftCtx.ownerType or '') == tostring(rightCtx.ownerType or '')
    and tostring(leftCtx.ownerId or '') == tostring(rightCtx.ownerId or '')
    and tostring(leftCtx.inventoryType or '') == tostring(rightCtx.inventoryType or '')
end

local function collectDeterministicLockKeys(contexts)
  local keys = {}
  local seen = {}

  for _, ctx in ipairs(contexts or {}) do
    if ctx then
      local key = buildContainerLockKey(ctx)
      if key ~= '' and not seen[key] then
        seen[key] = true
        keys[#keys + 1] = key
      end
    end
  end

  table.sort(keys)
  return keys
end

local function acquireContainerLocks(contexts)
  local keys = collectDeterministicLockKeys(contexts)
  local token = {}
  local acquired = {}
  local deadline = GetGameTimer() + InventoryMutationLockTimeoutMs

  for _, key in ipairs(keys) do
    while InventoryMutationLocks[key] ~= nil do
      if GetGameTimer() >= deadline then
        for _, acquiredKey in ipairs(acquired) do
          if InventoryMutationLocks[acquiredKey] == token then
            InventoryMutationLocks[acquiredKey] = nil
          end
        end

        return nil, 'inventory_busy'
      end

      Wait(0)
    end

    InventoryMutationLocks[key] = token
    acquired[#acquired + 1] = key
  end

  return {
    token = token,
    keys = acquired
  }
end

local function releaseContainerLocks(lockHandle)
  if type(lockHandle) ~= 'table' then
    return
  end

  for index = #(lockHandle.keys or {}), 1, -1 do
    local key = lockHandle.keys[index]
    if InventoryMutationLocks[key] == lockHandle.token then
      InventoryMutationLocks[key] = nil
    end
  end
end

local function executeInventoryMutation(actorPlayer, contexts, mutationName, buildPlan)
  local lockHandle, lockErr = acquireContainerLocks(contexts)
  if not lockHandle then
    return false, lockErr
  end

  local ok, planOrFalse, planErr = xpcall(function()
    return buildPlan()
  end, debug.traceback)

  if not ok then
    releaseContainerLocks(lockHandle)
    print(('[mz_core][inventory][mutation_failed] mutation=%s | error=%s'):format(
      tostring(mutationName or 'unknown'),
      tostring(planOrFalse or 'unknown')
    ))
    return false, 'inventory_mutation_failed'
  end

  if planOrFalse == false then
    releaseContainerLocks(lockHandle)
    return false, planErr
  end

  local plan = type(planOrFalse) == 'table' and planOrFalse or {}
  local statements = type(plan.statements) == 'table' and plan.statements or {}

  if #statements > 0 then
    local transactionOk, transactionErr = MZInventoryRepository.runTransaction(statements)
    if not transactionOk then
      releaseContainerLocks(lockHandle)
      print(('[mz_core][inventory][transaction_failed] mutation=%s | error=%s'):format(
        tostring(mutationName or 'unknown'),
        tostring(transactionErr or 'inventory_transaction_failed')
      ))
      return false, transactionErr or 'inventory_transaction_failed'
    end
  end

  if type(plan.afterCommit) == 'function' then
    local commitHookOk, commitHookErr = pcall(plan.afterCommit)
    if not commitHookOk then
      print(('[mz_core][inventory][after_commit_failed] mutation=%s | error=%s'):format(
        tostring(mutationName or 'unknown'),
        tostring(commitHookErr or 'unknown')
      ))
    end
  end

  releaseContainerLocks(lockHandle)

  if actorPlayer and plan.logAction then
    logInventoryAction(
      plan.logAction,
      actorPlayer.source,
      actorPlayer,
      plan.logTargetCtx or plan.targetCtx or contexts[1],
      plan.logPayload or {}
    )
  end

  if plan.result ~= nil then
    return true, plan.result
  end

  return true
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

local function getRowsWeight(rows)
  local total = 0

  for _, row in ipairs(rows or {}) do
    total = total + computeRowWeight(row)
  end

  return total
end

local function canCarryRows(rows, itemName, amount, maxWeight, removedWeight)
  local def = getItemDefinition(itemName)
  if not def then
    return false, 'item_not_found'
  end

  local currentWeight = getRowsWeight(rows)
  local deltaWeight = (tonumber(def.weight) or 0) * (tonumber(amount) or 0)
  local nextWeight = currentWeight - (tonumber(removedWeight) or 0) + deltaWeight

  if nextWeight > maxWeight then
    return false, 'inventory_full'
  end

  return true
end

local function metadataMatches(leftMetadata, rightMetadata)
  return json.encode(leftMetadata or {}) == json.encode(rightMetadata or {})
end

local function findRowBySlot(rows, slot)
  slot = tonumber(slot)

  for _, row in ipairs(rows or {}) do
    if tonumber(row.slot) == slot then
      return row
    end
  end

  return nil
end

local function buildUsedSlotLookup(rows)
  local used = {}

  for _, row in ipairs(rows or {}) do
    local slot = tonumber(row.slot)
    if slot then
      used[slot] = true
    end
  end

  return used
end

local function findFreeSlotInRows(rows, maxSlots, usedSlots)
  usedSlots = usedSlots or buildUsedSlotLookup(rows)

  for slot = 1, maxSlots do
    if not usedSlots[slot] then
      return slot
    end
  end

  return nil
end

local function buildTransactionSetRow(ctx, slot, itemName, amount, metadata, instanceUid)
  return MZInventoryRepository.buildSetSlotStatement({
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

local function buildTransactionDeleteRow(ctx, slot)
  return MZInventoryRepository.buildDeleteSlotStatement(ctx.ownerType, ctx.ownerId, ctx.inventoryType, slot)
end

local function buildTransactionUpdateAmount(ctx, slot, amount)
  return MZInventoryRepository.buildUpdateAmountBySlotStatement(ctx.ownerType, ctx.ownerId, ctx.inventoryType, slot, amount)
end

local function buildTransactionUpdateMetadata(ctx, slot, metadata)
  return MZInventoryRepository.buildUpdateMetadataBySlotStatement(ctx.ownerType, ctx.ownerId, ctx.inventoryType, slot, metadata)
end

local function buildTransferLogContext(fromCtx, toCtx, fromSlot, toSlot, mode)
  return {
    from_inventory = buildInventoryContext(fromCtx, { slot = tonumber(fromSlot) or fromSlot }),
    to_inventory = buildInventoryContext(toCtx, { slot = tonumber(toSlot) or toSlot }),
    mode = tostring(mode or '')
  }
end

local function canStackRows(itemDef, fromRow, toRow)
  if not itemDef or itemDef.unique or not itemDef.stack then
    return false
  end

  if not fromRow or not toRow then
    return false
  end

  if tostring(fromRow.item or '') ~= tostring(toRow.item or '') then
    return false
  end

  return metadataMatches(fromRow.metadata or {}, toRow.metadata or {})
end

local function findStackableRowInRows(rows, itemName, metadata, ignoredSlot)
  local itemDef = getItemDefinition(itemName)
  local probeRow = {
    item = itemName,
    metadata = metadata or {}
  }

  for _, row in ipairs(rows or {}) do
    if tonumber(row.slot) ~= tonumber(ignoredSlot) and canStackRows(itemDef, probeRow, row) then
      return row
    end
  end

  return nil
end

local function buildMoveOperationPlan(fromCtx, toCtx, fromRow, fromSlot, toSlot, movedAmount, isSplit)
  local sameInventory = isSameInventoryContext(fromCtx, toCtx)
  local fromAmount = tonumber(fromRow.amount) or 0
  local statements = {}
  local afterFromRow = nil

  if isSplit then
    afterFromRow = {
      item = fromRow.item,
      amount = fromAmount - movedAmount,
      metadata = cloneTable(fromRow.metadata or {}),
      instance_uid = fromRow.instance_uid
    }

    statements[#statements + 1] = buildTransactionUpdateAmount(fromCtx, fromSlot, fromAmount - movedAmount)
  else
    statements[#statements + 1] = buildTransactionDeleteRow(fromCtx, fromSlot)
  end

  statements[#statements + 1] = buildTransactionSetRow(
    toCtx,
    toSlot,
    fromRow.item,
    movedAmount,
    fromRow.metadata or {},
    fromRow.instance_uid
  )

  return {
    statements = statements,
    logAction = isSplit
      and (sameInventory and 'split_slot' or 'split_between_inventories')
      or (sameInventory and 'move_slot' or 'move_between_inventories'),
    logTargetCtx = sameInventory and fromCtx or toCtx,
    logPayload = {
      context = buildTransferLogContext(
        fromCtx,
        toCtx,
        fromSlot,
        toSlot,
        isSplit and 'split' or 'move'
      ),
      before = {
        from_slot = buildSlotSnapshot(fromRow, fromSlot),
        to_slot = buildSlotSnapshot(nil, toSlot)
      },
      after = {
        from_slot = buildSlotSnapshot(afterFromRow, fromSlot),
        to_slot = buildSlotSnapshot({
          item = fromRow.item,
          amount = movedAmount,
          metadata = fromRow.metadata,
          instance_uid = fromRow.instance_uid
        }, toSlot)
      },
      meta = {
        requested_amount = movedAmount,
        item = fromRow.item,
        operation = isSplit and 'split' or 'move'
      }
    },
    result = {
      operation = isSplit and 'split' or 'move',
      to_slot = tonumber(toSlot) or toSlot
    }
  }
end

local function buildMergeOperationPlan(fromCtx, toCtx, fromRow, toRow, fromSlot, toSlot, movedAmount)
  local sameInventory = isSameInventoryContext(fromCtx, toCtx)
  local fromAmount = tonumber(fromRow.amount) or 0
  local toAmount = tonumber(toRow.amount) or 0
  local statements = {}
  local afterFromRow = nil

  if movedAmount >= fromAmount then
    statements[#statements + 1] = buildTransactionDeleteRow(fromCtx, fromSlot)
  else
    afterFromRow = {
      item = fromRow.item,
      amount = fromAmount - movedAmount,
      metadata = cloneTable(fromRow.metadata or {}),
      instance_uid = fromRow.instance_uid
    }

    statements[#statements + 1] = buildTransactionUpdateAmount(fromCtx, fromSlot, fromAmount - movedAmount)
  end

  statements[#statements + 1] = buildTransactionUpdateAmount(toCtx, toSlot, toAmount + movedAmount)

  return {
    statements = statements,
    logAction = sameInventory and 'merge_slot' or 'merge_between_inventories',
    logTargetCtx = sameInventory and fromCtx or toCtx,
    logPayload = {
      context = buildTransferLogContext(fromCtx, toCtx, fromSlot, toSlot, 'merge'),
      before = {
        from_slot = buildSlotSnapshot(fromRow, fromSlot),
        to_slot = buildSlotSnapshot(toRow, toSlot)
      },
      after = {
        from_slot = buildSlotSnapshot(afterFromRow, fromSlot),
        to_slot = buildSlotSnapshot({
          item = toRow.item,
          amount = toAmount + movedAmount,
          metadata = toRow.metadata,
          instance_uid = toRow.instance_uid
        }, toSlot)
      },
      meta = {
        requested_amount = movedAmount,
        item = fromRow.item,
        operation = 'merge'
      }
    },
    result = {
      operation = 'merge',
      to_slot = tonumber(toSlot) or toSlot
    }
  }
end

local function buildSwapOperationPlan(fromCtx, toCtx, fromRow, toRow, fromSlot, toSlot)
  local sameInventory = isSameInventoryContext(fromCtx, toCtx)

  return {
    statements = {
      buildTransactionDeleteRow(fromCtx, fromSlot),
      buildTransactionDeleteRow(toCtx, toSlot),
      buildTransactionSetRow(
        fromCtx,
        fromSlot,
        toRow.item,
        tonumber(toRow.amount) or 0,
        toRow.metadata or {},
        toRow.instance_uid
      ),
      buildTransactionSetRow(
        toCtx,
        toSlot,
        fromRow.item,
        tonumber(fromRow.amount) or 0,
        fromRow.metadata or {},
        fromRow.instance_uid
      )
    },
    logAction = sameInventory and 'swap_slot' or 'swap_between_inventories',
    logTargetCtx = sameInventory and fromCtx or toCtx,
    logPayload = {
      context = buildTransferLogContext(fromCtx, toCtx, fromSlot, toSlot, 'swap'),
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
        to_item = toRow.item,
        operation = 'swap'
      }
    },
    result = {
      operation = 'swap',
      to_slot = tonumber(toSlot) or toSlot
    }
  }
end

local function planSlotTransferMutation(fromCtx, toCtx, fromSlot, toSlot, amount, options)
  options = type(options) == 'table' and options or {}
  fromSlot = tonumber(fromSlot)
  toSlot = tonumber(toSlot)
  amount = tonumber(amount)

  if not isValidSlotNumber(fromSlot, fromCtx.maxSlots) then
    return false, 'invalid_from_slot'
  end

  if not isValidSlotNumber(toSlot, toCtx.maxSlots) then
    return false, 'invalid_to_slot'
  end

  if isSameInventoryContext(fromCtx, toCtx) and fromSlot == toSlot then
    return false, 'same_slot'
  end

  local sameInventory = isSameInventoryContext(fromCtx, toCtx)
  local fromRows = getInventoryRowsFromContext(fromCtx)
  local toRows = sameInventory and fromRows or getInventoryRowsFromContext(toCtx)

  local fromRow = findRowBySlot(fromRows, fromSlot)
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

  local forcedOperation = tostring(options.forcedOperation or ''):lower()
  local resolvedToSlot = tonumber(toSlot) or toSlot
  local toRow = findRowBySlot(toRows, resolvedToSlot)

  if forcedOperation == '' and not toRow and amount < fromAmount then
    local stackableRow = findStackableRowInRows(toRows, fromRow.item, fromRow.metadata or {}, resolvedToSlot)
    if stackableRow and tonumber(stackableRow.slot) ~= tonumber(resolvedToSlot) then
      resolvedToSlot = tonumber(stackableRow.slot) or stackableRow.slot
      toRow = stackableRow
    end
  end

  if forcedOperation == 'split' then
    if itemDef.unique or amount >= fromAmount then
      return false, 'invalid_split_amount'
    end

    if toRow then
      return false, 'split_requires_empty_slot'
    end
  end

  if forcedOperation == 'merge' and (not toRow or not canStackRows(itemDef, fromRow, toRow)) then
    return false, 'merge_not_allowed'
  end

  if forcedOperation == 'swap' then
    if not toRow then
      return false, 'swap_target_missing'
    end

    if amount < fromAmount then
      return false, 'swap_requires_full_stack'
    end
  end

  local operation = nil

  if forcedOperation == 'split' then
    operation = 'split'
  elseif forcedOperation == 'merge' then
    operation = 'merge'
  elseif forcedOperation == 'swap' then
    operation = 'swap'
  elseif not toRow then
    operation = amount < fromAmount and 'split' or 'move'
  elseif canStackRows(itemDef, fromRow, toRow) then
    operation = 'merge'
  else
    if amount < fromAmount then
      return false, 'partial_move_blocked'
    end

    operation = 'swap'
  end

  if not sameInventory then
    if operation == 'move' then
      local carryOk, carryErr = canCarryRows(
        toRows,
        fromRow.item,
        itemDef.unique and 1 or fromAmount,
        toCtx.maxWeight
      )
      if not carryOk then
        return false, carryErr
      end
    elseif operation == 'split' or operation == 'merge' then
      local carryOk, carryErr = canCarryRows(
        toRows,
        fromRow.item,
        amount,
        toCtx.maxWeight
      )
      if not carryOk then
        return false, carryErr
      end
    elseif operation == 'swap' then
      local fromRowWeight = computeRowWeight(fromRow)
      local toRowWeight = computeRowWeight(toRow)

      local toCarryOk, toCarryErr = canCarryRows(
        toRows,
        fromRow.item,
        tonumber(fromRow.amount) or 0,
        toCtx.maxWeight,
        toRowWeight
      )
      if not toCarryOk then
        return false, toCarryErr
      end

      local fromCarryOk, fromCarryErr = canCarryRows(
        fromRows,
        toRow.item,
        tonumber(toRow.amount) or 0,
        fromCtx.maxWeight,
        fromRowWeight
      )
      if not fromCarryOk then
        return false, fromCarryErr
      end
    end
  end

  if operation == 'move' then
    return buildMoveOperationPlan(
      fromCtx,
      toCtx,
      fromRow,
      fromSlot,
      resolvedToSlot,
      itemDef.unique and 1 or fromAmount,
      false
    )
  end

  if operation == 'split' then
    return buildMoveOperationPlan(
      fromCtx,
      toCtx,
      fromRow,
      fromSlot,
      resolvedToSlot,
      amount,
      true
    )
  end

  if operation == 'merge' then
    return buildMergeOperationPlan(fromCtx, toCtx, fromRow, toRow, fromSlot, resolvedToSlot, amount)
  end

  return buildSwapOperationPlan(fromCtx, toCtx, fromRow, toRow, fromSlot, resolvedToSlot)
end

local function moveBetweenContexts(actorPlayer, fromCtx, toCtx, fromSlot, toSlot, amount, options)
  return executeInventoryMutation(actorPlayer, { fromCtx, toCtx }, 'move_between_contexts', function()
    local plan, err = planSlotTransferMutation(fromCtx, toCtx, fromSlot, toSlot, amount, options)
    if not plan then
      return false, err
    end

    if type(options) == 'table' and type(options.afterCommit) == 'function' then
      plan.afterCommit = options.afterCommit
    end

    return plan
  end)
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

local function buildAddItemMutationPlan(ctx, itemName, amount, metadata)
  local itemDef = getItemDefinition(itemName)
  if not itemDef then
    return false, 'item_not_found'
  end

  amount = tonumber(amount) or 1
  if amount <= 0 then
    return false, 'invalid_amount'
  end

  local rows = getInventoryRowsFromContext(ctx)
  local carryOk, carryErr = canCarryRows(rows, itemName, amount, ctx.maxWeight)
  if not carryOk then
    return false, carryErr
  end

  metadata = normalizeMetadataTable(metadata)

  if itemDef.unique then
    local uniqueCount = math.floor(amount)
    if uniqueCount <= 0 then
      return false, 'invalid_amount'
    end

    local usedSlots = buildUsedSlotLookup(rows)
    local statements = {}
    local addedSlots = {}

    for _ = 1, uniqueCount do
      local slot = findFreeSlotInRows(rows, ctx.maxSlots, usedSlots)
      if not slot then
        return false, 'no_free_slot'
      end

      usedSlots[slot] = true

      local finalMetadata = buildItemMetadata(itemDef, metadata, ctx.player.citizenid, itemName)
      statements[#statements + 1] = buildTransactionSetRow(
        ctx,
        slot,
        itemName,
        1,
        finalMetadata,
        finalMetadata.uid
      )
      addedSlots[#addedSlots + 1] = buildSlotSnapshot({
        item = itemName,
        amount = 1,
        metadata = finalMetadata,
        instance_uid = finalMetadata.uid
      }, slot)
    end

    return {
      statements = statements,
      logAction = 'add_unique_item',
      logTargetCtx = ctx,
      logPayload = {
        after = {
          slots = addedSlots
        },
        meta = {
          item = itemName,
          delta = uniqueCount,
          unique = true
        }
      }
    }
  end

  local stackRow = itemDef.stack and findStackableRowInRows(rows, itemName, metadata) or nil
  if stackRow then
    local nextAmount = (tonumber(stackRow.amount) or 0) + amount

    return {
      statements = {
        buildTransactionUpdateAmount(ctx, stackRow.slot, nextAmount)
      },
      logAction = 'stack_item',
      logTargetCtx = ctx,
      logPayload = {
        before = {
          slot = buildSlotSnapshot(stackRow, stackRow.slot)
        },
        after = {
          slot = buildSlotSnapshot({
            item = itemName,
            amount = nextAmount,
            metadata = stackRow.metadata,
            instance_uid = stackRow.instance_uid
          }, stackRow.slot)
        },
        meta = {
          item = itemName,
          delta = amount
        }
      }
    }
  end

  local slot = findFreeSlotInRows(rows, ctx.maxSlots)
  if not slot then
    return false, 'no_free_slot'
  end

  return {
    statements = {
      buildTransactionSetRow(ctx, slot, itemName, amount, metadata, nil)
    },
    logAction = 'add_item',
    logTargetCtx = ctx,
    logPayload = {
      after = {
        slot = buildSlotSnapshot({
          item = itemName,
          amount = amount,
          metadata = metadata
        }, slot)
      },
      meta = {
        item = itemName,
        delta = amount
      }
    }
  }
end

local function buildRemoveItemMutationPlan(ctx, itemName, amount)
  local itemDef = getItemDefinition(itemName)
  if not itemDef then
    return false, 'item_not_found'
  end

  amount = tonumber(amount) or 1
  if amount <= 0 then
    return false, 'invalid_amount'
  end

  local rows = getInventoryRowsFromContext(ctx)
  local matchingRows = {}
  local total = 0

  for _, row in ipairs(rows) do
    if tostring(row.item or '') == tostring(itemName) then
      matchingRows[#matchingRows + 1] = row
      total = total + (tonumber(row.amount) or 0)
    end
  end

  if total < amount then
    return false, 'not_enough_items'
  end

  local statements = {}
  local remaining = amount
  local beforeSlots = {}
  local afterSlots = {}

  for _, row in ipairs(matchingRows) do
    if remaining <= 0 then
      break
    end

    local rowAmount = tonumber(row.amount) or 0
    beforeSlots[#beforeSlots + 1] = buildSlotSnapshot(row, row.slot)

    if rowAmount <= remaining then
      statements[#statements + 1] = buildTransactionDeleteRow(ctx, row.slot)
      afterSlots[#afterSlots + 1] = buildSlotSnapshot(nil, row.slot)
      remaining = remaining - rowAmount
    else
      statements[#statements + 1] = buildTransactionUpdateAmount(ctx, row.slot, rowAmount - remaining)
      afterSlots[#afterSlots + 1] = buildSlotSnapshot({
        item = row.item,
        amount = rowAmount - remaining,
        metadata = row.metadata,
        instance_uid = row.instance_uid
      }, row.slot)
      remaining = 0
    end
  end

  return {
    statements = statements,
    logAction = 'remove_item',
    logTargetCtx = ctx,
    logPayload = {
      before = {
        slots = beforeSlots
      },
      after = {
        slots = afterSlots
      },
      meta = {
        item = itemName,
        delta = amount
      }
    }
  }
end

local function buildSetPlayerSlotMutationPlan(ctx, slot, itemName, amount, metadata)
  local itemDef = getItemDefinition(itemName)
  if not itemDef then
    return false, 'item_not_found'
  end

  slot = tonumber(slot)
  amount = tonumber(amount) or 1
  if not isValidSlotNumber(slot, ctx.maxSlots) then
    return false, 'invalid_slot'
  end

  if not itemDef.unique and amount <= 0 then
    return false, 'invalid_amount'
  end

  local finalMetadata = itemDef.unique
    and buildItemMetadata(itemDef, metadata, ctx.player.citizenid, itemName)
    or normalizeMetadataTable(metadata)

  local rowAmount = itemDef.unique and 1 or amount

  return {
    statements = {
      buildTransactionSetRow(ctx, slot, itemName, rowAmount, finalMetadata, finalMetadata.uid)
    },
    logAction = 'set_slot',
    logTargetCtx = ctx,
    logPayload = {
      after = {
        slot = buildSlotSnapshot({
          item = itemName,
          amount = rowAmount,
          metadata = finalMetadata,
          instance_uid = finalMetadata.uid
        }, slot)
      },
      meta = {
        item = itemName
      }
    }
  }
end

local function buildClearPlayerSlotMutationPlan(ctx, slot)
  slot = tonumber(slot)
  if not isValidSlotNumber(slot, ctx.maxSlots) then
    return false, 'invalid_slot'
  end

  local row = findRowBySlot(getInventoryRowsFromContext(ctx), slot)

  return {
    statements = {
      buildTransactionDeleteRow(ctx, slot)
    },
    logAction = 'clear_slot',
    logTargetCtx = ctx,
    logPayload = {
      before = {
        slot = buildSlotSnapshot(row, slot)
      },
      after = {
        slot = buildSlotSnapshot(nil, slot)
      }
    }
  }
end

local function buildSetPlayerSlotMetadataMutationPlan(ctx, slot, metadata, mode)
  slot = tonumber(slot)
  if not isValidSlotNumber(slot, ctx.maxSlots) then
    return false, 'invalid_slot'
  end

  local row = findRowBySlot(getInventoryRowsFromContext(ctx), slot)
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

  return {
    statements = {
      buildTransactionUpdateMetadata(ctx, slot, nextMetadata)
    },
    logAction = 'set_slot_metadata',
    logTargetCtx = ctx,
    logPayload = {
      before = {
        slot = buildSlotSnapshot(row, slot)
      },
      after = {
        slot = buildSlotSnapshot({
          item = row.item,
          amount = row.amount,
          metadata = nextMetadata,
          instance_uid = row.instance_uid
        }, slot)
      },
      meta = {
        item = row.item,
        mode = mode
      }
    },
    result = nextMetadata
  }
end

local function buildUsePlayerItemMutationPlan(ctx, source, slot)
  slot = tonumber(slot)
  if not isValidSlotNumber(slot, ctx.maxSlots) then
    return false, 'invalid_slot'
  end

  local row = findRowBySlot(getInventoryRowsFromContext(ctx), slot)
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

  local statements = {}
  local afterSlot = buildSlotSnapshot(row, slot)

  if result.consume then
    local consumeAmount = tonumber(result.amount) or 1
    if consumeAmount <= 0 then
      consumeAmount = 1
    end

    local currentAmount = tonumber(row.amount) or 0
    if currentAmount <= consumeAmount then
      statements[#statements + 1] = buildTransactionDeleteRow(ctx, slot)
      afterSlot = buildSlotSnapshot(nil, slot)
    else
      statements[#statements + 1] = buildTransactionUpdateAmount(ctx, slot, currentAmount - consumeAmount)
      afterSlot = buildSlotSnapshot({
        item = row.item,
        amount = currentAmount - consumeAmount,
        metadata = row.metadata,
        instance_uid = row.instance_uid
      }, slot)
    end
  end

  return {
    statements = statements,
    logAction = 'use_item',
    logTargetCtx = ctx,
    logPayload = {
      before = {
        slot = buildSlotSnapshot(row, slot)
      },
      after = {
        slot = afterSlot
      },
      meta = {
        item = row.item,
        consume = result.consume == true,
        amount = result.amount or 1,
        handler_data = cloneTable(result.data or {})
      }
    },
    result = result
  }
end

local function moveWithinPlayerInventory(playerCtx, fromSlot, toSlot, amount, forcedOperation)
  return moveBetweenContexts(playerCtx.player, playerCtx, playerCtx, fromSlot, toSlot, amount, {
    forcedOperation = forcedOperation
  })
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

  local ok, result = moveBetweenContexts(playerCtx.player, dropCtx, playerCtx, fromSlot, toSlot, amount, {
    afterCommit = function()
      cleanupDropIfEmpty(dropUid)
    end
  })
  if not ok then
    return false, result
  end

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

  return executeInventoryMutation(ctx.player, { ctx }, 'add_player_item', function()
    return buildAddItemMutationPlan(ctx, itemName, amount, metadata)
  end)
end

function MZInventoryService.removePlayerItem(source, itemName, amount)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then return false, err end

  return executeInventoryMutation(ctx.player, { ctx }, 'remove_player_item', function()
    return buildRemoveItemMutationPlan(ctx, itemName, amount)
  end)
end

function MZInventoryService.setPlayerSlot(source, slot, item, amount, metadata)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then return false, err end

  return executeInventoryMutation(ctx.player, { ctx }, 'set_player_slot', function()
    return buildSetPlayerSlotMutationPlan(ctx, slot, item, amount, metadata)
  end)
end

function MZInventoryService.clearPlayerSlot(source, slot)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then return false, err end

  return executeInventoryMutation(ctx.player, { ctx }, 'clear_player_slot', function()
    return buildClearPlayerSlotMutationPlan(ctx, slot)
  end)
end

function MZInventoryService.movePlayerSlot(source, fromSlot, toSlot, amount)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then
    return false, err
  end

  return moveWithinPlayerInventory(ctx, fromSlot, toSlot, amount)
end

function MZInventoryService.canStackRows(fromRow, toRow)
  if type(fromRow) ~= 'table' or type(toRow) ~= 'table' then
    return false
  end

  local itemDef = getItemDefinition(fromRow.item)
  return canStackRows(itemDef, fromRow, toRow)
end

function MZInventoryService.splitPlayerSlot(source, fromSlot, toSlot, amount)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then
    return false, err
  end

  return moveWithinPlayerInventory(ctx, fromSlot, toSlot, amount, 'split')
end

function MZInventoryService.mergePlayerSlots(source, fromSlot, toSlot, amount)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then
    return false, err
  end

  return moveWithinPlayerInventory(ctx, fromSlot, toSlot, amount, 'merge')
end

function MZInventoryService.swapPlayerSlots(source, fromSlot, toSlot)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then
    return false, err
  end

  return moveWithinPlayerInventory(ctx, fromSlot, toSlot, nil, 'swap')
end

function MZInventoryService.setPlayerSlotMetadata(source, slot, metadata, mode)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then
    return false, err
  end

  return executeInventoryMutation(ctx.player, { ctx }, 'set_player_slot_metadata', function()
    return buildSetPlayerSlotMetadataMutationPlan(ctx, slot, metadata, mode)
  end)
end

function MZInventoryService.usePlayerItem(source, slot)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then
    return false, err
  end

  return executeInventoryMutation(ctx.player, { ctx }, 'use_player_item', function()
    return buildUsePlayerItemMutationPlan(ctx, source, slot)
  end)
end

local PublicInventoryErrors = {
  inventory_busy = { code = 'inventory_busy', message = 'Inventory is busy.' },
  invalid_container = { code = 'invalid_container', message = 'Invalid inventory container.' },
  invalid_slot = { code = 'invalid_slot', message = 'Invalid inventory slot.' },
  invalid_amount = { code = 'invalid_amount', message = 'Invalid item amount.' },
  item_not_found = { code = 'item_not_found', message = 'Item not found.' },
  not_enough_amount = { code = 'not_enough_amount', message = 'Not enough item amount.' },
  cannot_carry = { code = 'cannot_carry', message = 'Target inventory cannot carry this item.' },
  cannot_stack = { code = 'cannot_stack', message = 'Items cannot be stacked together.' },
  no_free_slot = { code = 'no_free_slot', message = 'No free slot available.' },
  container_access_denied = { code = 'container_access_denied', message = 'Access to this container was denied.' },
  container_not_found = { code = 'container_not_found', message = 'Inventory container was not found.' },
  invalid_target = { code = 'invalid_target', message = 'Invalid inventory target.' },
  item_not_usable = { code = 'item_not_usable', message = 'Item is not usable.' },
  use_failed = { code = 'use_failed', message = 'Item use failed.' },
  player_not_loaded = { code = 'player_not_loaded', message = 'Player inventory is not available yet.' },
  unknown_error = { code = 'unknown_error', message = 'Unknown inventory error.' }
}

local function mapPublicInventoryErrorCode(internalCode)
  internalCode = tostring(internalCode or '')

  if internalCode == '' then
    return 'unknown_error'
  end

  local mappings = {
    invalid_from_slot = 'invalid_slot',
    invalid_to_slot = 'invalid_target',
    source_slot_empty = 'invalid_slot',
    slot_empty = 'invalid_slot',
    invalid_source_amount = 'not_enough_amount',
    not_enough_items = 'not_enough_amount',
    inventory_full = 'cannot_carry',
    merge_not_allowed = 'cannot_stack',
    partial_move_blocked = 'invalid_target',
    split_requires_empty_slot = 'invalid_target',
    swap_target_missing = 'invalid_target',
    same_slot = 'invalid_target',
    invalid_plate = 'invalid_container',
    invalid_drop_uid = 'invalid_container',
    invalid_org = 'invalid_container',
    drop_not_found = 'container_not_found',
    vehicle_not_found = 'container_not_found',
    org_not_found = 'container_not_found',
    vehicle_access_denied = 'container_access_denied',
    not_in_org = 'container_access_denied',
    org_membership_required = 'container_access_denied',
    org_duty_required = 'container_access_denied',
    use_handler_failed = 'use_failed'
  }

  return mappings[internalCode] or internalCode
end

local function buildPublicInventoryError(internalCode, details)
  local publicCode = mapPublicInventoryErrorCode(internalCode)
  local errorDef = PublicInventoryErrors[publicCode] or PublicInventoryErrors.unknown_error

  return {
    ok = false,
    error = {
      code = errorDef.code,
      message = errorDef.message,
      internal_code = tostring(internalCode or publicCode),
      details = cloneTable(type(details) == 'table' and details or {})
    }
  }
end

local function buildPublicInventorySuccess(data)
  return {
    ok = true,
    data = data or {}
  }
end

local function normalizePublicContainerDescriptor(descriptor)
  if descriptor == nil then
    return {
      type = 'player'
    }
  end

  if type(descriptor) == 'string' then
    descriptor = { type = descriptor }
  end

  if type(descriptor) ~= 'table' then
    return nil, 'invalid_container'
  end

  local containerType = tostring(descriptor.type or descriptor.container_type or descriptor.kind or ''):lower()
  if containerType == '' then
    return nil, 'invalid_container'
  end

  local normalized = {
    type = containerType
  }

  if containerType == 'player' then
    normalized.scope = 'main'
    return normalized
  end

  if containerType == 'trunk' or containerType == 'glovebox' then
    normalized.plate = tostring(descriptor.plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
    if normalized.plate == '' then
      return nil, 'invalid_container'
    end

    return normalized
  end

  if containerType == 'drop' then
    normalized.drop_uid = tostring(descriptor.drop_uid or descriptor.dropUid or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if normalized.drop_uid == '' then
      return nil, 'invalid_container'
    end

    return normalized
  end

  if containerType == 'stash' then
    local scope = tostring(descriptor.scope or descriptor.stash_scope or descriptor.stash_type or 'personal'):lower()
    if scope ~= 'personal' and scope ~= 'org' then
      return nil, 'invalid_container'
    end

    normalized.scope = scope

    if scope == 'org' then
      normalized.org_code = tostring(descriptor.org_code or descriptor.orgCode or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
      if normalized.org_code == '' then
        return nil, 'invalid_container'
      end
    end

    return normalized
  end

  return nil, 'invalid_container'
end

local function resolvePublicContainerContext(source, descriptor)
  local normalized, normalizeErr = normalizePublicContainerDescriptor(descriptor)
  if not normalized then
    return nil, normalizeErr
  end

  local ctx, err = nil, nil

  if normalized.type == 'player' then
    ctx, err = getPlayerInventoryContext(source)
  elseif normalized.type == 'trunk' then
    ctx, err = getVehicleTrunkContext(source, normalized.plate)
  elseif normalized.type == 'glovebox' then
    ctx, err = getVehicleGloveboxContext(source, normalized.plate)
  elseif normalized.type == 'stash' then
    if normalized.scope == 'org' then
      ctx, err = getOrgStashContext(source, normalized.org_code)
    else
      ctx, err = getPersonalStashContext(source)
    end
  elseif normalized.type == 'drop' then
    ctx, err = getWorldDropContext(normalized.drop_uid)
  else
    return nil, 'invalid_container'
  end

  if not ctx then
    return nil, err or 'invalid_container'
  end

  return ctx, nil, normalized
end

local function buildPublicSlotPayload(row, slot)
  slot = tonumber(slot) or 0

  if not row then
    return {
      slot = slot,
      occupied = false,
      item_id = nil,
      label = nil,
      amount = 0,
      weight = 0,
      total_weight = 0,
      metadata = {},
      stack = false,
      usable = false,
      unique = false,
      instance_uid = nil
    }
  end

  local itemDef = getItemDefinition(row.item)
  local amount = tonumber(row.amount) or 0
  local unitWeight = itemDef and (tonumber(itemDef.weight) or 0) or 0

  return {
    slot = slot,
    occupied = true,
    item_id = tostring(row.item or ''),
    label = itemDef and tostring(itemDef.label or row.item or '') or tostring(row.item or ''),
    amount = amount,
    weight = unitWeight,
    total_weight = unitWeight * amount,
    metadata = cloneTable(type(row.metadata) == 'table' and row.metadata or {}),
    stack = itemDef and itemDef.stack == true or false,
    usable = itemDef and itemDef.usable == true or false,
    unique = itemDef and itemDef.unique == true or false,
    instance_uid = row.instance_uid and tostring(row.instance_uid) or nil
  }
end

local function buildPublicContainerPayload(ctx, descriptor, rows, currentWeight)
  rows = type(rows) == 'table' and rows or {}
  currentWeight = tonumber(currentWeight) or 0
  descriptor = type(descriptor) == 'table' and descriptor or {}

  local rowBySlot = {}
  for _, row in ipairs(rows) do
    local slot = tonumber(row.slot)
    if slot then
      rowBySlot[slot] = row
    end
  end

  local slots = {}
  for slot = 1, tonumber(ctx.maxSlots) or 0 do
    slots[#slots + 1] = buildPublicSlotPayload(rowBySlot[slot], slot)
  end

  return {
    container = {
      id = buildContainerLockKey(ctx),
      type = descriptor.type or ctx.ownerType,
      scope = descriptor.scope,
      label = tostring(ctx.label or ''),
      owner_type = tostring(ctx.ownerType or ''),
      owner_id = tostring(ctx.ownerId or ''),
      inventory_type = tostring(ctx.inventoryType or ''),
      slot_count = #rows,
      max_slots = tonumber(ctx.maxSlots) or 0,
      current_weight = currentWeight,
      max_weight = tonumber(ctx.maxWeight) or 0,
      plate = ctx.vehicle and tostring(ctx.vehicle.plate or '') or descriptor.plate,
      model = ctx.vehicle and tostring(ctx.vehicle.model or '') or nil,
      org_code = ctx.org and tostring(ctx.org.code or '') or descriptor.org_code,
      drop_uid = ctx.drop and tostring(ctx.drop.drop_uid or '') or descriptor.drop_uid,
      resolved_by = ctx.storage and tostring(ctx.storage.resolved_by or '') or nil,
      storage_category = ctx.storage and tostring(ctx.storage.category or '') or nil
    },
    slots = slots
  }
end

local function getPublicInventorySnapshot(source, descriptor)
  local ctx, err, normalized = resolvePublicContainerContext(source, descriptor)
  if not ctx then
    return false, err
  end

  local rows = getInventoryRowsFromContext(ctx)
  local currentWeight = getRowsWeight(rows)

  return true, buildPublicContainerPayload(ctx, normalized, rows, currentWeight), normalized
end

local function buildPublicTouchedSnapshots(source, descriptors)
  local snapshots = {}
  local dedupe = {}

  for key, descriptor in pairs(type(descriptors) == 'table' and descriptors or {}) do
    if descriptor ~= nil then
      local normalized, normalizeErr = normalizePublicContainerDescriptor(descriptor)
      if not normalized then
        return false, normalizeErr
      end

      local dedupeKey = ('%s|%s|%s|%s|%s'):format(
        tostring(normalized.type or ''),
        tostring(normalized.scope or ''),
        tostring(normalized.plate or ''),
        tostring(normalized.org_code or ''),
        tostring(normalized.drop_uid or '')
      )
      if not dedupe[dedupeKey] then
        local ok, snapshotOrErr = getPublicInventorySnapshot(source, normalized)
        if not ok then
          return false, snapshotOrErr
        end

        dedupe[dedupeKey] = snapshotOrErr
      end

      snapshots[key] = dedupe[dedupeKey]
    end
  end

  return true, snapshots
end

function MZInventoryService.openPlayerInventory(source)
  local ok, snapshotOrErr = getPublicInventorySnapshot(source, { type = 'player' })
  if not ok then
    return buildPublicInventoryError(snapshotOrErr, {
      container = {
        type = 'player'
      }
    })
  end

  return buildPublicInventorySuccess({
    snapshot = snapshotOrErr
  })
end

function MZInventoryService.openInventoryContainer(source, descriptor)
  local ok, snapshotOrErr, normalized = getPublicInventorySnapshot(source, descriptor)
  if not ok then
    return buildPublicInventoryError(snapshotOrErr, {
      container = cloneTable(type(descriptor) == 'table' and descriptor or { type = descriptor })
    })
  end

  return buildPublicInventorySuccess({
    snapshot = snapshotOrErr,
    container = normalized
  })
end

function MZInventoryService.getInventorySnapshot(source, descriptor)
  return MZInventoryService.openInventoryContainer(source, descriptor)
end

function MZInventoryService.getInventoryViewSnapshot(source, request)
  request = type(request) == 'table' and request or {}

  local playerDescriptor = request.player or request.primary or { type = 'player' }
  local targetDescriptor = request.target or request.secondary

  local playerOk, playerSnapshotOrErr = getPublicInventorySnapshot(source, playerDescriptor)
  if not playerOk then
    return buildPublicInventoryError(playerSnapshotOrErr, {
      container = cloneTable(type(playerDescriptor) == 'table' and playerDescriptor or { type = playerDescriptor })
    })
  end

  local targetSnapshot = nil
  if targetDescriptor ~= nil then
    local targetOk, targetSnapshotOrErr = getPublicInventorySnapshot(source, targetDescriptor)
    if not targetOk then
      return buildPublicInventoryError(targetSnapshotOrErr, {
        container = cloneTable(type(targetDescriptor) == 'table' and targetDescriptor or { type = targetDescriptor })
      })
    end

    targetSnapshot = targetSnapshotOrErr
  end

  return buildPublicInventorySuccess({
    player = playerSnapshotOrErr,
    target = targetSnapshot
  })
end

function MZInventoryService.moveInventoryItem(source, request)
  request = type(request) == 'table' and request or {}

  local fromDescriptor = request.from and request.from.container or request.from_container
  local toDescriptor = request.to and request.to.container or request.to_container
  local fromSlot = request.from and request.from.slot or request.from_slot
  local toSlot = request.to and request.to.slot or request.to_slot
  local amount = request.amount

  local fromCtx, fromErr = resolvePublicContainerContext(source, fromDescriptor)
  if not fromCtx then
    return buildPublicInventoryError(fromErr, {
      container = cloneTable(type(fromDescriptor) == 'table' and fromDescriptor or { type = fromDescriptor })
    })
  end

  local toCtx, toErr = resolvePublicContainerContext(source, toDescriptor)
  if not toCtx then
    return buildPublicInventoryError(toErr, {
      container = cloneTable(type(toDescriptor) == 'table' and toDescriptor or { type = toDescriptor })
    })
  end

  local actorPlayer = fromCtx.player or toCtx.player
  local ok, resultOrErr = moveBetweenContexts(actorPlayer, fromCtx, toCtx, fromSlot, toSlot, amount)
  if not ok then
    return buildPublicInventoryError(resultOrErr, {
      from = {
        container = cloneTable(type(fromDescriptor) == 'table' and fromDescriptor or { type = fromDescriptor }),
        slot = tonumber(fromSlot) or fromSlot
      },
      to = {
        container = cloneTable(type(toDescriptor) == 'table' and toDescriptor or { type = toDescriptor }),
        slot = tonumber(toSlot) or toSlot
      }
    })
  end

  local snapshotsOk, snapshotsOrErr = buildPublicTouchedSnapshots(source, {
    from = fromDescriptor,
    to = toDescriptor
  })
  if not snapshotsOk then
    return buildPublicInventoryError(snapshotsOrErr)
  end

  return buildPublicInventorySuccess({
    operation = type(resultOrErr) == 'table' and resultOrErr.operation or 'move',
    snapshots = snapshotsOrErr
  })
end

function MZInventoryService.splitInventoryStack(source, request)
  request = type(request) == 'table' and request or {}

  local descriptor = request.container
  local ctx, err = resolvePublicContainerContext(source, descriptor)
  if not ctx then
    return buildPublicInventoryError(err)
  end

  local actorPlayer = ctx.player
  local ok, resultOrErr = moveBetweenContexts(actorPlayer, ctx, ctx, request.from_slot, request.to_slot, request.amount, {
    forcedOperation = 'split'
  })
  if not ok then
    return buildPublicInventoryError(resultOrErr, {
      container = cloneTable(type(descriptor) == 'table' and descriptor or { type = descriptor })
    })
  end

  local snapshotsOk, snapshotsOrErr = buildPublicTouchedSnapshots(source, {
    container = descriptor
  })
  if not snapshotsOk then
    return buildPublicInventoryError(snapshotsOrErr)
  end

  return buildPublicInventorySuccess({
    operation = type(resultOrErr) == 'table' and resultOrErr.operation or 'split',
    snapshots = {
      container = snapshotsOrErr.container
    }
  })
end

function MZInventoryService.mergeInventorySlots(source, request)
  request = type(request) == 'table' and request or {}

  local descriptor = request.container
  local ctx, err = resolvePublicContainerContext(source, descriptor)
  if not ctx then
    return buildPublicInventoryError(err)
  end

  local actorPlayer = ctx.player
  local ok, resultOrErr = moveBetweenContexts(actorPlayer, ctx, ctx, request.from_slot, request.to_slot, request.amount, {
    forcedOperation = 'merge'
  })
  if not ok then
    return buildPublicInventoryError(resultOrErr, {
      container = cloneTable(type(descriptor) == 'table' and descriptor or { type = descriptor })
    })
  end

  local snapshotsOk, snapshotsOrErr = buildPublicTouchedSnapshots(source, {
    container = descriptor
  })
  if not snapshotsOk then
    return buildPublicInventoryError(snapshotsOrErr)
  end

  return buildPublicInventorySuccess({
    operation = type(resultOrErr) == 'table' and resultOrErr.operation or 'merge',
    snapshots = {
      container = snapshotsOrErr.container
    }
  })
end

function MZInventoryService.swapInventorySlots(source, request)
  request = type(request) == 'table' and request or {}

  local descriptor = request.container
  local ctx, err = resolvePublicContainerContext(source, descriptor)
  if not ctx then
    return buildPublicInventoryError(err)
  end

  local actorPlayer = ctx.player
  local ok, resultOrErr = moveBetweenContexts(actorPlayer, ctx, ctx, request.from_slot, request.to_slot, nil, {
    forcedOperation = 'swap'
  })
  if not ok then
    return buildPublicInventoryError(resultOrErr, {
      container = cloneTable(type(descriptor) == 'table' and descriptor or { type = descriptor })
    })
  end

  local snapshotsOk, snapshotsOrErr = buildPublicTouchedSnapshots(source, {
    container = descriptor
  })
  if not snapshotsOk then
    return buildPublicInventoryError(snapshotsOrErr)
  end

  return buildPublicInventorySuccess({
    operation = type(resultOrErr) == 'table' and resultOrErr.operation or 'swap',
    snapshots = {
      container = snapshotsOrErr.container
    }
  })
end

function MZInventoryService.useInventoryItemAction(source, request)
  request = type(request) == 'table' and request or {}

  local descriptor = request.container or { type = 'player' }
  local normalized, normalizeErr = normalizePublicContainerDescriptor(descriptor)
  if not normalized then
    return buildPublicInventoryError(normalizeErr)
  end

  if normalized.type ~= 'player' then
    return buildPublicInventoryError('invalid_target', {
      container = normalized
    })
  end

  local ok, resultOrErr = MZInventoryService.usePlayerItem(source, request.slot)
  if not ok then
    return buildPublicInventoryError(resultOrErr, {
      container = normalized,
      slot = tonumber(request.slot) or request.slot
    })
  end

  local snapshotOk, snapshotOrErr = getPublicInventorySnapshot(source, normalized)
  if not snapshotOk then
    return buildPublicInventoryError(snapshotOrErr)
  end

  return buildPublicInventorySuccess({
    result = resultOrErr,
    snapshot = snapshotOrErr
  })
end

function MZInventoryService.getPublicInventoryErrorCatalog()
  return cloneTable(PublicInventoryErrors)
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
