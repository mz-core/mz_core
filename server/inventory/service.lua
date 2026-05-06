MZInventoryService = {}

local ItemUseHandlers = {}
local EquippedWeaponsBySource = {}
local EquippedWeaponSourceByCitizenId = {}
local PendingWeaponAmmoUpdatesBySource = {}
local WeaponAmmoUpdateRateLimits = {}
local UnauthorizedWeaponLogRateLimits = {}
local PendingWeaponAmmoUpdateTtlMs = 10000

local enforceEquippedWeaponStillOwned
local applyEquippedAmmoToMovingWeapon
local cleanupInvalidHotbarRefsForPlayer

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

local emitWorldDropUpserted
local emitWorldDropRemoved

local WORLD_DROP_DEFAULT_LABEL = 'Ground Bag'
local WORLD_DROP_REUSE_RADIUS = 2.0
local WORLD_DROP_MAX_DISTANCE_FROM_PLAYER = 5.0

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
    local drop = MZWorldDropRepository.getByUid(dropUid)
    if drop then
      MZWorldDropRepository.deleteByUid(dropUid)
      emitWorldDropRemoved(dropUid)
      return true
    end
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

local function buildWorldDropSyncPayload(drop)
  if type(drop) ~= 'table' then
    return nil
  end

  local dropUid = tostring(drop.drop_uid or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if dropUid == '' then
    return nil
  end

  return {
    drop_uid = dropUid,
    label = tostring(drop.label or 'Drop'),
    x = tonumber(drop.x) or 0,
    y = tonumber(drop.y) or 0,
    z = tonumber(drop.z) or 0,
    metadata = cloneTable(type(drop.metadata_json) == 'table' and drop.metadata_json or {})
  }
end

emitWorldDropUpserted = function(drop)
  local payload = buildWorldDropSyncPayload(drop)
  if not payload then
    return
  end

  TriggerEvent('mz_core:server:inventory:worldDropUpserted', payload)
end

emitWorldDropRemoved = function(dropUid)
  dropUid = tostring(dropUid or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if dropUid == '' then
    return
  end

  TriggerEvent('mz_core:server:inventory:worldDropRemoved', dropUid)
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

cleanupInvalidHotbarRefsForPlayer = function(source, reason)
  local player = MZPlayerService.getPlayer(source)
  local citizenid = tostring(player and player.citizenid or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if citizenid == '' then
    return 0
  end

  local removed = tonumber(MZInventoryRepository.clearInvalidPlayerHotbarRefs(citizenid)) or 0
  if removed > 0 then
    logInventoryAction('inventory_hotbar_invalid_ref_cleaned', source, player, nil, {
      actor = buildInventoryActor(player, source),
      target = {
        type = 'hotbar',
        id = citizenid
      },
      context = {
        citizenid = citizenid,
        removed = removed,
        reason = tostring(reason or 'inventory_mutation')
      },
      meta = {
        removed = removed,
        reason = tostring(reason or 'inventory_mutation')
      }
    })
  end

  return removed
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

  if actorPlayer and enforceEquippedWeaponStillOwned then
    enforceEquippedWeaponStillOwned(actorPlayer.source, mutationName or 'inventory_mutation')
  end

  if actorPlayer and cleanupInvalidHotbarRefsForPlayer then
    cleanupInvalidHotbarRefsForPlayer(actorPlayer.source, mutationName or 'inventory_mutation')
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

  if applyEquippedAmmoToMovingWeapon then
    applyEquippedAmmoToMovingWeapon(fromCtx, fromRow, itemDef)
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

local function getWeaponConfig()
  return type(Config.Weapons) == 'table' and Config.Weapons or {}
end

local function getWeaponConfigNumber(key, fallback)
  local value = tonumber(getWeaponConfig()[key])
  if value == nil then
    return fallback
  end

  return value
end

local function generateWeaponEquipNonce(source, instanceUid)
  return MZUtils.generateInstanceUid(('WPN%s%s'):format(tostring(source or ''), tostring(instanceUid or '')))
end

local function weaponNonceMatches(state, equipNonce)
  if type(state) ~= 'table' then
    return false
  end

  local expected = tostring(state.equip_nonce or '')
  return expected ~= '' and expected == tostring(equipNonce or '')
end

local function isWeaponAmmoUpdateRateLimited(source, instanceUid)
  source = tonumber(source)
  instanceUid = tostring(instanceUid or '')
  if not source or instanceUid == '' then
    return true
  end

  local interval = math.max(0, math.floor(getWeaponConfigNumber('ammoUpdateMinIntervalMs', 750)))
  if interval <= 0 then
    return false
  end

  local key = ('%s:%s'):format(source, instanceUid)
  local now = GetGameTimer()
  local last = tonumber(WeaponAmmoUpdateRateLimits[key]) or 0
  if last > 0 and now - last < interval then
    return true
  end

  WeaponAmmoUpdateRateLimits[key] = now
  return false
end

local function isUnauthorizedWeaponLogRateLimited(source)
  source = tonumber(source)
  if not source then
    return true
  end

  local interval = math.max(0, math.floor(getWeaponConfigNumber('unauthorizedLogIntervalMs', 5000)))
  if interval <= 0 then
    return false
  end

  local now = GetGameTimer()
  local last = tonumber(UnauthorizedWeaponLogRateLimits[source]) or 0
  if last > 0 and now - last < interval then
    return true
  end

  UnauthorizedWeaponLogRateLimits[source] = now
  return false
end

local function clearWeaponRuntimeLimitsForSource(source)
  source = tonumber(source)
  if not source then
    return
  end

  PendingWeaponAmmoUpdatesBySource[source] = nil
  UnauthorizedWeaponLogRateLimits[source] = nil

  local prefix = tostring(source) .. ':'
  for key in pairs(WeaponAmmoUpdateRateLimits) do
    if tostring(key):sub(1, #prefix) == prefix then
      WeaponAmmoUpdateRateLimits[key] = nil
    end
  end
end

local function isWeaponItemDefinition(itemDef)
  return type(itemDef) == 'table'
    and (tostring(itemDef.type or '') == 'weapon' or tostring(itemDef.weapon or '') ~= '')
end

local function getWeaponNameFromDefinition(itemDef)
  if type(itemDef) ~= 'table' then
    return nil
  end

  local weaponName = tostring(itemDef.weapon or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
  if weaponName == '' then
    return nil
  end

  if weaponName:sub(1, 7) ~= 'WEAPON_' then
    weaponName = 'WEAPON_' .. weaponName
  end

  return weaponName
end

local function getWeaponHashValue(weaponName)
  local ok, result = pcall(function()
    return joaat(weaponName)
  end)

  if ok and result then
    return result
  end

  ok, result = pcall(function()
    return GetHashKey(weaponName)
  end)

  if ok and result then
    return result
  end

  return nil
end

local function clampWeaponAmmo(itemDef, ammo)
  ammo = tonumber(ammo) or 0
  ammo = math.floor(ammo)
  if ammo < 0 then
    ammo = 0
  end

  local maxAmmo = tonumber(type(itemDef) == 'table' and itemDef.maxAmmo or nil)
  if maxAmmo and maxAmmo >= 0 and ammo > maxAmmo then
    ammo = math.floor(maxAmmo)
  end

  return ammo
end

local function getWeaponInstanceUid(row)
  if type(row) ~= 'table' then
    return ''
  end

  local instanceUid = tostring(row.instance_uid or '')
  if instanceUid ~= '' then
    return instanceUid
  end

  local metadata = type(row.metadata) == 'table' and row.metadata or {}
  return tostring(metadata.uid or '')
end

local function findPlayerWeaponRowByInstance(ctx, instanceUid)
  instanceUid = tostring(instanceUid or '')
  if instanceUid == '' then
    return nil
  end

  for _, row in ipairs(getInventoryRowsFromContext(ctx)) do
    if getWeaponInstanceUid(row) == instanceUid then
      return row
    end
  end

  return nil
end

local function buildWeaponClientPayload(row, itemDef, source, action)
  local metadata = normalizeMetadataTable(row.metadata)
  local weaponName = getWeaponNameFromDefinition(itemDef)
  local ammo = clampWeaponAmmo(itemDef, metadata.ammo or itemDef.defaultAmmo or 0)
  local instanceUid = getWeaponInstanceUid(row)
  local weaponHash = getWeaponHashValue(weaponName)
  local equipNonce = generateWeaponEquipNonce(source, instanceUid)

  return {
    action = action or 'equip',
    source = tonumber(source) or source,
    item = tostring(row.item or ''),
    slot = tonumber(row.slot) or row.slot,
    instance_uid = instanceUid,
    weapon = weaponName,
    weapon_hash = weaponHash and tostring(weaponHash) or nil,
    equip_nonce = equipNonce,
    ammo = ammo,
    durability = tonumber(metadata.durability) or 100,
    serial = metadata.serial and tostring(metadata.serial) or nil
  }
end

local function logWeaponInventoryAction(action, source, player, row, extra)
  extra = type(extra) == 'table' and extra or {}

  local context = {
    inventory_label = 'player_main',
    owner_type = 'player',
    owner_id = tostring((player and player.citizenid) or extra.citizenid or ''),
    inventory_type = MZConstants.InventoryTypes.MAIN,
    slot = row and (tonumber(row.slot) or row.slot) or extra.slot,
    ammo = extra.ammo,
    known_ammo = extra.known_ammo,
    reason = tostring(extra.reason or '')
  }

  local itemName = row and tostring(row.item or '') or tostring(extra.item or '')
  local itemDef = getItemDefinition(itemName)
  local instanceUid = row and getWeaponInstanceUid(row) or tostring(extra.instance_uid or '')

  logInventoryAction(action, source, player, nil, {
    actor = buildInventoryActor(player, source),
    target = {
      type = 'weapon',
      id = instanceUid ~= '' and instanceUid or 'unknown'
    },
    context = context,
    meta = {
      item = itemName,
      instance_uid = instanceUid,
      weapon = itemDef and getWeaponNameFromDefinition(itemDef) or tostring(extra.weapon or ''),
      reason = tostring(extra.reason or '')
    }
  })
end

local function queuePendingWeaponAmmoUpdate(source, equipped)
  source = tonumber(source)
  if not source or type(equipped) ~= 'table' or tostring(equipped.instance_uid or '') == '' then
    return
  end

  PendingWeaponAmmoUpdatesBySource[source] = {
    instance_uid = tostring(equipped.instance_uid),
    slot = tonumber(equipped.slot) or equipped.slot,
    item = tostring(equipped.item or ''),
    equip_nonce = tostring(equipped.equip_nonce or ''),
    ammo = math.max(0, math.floor(tonumber(equipped.ammo) or 0)),
    expires_at = GetGameTimer() + PendingWeaponAmmoUpdateTtlMs
  }
end

local function clearPendingWeaponAmmoUpdate(source, instanceUid)
  source = tonumber(source)
  if not source then
    return
  end

  local pending = PendingWeaponAmmoUpdatesBySource[source]
  if not pending then
    return
  end

  if not instanceUid or tostring(pending.instance_uid or '') == tostring(instanceUid or '') then
    PendingWeaponAmmoUpdatesBySource[source] = nil
  end
end

local function getAllowedWeaponAmmoUpdate(source, instanceUid, equipNonce)
  source = tonumber(source)
  instanceUid = tostring(instanceUid or '')
  if not source or instanceUid == '' then
    return nil
  end

  local equipped = EquippedWeaponsBySource[source]
  if equipped and tostring(equipped.instance_uid or '') == instanceUid and weaponNonceMatches(equipped, equipNonce) then
    return 'equipped', equipped
  end

  local pending = PendingWeaponAmmoUpdatesBySource[source]
  if pending and tostring(pending.instance_uid or '') == instanceUid and weaponNonceMatches(pending, equipNonce) then
    if GetGameTimer() <= (tonumber(pending.expires_at) or 0) then
      return 'pending', pending
    end

    PendingWeaponAmmoUpdatesBySource[source] = nil
  end

  return nil
end

local function setEquippedWeaponState(source, player, row, payload)
  source = tonumber(source)
  if not source or type(player) ~= 'table' or type(row) ~= 'table' or type(payload) ~= 'table' then
    return
  end

  local state = {
    source = source,
    citizenid = tostring(player.citizenid or ''),
    item = tostring(row.item or ''),
    slot = tonumber(row.slot) or row.slot,
    instance_uid = tostring(payload.instance_uid or ''),
    weapon = tostring(payload.weapon or ''),
    equip_nonce = tostring(payload.equip_nonce or ''),
    ammo = math.max(0, math.floor(tonumber(payload.ammo) or 0)),
    serial = payload.serial,
    durability = payload.durability
  }

  EquippedWeaponsBySource[source] = state
  if state.citizenid ~= '' then
    EquippedWeaponSourceByCitizenId[state.citizenid] = source
  end
end

local function clearEquippedWeaponState(source, reason, options)
  source = tonumber(source)
  if not source then
    return false, 'invalid_source'
  end

  options = type(options) == 'table' and options or {}
  local equipped = EquippedWeaponsBySource[source]
  if not equipped then
    return true
  end

  if options.queuePending ~= false then
    queuePendingWeaponAmmoUpdate(source, equipped)
  end

  local player = MZPlayerService.getPlayer(source)
  EquippedWeaponsBySource[source] = nil
  if equipped.citizenid and EquippedWeaponSourceByCitizenId[equipped.citizenid] == source then
    EquippedWeaponSourceByCitizenId[equipped.citizenid] = nil
  end

  logWeaponInventoryAction('weapon_unequip', source, player or { source = source, citizenid = equipped.citizenid }, {
    item = equipped.item,
    slot = equipped.slot,
    instance_uid = equipped.instance_uid,
    metadata = {
      serial = equipped.serial,
      durability = equipped.durability
    }
  }, {
    reason = tostring(reason or 'unequip'),
    weapon = equipped.weapon
  })

  if options.notifyClient ~= false then
    TriggerClientEvent('mz_core:client:inventory:unequipWeapon', source, {
      reason = tostring(reason or 'unequip'),
      item = equipped.item,
      slot = equipped.slot,
      instance_uid = equipped.instance_uid,
      weapon = equipped.weapon,
      equip_nonce = equipped.equip_nonce
    })
  end

  return true
end

local function updateWeaponAmmoMetadata(source, instanceUid, ammo, reason, equipNonce)
  local player, playerErr = getPlayerBySource(source)
  if not player then
    return false, playerErr
  end

  local requestedAmmo = tonumber(ammo)
  if requestedAmmo == nil then
    return false, 'invalid_ammo'
  end
  requestedAmmo = math.floor(requestedAmmo)
  if requestedAmmo < 0 then
    requestedAmmo = 0
  end

  local ctx, ctxErr = getPlayerInventoryContext(source)
  if not ctx then
    return false, ctxErr
  end

  local allowedMode, allowedState = getAllowedWeaponAmmoUpdate(source, instanceUid, equipNonce)
  if not allowedMode then
    return false, 'weapon_not_equipped'
  end

  if allowedMode ~= 'pending' and isWeaponAmmoUpdateRateLimited(source, instanceUid) then
    return false, 'weapon_ammo_rate_limited'
  end

  local lockHandle, lockErr = acquireContainerLocks({ ctx })
  if not lockHandle then
    return false, lockErr
  end

  local row = findPlayerWeaponRowByInstance(ctx, instanceUid)
  if not row then
    releaseContainerLocks(lockHandle)
    return false, 'weapon_not_owned'
  end

  local itemDef = getItemDefinition(row.item)
  if not isWeaponItemDefinition(itemDef) then
    releaseContainerLocks(lockHandle)
    return false, 'item_not_weapon'
  end

  local nextAmmo = clampWeaponAmmo(itemDef, requestedAmmo)
  local currentMetadata = type(row.metadata) == 'table' and row.metadata or {}
  local knownAmmo = clampWeaponAmmo(itemDef, allowedState and allowedState.ammo or currentMetadata.ammo or itemDef.defaultAmmo or 0)

  -- Client ammo updates only confirm shots/decreases. Future ammo increases must come from a server-side reload flow.
  if nextAmmo > knownAmmo then
    releaseContainerLocks(lockHandle)
    logWeaponInventoryAction('weapon_ammo_increase_blocked', source, player, row, {
      reason = tostring(reason or 'client_update'),
      ammo = nextAmmo,
      known_ammo = knownAmmo
    })
    return false, 'weapon_ammo_increase_blocked'
  end

  local metadata = cloneTable(type(row.metadata) == 'table' and row.metadata or {})
  metadata.ammo = nextAmmo

  MZInventoryRepository.updateMetadataBySlot(ctx.ownerType, ctx.ownerId, ctx.inventoryType, row.slot, metadata)
  releaseContainerLocks(lockHandle)

  local equipped = EquippedWeaponsBySource[tonumber(source)]
  if equipped and tostring(equipped.instance_uid or '') == tostring(instanceUid or '') then
    equipped.ammo = nextAmmo
    equipped.slot = tonumber(row.slot) or row.slot
  end

  clearPendingWeaponAmmoUpdate(source, instanceUid)

  logWeaponInventoryAction('weapon_ammo_update', source, player, row, {
    reason = tostring(reason or 'client_update'),
    ammo = nextAmmo
  })

  return true, {
    ammo = nextAmmo,
    slot = tonumber(row.slot) or row.slot,
    instance_uid = tostring(instanceUid or '')
  }
end

local function handleWeaponItemUse(payload)
  payload = type(payload) == 'table' and payload or {}

  local source = tonumber(payload.source)
  if not source then
    return {
      ok = false,
      error = 'invalid_source'
    }
  end

  local ctx, ctxErr = getPlayerInventoryContext(source)
  if not ctx then
    return {
      ok = false,
      error = ctxErr
    }
  end

  local slot = tonumber(payload.slot)
  local row = findRowBySlot(getInventoryRowsFromContext(ctx), slot)
  if not row or tostring(row.item or '') ~= tostring(payload.item or '') then
    return {
      ok = false,
      error = 'slot_empty'
    }
  end

  local itemDef = getItemDefinition(row.item)
  if not isWeaponItemDefinition(itemDef) then
    return {
      ok = false,
      error = 'item_not_weapon'
    }
  end

  local instanceUid = getWeaponInstanceUid(row)
  if instanceUid == '' then
    return {
      ok = false,
      error = 'missing_weapon_uid'
    }
  end

  local current = EquippedWeaponsBySource[source]
  if current and tostring(current.instance_uid or '') == instanceUid then
    clearEquippedWeaponState(source, 'toggle_unequip', { notifyClient = true })
    return {
      ok = true,
      consume = false,
      data = {
        weapon = {
          equipped = false,
          instance_uid = instanceUid
        }
      }
    }
  end

  if current then
    logWeaponInventoryAction('weapon_unequip', source, ctx.player, {
      item = current.item,
      slot = current.slot,
      instance_uid = current.instance_uid,
      metadata = {
        serial = current.serial,
        durability = current.durability
      }
    }, {
      reason = 'switch_weapon',
      weapon = current.weapon
    })
    queuePendingWeaponAmmoUpdate(source, current)
  end

  local clientPayload = buildWeaponClientPayload(row, itemDef, source, 'equip')
  setEquippedWeaponState(source, ctx.player, row, clientPayload)

  logWeaponInventoryAction('weapon_equip', source, ctx.player, row, {
    weapon = clientPayload.weapon,
    ammo = clientPayload.ammo,
    reason = current and 'switch_weapon' or 'use_item'
  })

  TriggerClientEvent('mz_core:client:inventory:equipWeapon', source, clientPayload)

  return {
    ok = true,
    consume = false,
    data = {
      weapon = {
        equipped = true,
        item = clientPayload.item,
        slot = clientPayload.slot,
        instance_uid = clientPayload.instance_uid,
        weapon = clientPayload.weapon,
        equip_nonce = clientPayload.equip_nonce,
        ammo = clientPayload.ammo,
        durability = clientPayload.durability,
        serial = clientPayload.serial
      }
    }
  }
end

applyEquippedAmmoToMovingWeapon = function(fromCtx, fromRow, itemDef)
  if not isWeaponItemDefinition(itemDef) then
    return
  end

  if type(fromCtx) ~= 'table' or tostring(fromCtx.ownerType or '') ~= 'player' then
    return
  end

  local source = tonumber(fromCtx.player and fromCtx.player.source)
  local equipped = source and EquippedWeaponsBySource[source] or nil
  if not equipped then
    return
  end

  if tostring(equipped.instance_uid or '') ~= getWeaponInstanceUid(fromRow) then
    return
  end

  fromRow.metadata = cloneTable(type(fromRow.metadata) == 'table' and fromRow.metadata or {})
  fromRow.metadata.ammo = clampWeaponAmmo(itemDef, equipped.ammo or fromRow.metadata.ammo or itemDef.defaultAmmo or 0)
end

enforceEquippedWeaponStillOwned = function(source, reason)
  source = tonumber(source)
  if not source then
    return true
  end

  if getWeaponConfig().enforceInventoryWeapons == false then
    return true
  end

  local equipped = EquippedWeaponsBySource[source]
  if not equipped then
    return true
  end

  local ctx = getPlayerInventoryContext(source)
  if not ctx then
    return clearEquippedWeaponState(source, reason or 'player_inventory_missing', { notifyClient = true })
  end

  local row = findPlayerWeaponRowByInstance(ctx, equipped.instance_uid)
  local itemDef = row and getItemDefinition(row.item) or nil
  if not row or not isWeaponItemDefinition(itemDef) then
    return clearEquippedWeaponState(source, reason or 'weapon_not_owned', { notifyClient = true })
  end

  equipped.slot = tonumber(row.slot) or row.slot
  return true
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

local function buildUsePlayerItemMutationPlan(ctx, source, slot, expectedInstanceUid)
  slot = tonumber(slot)
  if not isValidSlotNumber(slot, ctx.maxSlots) then
    return false, 'invalid_slot'
  end

  local row = findRowBySlot(getInventoryRowsFromContext(ctx), slot)
  if not row then
    return false, 'slot_empty'
  end

  expectedInstanceUid = tostring(expectedInstanceUid or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if expectedInstanceUid ~= '' then
    local rowInstanceUid = tostring(row.instance_uid or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if rowInstanceUid ~= expectedInstanceUid then
      return false, 'hotbar_item_moved'
    end
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

  emitWorldDropUpserted(drop)

  return true, drop
end

function MZInventoryService.deleteWorldDrop(dropUid)
  dropUid = tostring(dropUid or '')
  if dropUid == '' then
    return false, 'invalid_drop_uid'
  end

  local drop = MZWorldDropRepository.getByUid(dropUid)
  MZInventoryRepository.clearInventory('world', dropUid, 'drop')
  MZWorldDropRepository.deleteByUid(dropUid)

  if drop then
    emitWorldDropRemoved(dropUid)
  end

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

local function getSourcePedCoords(source)
  local ped = GetPlayerPed(source)
  if not ped or ped == 0 then
    return nil
  end

  local coords = GetEntityCoords(ped)
  if not coords then
    return nil
  end

  return {
    x = tonumber(coords.x) or 0,
    y = tonumber(coords.y) or 0,
    z = tonumber(coords.z) or 0
  }
end

local function getDistanceSquared(leftCoords, rightCoords)
  if type(leftCoords) ~= 'table' or type(rightCoords) ~= 'table' then
    return math.huge
  end

  local dx = (tonumber(leftCoords.x) or 0) - (tonumber(rightCoords.x) or 0)
  local dy = (tonumber(leftCoords.y) or 0) - (tonumber(rightCoords.y) or 0)
  local dz = (tonumber(leftCoords.z) or 0) - (tonumber(rightCoords.z) or 0)

  return (dx * dx) + (dy * dy) + (dz * dz)
end

local function resolveGroundDropCoords(source, requestedCoords)
  local fallbackCoords = getSourcePedCoords(source)
  local normalizedCoords = normalizeWorldCoords(requestedCoords)

  if type(requestedCoords) ~= 'table' then
    return fallbackCoords or normalizedCoords
  end

  if not fallbackCoords then
    return normalizedCoords
  end

  local maxDistanceSq = WORLD_DROP_MAX_DISTANCE_FROM_PLAYER * WORLD_DROP_MAX_DISTANCE_FROM_PLAYER
  if getDistanceSquared(fallbackCoords, normalizedCoords) > maxDistanceSq then
    return fallbackCoords
  end

  return normalizedCoords
end

local function findReusableWorldDropForPlayer(player, coords)
  if type(player) ~= 'table' or tostring(player.citizenid or '') == '' then
    return nil
  end

  local bestDrop = nil
  local bestDistanceSq = nil
  local maxDistanceSq = WORLD_DROP_REUSE_RADIUS * WORLD_DROP_REUSE_RADIUS

  for _, drop in ipairs(MZWorldDropRepository.listAll() or {}) do
    local metadata = type(drop.metadata_json) == 'table' and drop.metadata_json or {}
    if tostring(metadata.created_by or '') == tostring(player.citizenid) then
      local distanceSq = getDistanceSquared(coords, {
        x = drop.x,
        y = drop.y,
        z = drop.z
      })

      if distanceSq <= maxDistanceSq and (bestDistanceSq == nil or distanceSq < bestDistanceSq) then
        bestDrop = drop
        bestDistanceSq = distanceSq
      end
    end
  end

  return bestDrop
end

local function chooseWorldDropSlot(ctx, itemName, metadata)
  local rows = getInventoryRowsFromContext(ctx)
  local stackRow = findStackableRowInRows(rows, itemName, metadata or {})
  if stackRow then
    return tonumber(stackRow.slot) or stackRow.slot
  end

  return findFreeSlotInRows(rows, ctx.maxSlots)
end

local function ensureWorldDropForTransfer(source, playerCtx, itemRow, coords)
  local reusableDrop = findReusableWorldDropForPlayer(playerCtx.player, coords)
  if reusableDrop then
    local reusableCtx = getWorldDropContext(reusableDrop.drop_uid)
    if reusableCtx then
      local reusableSlot = chooseWorldDropSlot(reusableCtx, itemRow.item, itemRow.metadata or {})
      if reusableSlot then
        return true, reusableCtx, reusableDrop, reusableSlot, false
      end
    end
  end

  local ok, dropOrErr = MZInventoryService.createWorldDrop(coords, WORLD_DROP_DEFAULT_LABEL, {
    source = 'inventory_drop',
    created_by = tostring(playerCtx.player and playerCtx.player.citizenid or ''),
    created_at = os.time()
  })
  if not ok then
    return false, dropOrErr
  end

  local dropCtx, dropErr = getWorldDropContext(dropOrErr.drop_uid)
  if not dropCtx then
    MZInventoryService.deleteWorldDrop(dropOrErr.drop_uid)
    return false, dropErr
  end

  local targetSlot = chooseWorldDropSlot(dropCtx, itemRow.item, itemRow.metadata or {})
  if not targetSlot then
    MZInventoryService.deleteWorldDrop(dropOrErr.drop_uid)
    return false, 'no_free_slot'
  end

  return true, dropCtx, dropOrErr, targetSlot, true
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

function MZInventoryService.usePlayerItemByInstanceUid(source, instanceUid)
  local ctx, err = getPlayerInventoryContext(source)
  if not ctx then
    return false, err
  end

  instanceUid = tostring(instanceUid or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if instanceUid == '' then
    return false, 'invalid_hotbar_instance'
  end

  return executeInventoryMutation(ctx.player, { ctx }, 'use_player_item_by_instance_uid', function()
    local rows = getInventoryRowsFromContext(ctx)
    local row = nil

    for _, candidate in ipairs(rows) do
      local candidateUid = tostring(candidate.instance_uid or ''):gsub('^%s+', ''):gsub('%s+$', '')
      if candidateUid == instanceUid then
        row = candidate
        break
      end
    end

    if not row then
      return false, 'hotbar_item_missing'
    end

    return buildUsePlayerItemMutationPlan(ctx, source, row.slot, instanceUid)
  end)
end

function MZInventoryService.updateEquippedWeaponAmmo(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local instanceUid = tostring(payload.instance_uid or payload.instanceUid or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if instanceUid == '' then
    return false, 'invalid_weapon_uid'
  end

  local equipNonce = tostring(payload.equip_nonce or payload.equipNonce or payload.nonce or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if equipNonce == '' then
    return false, 'invalid_weapon_nonce'
  end

  return updateWeaponAmmoMetadata(source, instanceUid, payload.ammo, payload.reason or 'client_update', equipNonce)
end

function MZInventoryService.clearPlayerEquippedWeapon(source, reason)
  return clearEquippedWeaponState(source, reason or 'clear_equipped_weapon', { notifyClient = true })
end

function MZInventoryService.handlePlayerDropped(source, reason)
  local ok, err = clearEquippedWeaponState(source, reason or 'player_dropped', { notifyClient = false, queuePending = false })
  clearWeaponRuntimeLimitsForSource(source)
  return ok, err
end

function MZInventoryService.logUnauthorizedWeapon(source, payload)
  payload = type(payload) == 'table' and payload or {}
  if isUnauthorizedWeaponLogRateLimited(source) then
    return false, 'weapon_unauthorized_rate_limited'
  end

  local player = MZPlayerService.getPlayer(source)
  logInventoryAction('weapon_unauthorized_detected', source, player, nil, {
    actor = buildInventoryActor(player, source),
    target = {
      type = 'ped_weapon',
      id = tostring(payload.weapon or payload.weapon_hash or 'unknown')
    },
    context = {
      selected_weapon = tostring(payload.weapon or ''),
      selected_hash = tostring(payload.weapon_hash or ''),
      authorized_instance_uid = tostring(payload.authorized_instance_uid or ''),
      reason = tostring(payload.reason or 'unauthorized_weapon')
    },
    meta = {
      event = 'client_weapon_enforcement'
    }
  })
  return true
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
  drop_create_failed = { code = 'drop_create_failed', message = 'Failed to create ground drop.' },
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
    use_handler_failed = 'use_failed',
    invalid_source = 'use_failed',
    invalid_ammo = 'use_failed',
    invalid_hotbar_slot = 'invalid_slot',
    missing_weapon_uid = 'use_failed',
    missing_instance_uid = 'use_failed',
    invalid_weapon_uid = 'use_failed',
    invalid_weapon_nonce = 'use_failed',
    hotbar_slot_empty = 'invalid_slot',
    hotbar_item_missing = 'use_failed',
    hotbar_save_failed = 'use_failed',
    hotbar_clear_failed = 'use_failed',
    item_not_weapon = 'item_not_usable',
    weapon_not_equipped = 'use_failed',
    weapon_not_owned = 'use_failed',
    weapon_ammo_rate_limited = 'use_failed',
    weapon_ammo_increase_blocked = 'use_failed',
    drop_create_failed = 'drop_create_failed'
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
      image = nil,
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
    image = itemDef and tostring(itemDef.image or ((row.item or '') .. '.png')) or (tostring(row.item or '') .. '.png'),
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

local function getHotbarSlotCount()
  local count = tonumber(Config.Inventory and Config.Inventory.hotbarSlots) or 5
  count = math.floor(count)
  if count < 1 then
    count = 1
  end

  return count
end

local function normalizeHotbarSlot(hotbarSlot)
  hotbarSlot = tonumber(hotbarSlot)
  if not hotbarSlot then
    return nil
  end

  hotbarSlot = math.floor(hotbarSlot)
  if hotbarSlot < 1 or hotbarSlot > getHotbarSlotCount() then
    return nil
  end

  return hotbarSlot
end

local function isPlayerMainInventoryRow(row, citizenid)
  return type(row) == 'table'
    and tostring(row.owner_type or '') == 'player'
    and tostring(row.owner_id or '') == tostring(citizenid or '')
    and tostring(row.inventory_type or '') == MZConstants.InventoryTypes.MAIN
end

local function resolvePlayerHotbarSlots(source, citizenid)
  citizenid = tostring(citizenid or ''):gsub('^%s+', ''):gsub('%s+$', '')
  local entries = MZInventoryRepository.getPlayerHotbar(citizenid)
  local bySlot = {}
  for _, entry in ipairs(entries) do
    local slot = normalizeHotbarSlot(entry.hotbar_slot)
    local instanceUid = tostring(entry.instance_uid or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if slot and instanceUid ~= '' then
      bySlot[slot] = instanceUid
    end
  end

  local slots = {}
  for slot = 1, getHotbarSlotCount() do
    local instanceUid = bySlot[slot]
    local row = instanceUid and MZInventoryRepository.getByInstanceUid(instanceUid) or nil
    local valid = row and isPlayerMainInventoryRow(row, citizenid)
    local itemDef = valid and getItemDefinition(row.item) or nil

    slots[#slots + 1] = {
      hotbar_slot = slot,
      instance_uid = instanceUid,
      valid = valid == true,
      inventory_slot = valid and (tonumber(row.slot) or row.slot) or nil,
      item = valid and tostring(row.item or '') or nil,
      label = valid and itemDef and tostring(itemDef.label or row.item or '') or nil,
      usable = valid and itemDef and itemDef.usable == true or false,
      unique = valid and itemDef and itemDef.unique == true or false
    }
  end

  return slots
end

local function logHotbarAction(action, source, player, hotbarSlot, instanceUid, extra)
  extra = type(extra) == 'table' and extra or {}
  logInventoryAction(action, source, player, nil, {
    actor = buildInventoryActor(player, source),
    target = {
      type = 'hotbar',
      id = tostring(hotbarSlot or 'unknown')
    },
    context = {
      citizenid = tostring(player and player.citizenid or ''),
      hotbar_slot = tonumber(hotbarSlot) or hotbarSlot,
      instance_uid = tostring(instanceUid or ''),
      inventory_slot = extra.inventory_slot,
      reason = tostring(extra.reason or '')
    },
    meta = {
      item = tostring(extra.item or ''),
      instance_uid = tostring(instanceUid or ''),
      hotbar_slot = tonumber(hotbarSlot) or hotbarSlot,
      reason = tostring(extra.reason or '')
    }
  })
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

local function collectTouchedWorldDropUids(...)
  local collected = {}
  local seen = {}

  for index = 1, select('#', ...) do
    local ctx = select(index, ...)
    if type(ctx) == 'table'
      and tostring(ctx.ownerType or '') == 'world'
      and tostring(ctx.inventoryType or '') == 'drop' then
      local dropUid = tostring((ctx.drop and ctx.drop.drop_uid) or ctx.ownerId or ''):gsub('^%s+', ''):gsub('%s+$', '')
      if dropUid ~= '' and not seen[dropUid] then
        seen[dropUid] = true
        collected[#collected + 1] = dropUid
      end
    end
  end

  return collected
end

local function cleanupTouchedWorldDrops(dropUids)
  for _, dropUid in ipairs(type(dropUids) == 'table' and dropUids or {}) do
    cleanupDropIfEmpty(dropUid)
  end
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

function MZInventoryService.dropInventoryItemAction(source, request)
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

  local playerCtx, ctxErr = resolvePublicContainerContext(source, normalized)
  if not playerCtx then
    return buildPublicInventoryError(ctxErr, {
      container = normalized
    })
  end

  local fromSlot = tonumber(request.slot or request.from_slot)
  if not isValidSlotNumber(fromSlot, playerCtx.maxSlots) then
    return buildPublicInventoryError('invalid_slot', {
      container = normalized,
      slot = tonumber(request.slot) or request.slot
    })
  end

  local sourceRow = findRowBySlot(getInventoryRowsFromContext(playerCtx), fromSlot)
  if not sourceRow then
    return buildPublicInventoryError('source_slot_empty', {
      container = normalized,
      slot = fromSlot
    })
  end

  local dropCoords = resolveGroundDropCoords(source, request.coords)
  local dropOk, dropCtxOrErr, dropData, targetSlot, createdDrop = ensureWorldDropForTransfer(source, playerCtx, sourceRow, dropCoords)
  if not dropOk then
    return buildPublicInventoryError(dropCtxOrErr, {
      container = normalized,
      slot = fromSlot
    })
  end

  local moveOk, resultOrErr = moveBetweenContexts(
    playerCtx.player,
    playerCtx,
    dropCtxOrErr,
    fromSlot,
    targetSlot,
    request.amount
  )
  if not moveOk then
    if createdDrop == true and type(dropData) == 'table' and tostring(dropData.drop_uid or '') ~= '' then
      cleanupDropIfEmpty(dropData.drop_uid)
    end

    return buildPublicInventoryError(resultOrErr, {
      container = normalized,
      slot = fromSlot
    })
  end

  local snapshotsOk, snapshotsOrErr = buildPublicTouchedSnapshots(source, {
    player = normalized,
    drop = {
      type = 'drop',
      drop_uid = tostring(dropData and dropData.drop_uid or '')
    }
  })
  if not snapshotsOk then
    return buildPublicInventoryError(snapshotsOrErr)
  end

  return buildPublicInventorySuccess({
    operation = type(resultOrErr) == 'table' and resultOrErr.operation or 'move',
    drop_uid = tostring(dropData and dropData.drop_uid or ''),
    created_drop = createdDrop == true,
    snapshots = {
      player = snapshotsOrErr.player,
      drop = snapshotsOrErr.drop
    }
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

  local touchedDropUids = collectTouchedWorldDropUids(fromCtx, toCtx)
  local snapshotsOk, snapshotsOrErr = buildPublicTouchedSnapshots(source, {
    from = fromDescriptor,
    to = toDescriptor
  })
  cleanupTouchedWorldDrops(touchedDropUids)
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

function MZInventoryService.getPlayerHotbar(source)
  local player, playerErr = getPlayerBySource(source)
  if not player then
    return false, playerErr
  end

  cleanupInvalidHotbarRefsForPlayer(source, 'get_hotbar')
  return true, {
    slots = resolvePlayerHotbarSlots(source, player.citizenid)
  }
end

function MZInventoryService.bindHotbarSlot(source, hotbarSlot, inventorySlot)
  local player, playerErr = getPlayerBySource(source)
  if not player then
    return false, playerErr
  end

  hotbarSlot = normalizeHotbarSlot(hotbarSlot)
  if not hotbarSlot then
    return false, 'invalid_hotbar_slot'
  end

  inventorySlot = tonumber(inventorySlot)
  if not inventorySlot then
    return false, 'invalid_slot'
  end

  local ctx, ctxErr = getPlayerInventoryContext(source)
  if not ctx then
    return false, ctxErr
  end

  if not isValidSlotNumber(inventorySlot, ctx.maxSlots) then
    return false, 'invalid_slot'
  end

  local row = findRowBySlot(getInventoryRowsFromContext(ctx), inventorySlot)
  if not row then
    return false, 'slot_empty'
  end

  local itemDef = getItemDefinition(row.item)
  if not itemDef then
    return false, 'item_not_found'
  end

  if itemDef.usable ~= true then
    return false, 'item_not_usable'
  end

  local instanceUid = tostring(row.instance_uid or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if instanceUid == '' then
    return false, 'missing_instance_uid'
  end

  local ok, err = MZInventoryRepository.setPlayerHotbarSlot(player.citizenid, hotbarSlot, instanceUid)
  if not ok then
    return false, err or 'hotbar_save_failed'
  end

  logHotbarAction('inventory_hotbar_bind', source, player, hotbarSlot, instanceUid, {
    item = row.item,
    inventory_slot = tonumber(row.slot) or row.slot
  })

  return true, {
    hotbar_slot = hotbarSlot,
    instance_uid = instanceUid,
    inventory_slot = tonumber(row.slot) or row.slot,
    item = tostring(row.item or '')
  }
end

function MZInventoryService.clearHotbarSlot(source, hotbarSlot)
  local player, playerErr = getPlayerBySource(source)
  if not player then
    return false, playerErr
  end

  hotbarSlot = normalizeHotbarSlot(hotbarSlot)
  if not hotbarSlot then
    return false, 'invalid_hotbar_slot'
  end

  local currentInstanceUid = ''
  local hotbar = MZInventoryRepository.getPlayerHotbar(player.citizenid)
  for _, entry in ipairs(hotbar) do
    if tonumber(entry.hotbar_slot) == hotbarSlot then
      currentInstanceUid = tostring(entry.instance_uid or ''):gsub('^%s+', ''):gsub('%s+$', '')
      break
    end
  end

  local removedOrFalse, err = MZInventoryRepository.clearPlayerHotbarSlot(player.citizenid, hotbarSlot)
  if removedOrFalse == false then
    return false, err or 'hotbar_clear_failed'
  end

  local removed = tonumber(removedOrFalse) or 0
  if removed > 0 then
    logHotbarAction('inventory_hotbar_clear', source, player, hotbarSlot, currentInstanceUid, {
      reason = 'manual_clear'
    })
  end

  return true, {
    hotbar_slot = hotbarSlot,
    removed = removed
  }
end

function MZInventoryService.useHotbarSlot(source, hotbarSlot)
  local player, playerErr = getPlayerBySource(source)
  if not player then
    return false, playerErr
  end

  hotbarSlot = normalizeHotbarSlot(hotbarSlot)
  if not hotbarSlot then
    return false, 'invalid_hotbar_slot'
  end

  local hotbar = MZInventoryRepository.getPlayerHotbar(player.citizenid)
  local instanceUid = ''
  for _, entry in ipairs(hotbar) do
    if tonumber(entry.hotbar_slot) == hotbarSlot then
      instanceUid = tostring(entry.instance_uid or ''):gsub('^%s+', ''):gsub('%s+$', '')
      break
    end
  end

  if instanceUid == '' then
    return false, 'hotbar_slot_empty'
  end

  local row = MZInventoryRepository.getByInstanceUid(instanceUid)
  if not isPlayerMainInventoryRow(row, player.citizenid) then
    cleanupInvalidHotbarRefsForPlayer(source, 'hotbar_use_missing_item')
    return false, 'hotbar_item_missing'
  end

  local itemDef = getItemDefinition(row.item)
  if not itemDef then
    cleanupInvalidHotbarRefsForPlayer(source, 'hotbar_use_missing_item_definition')
    return false, 'item_not_found'
  end

  if itemDef.usable ~= true then
    return false, 'item_not_usable'
  end

  local ok, resultOrErr = MZInventoryService.usePlayerItemByInstanceUid(source, instanceUid)
  if not ok then
    if resultOrErr == 'hotbar_item_missing' or resultOrErr == 'hotbar_item_moved' then
      cleanupInvalidHotbarRefsForPlayer(source, 'hotbar_use_invalid_reference')
    end
    return false, resultOrErr
  end

  local usedRow = MZInventoryRepository.getByInstanceUid(instanceUid) or row

  logHotbarAction('inventory_hotbar_use', source, player, hotbarSlot, instanceUid, {
    item = usedRow.item,
    inventory_slot = tonumber(usedRow.slot) or usedRow.slot
  })

  return true, {
    hotbar_slot = hotbarSlot,
    instance_uid = instanceUid,
    inventory_slot = tonumber(usedRow.slot) or usedRow.slot,
    item = tostring(usedRow.item or ''),
    result = resultOrErr
  }
end

function MZInventoryService.cleanupInvalidHotbarRefs(source)
  return cleanupInvalidHotbarRefsForPlayer(source, 'manual_cleanup')
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

MZInventoryService.registerItemUseHandler('weapon_pistol', function(payload)
  return handleWeaponItemUse(payload)
end)
