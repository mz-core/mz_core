local function expect(condition, message)
  if not condition then error(message, 2) end
end

local clock = 1000
local appliedPayload = nil
local equippedPayload = nil
local rows = {
  {
    slot = 4,
    item = 'weapon_pistol',
    amount = 1,
    instance_uid = 'MZINV-PISTOL-RELOAD',
    metadata = {
      uid = 'MZINV-PISTOL-RELOAD',
      ammo = 5,
      clip_ammo = 2,
      ammo_revision = 3
    }
  },
  {
    slot = 5,
    item = 'ammo_pistol',
    amount = 2,
    metadata = {}
  }
}

local function findRow(slot)
  for _, row in ipairs(rows) do
    if tonumber(row.slot) == tonumber(slot) then return row end
  end
end

local function deleteRow(slot)
  for index, row in ipairs(rows) do
    if tonumber(row.slot) == tonumber(slot) then
      table.remove(rows, index)
      return
    end
  end
end

Config = {
  Inventory = { defaultSlots = 40, defaultWeight = 50000 },
  Weapons = { enforceInventoryWeapons = true, ammoUpdateMinIntervalMs = 0 }
}
MZConstants = { InventoryTypes = { MAIN = 'main', STASH = 'stash', TRUNK = 'trunk', GLOVEBOX = 'glovebox', DROP = 'drop' } }
MZItems = {
  weapon_pistol = {
    type = 'weapon', weapon = 'WEAPON_PISTOL', ammoType = 'ammo_pistol',
    unique = true, usable = true, maxAmmo = 120, defaultAmmo = 0, clipSize = 12
  },
  ammo_pistol = {
    type = 'ammo', ammoType = 'ammo_pistol', reloadAmount = 12,
    stack = true, usable = true
  },
  weapon_mg = {
    type = 'weapon', weapon = 'WEAPON_MG', ammoType = 'ammo_heavy',
    unique = true, usable = true, maxAmmo = 240, defaultAmmo = 0, clipSize = 54
  },
  ammo_heavy = {
    type = 'ammo', ammoType = 'ammo_heavy', reloadAmount = 20,
    stack = true, usable = true
  }
}
MZUtils = {
  tableClone = function(input)
    local out = {}
    for key, value in pairs(input or {}) do out[key] = value end
    return out
  end,
  generateInstanceUid = function() return 'generated' end,
  generateItemSerial = function() return 'serial' end,
  jsonEncode = function() return '{}' end,
  jsonDecode = function(_, fallback) return fallback or {} end
}
MZPlayerService = {
  getPlayer = function(source)
    if tonumber(source) == 1 then return { source = 1, citizenid = 'MZ000001' } end
  end,
  isPlayerLoaded = function(source) return tonumber(source) == 1 end
}
MZPlayerStateService = {
  canPerformAction = function(source)
    local allowed = tonumber(source) == 1
    return allowed, { allowed = allowed }
  end
}
MZInventoryRepository = {
  getInventory = function() return rows end,
  clearInvalidPlayerHotbarRefs = function() return 0 end,
  updateMetadataBySlot = function(_, _, _, slot, metadata)
    local row = findRow(slot)
    if row then row.metadata = metadata end
    return true
  end,
  buildDeleteSlotStatement = function(_, _, _, slot)
    return { query = 'DELETE_SLOT', parameters = { slot } }
  end,
  buildUpdateAmountBySlotStatement = function(_, _, _, slot, amount)
    return { query = 'UPDATE_AMOUNT', parameters = { slot, amount } }
  end,
  buildUpdateMetadataBySlotStatement = function(_, _, _, slot, metadata)
    return { query = 'UPDATE_METADATA', parameters = { slot, metadata } }
  end,
  runTransaction = function(statements)
    for _, statement in ipairs(statements or {}) do
      local slot = statement.parameters[1]
      if statement.query == 'DELETE_SLOT' then
        deleteRow(slot)
      elseif statement.query == 'UPDATE_AMOUNT' then
        findRow(slot).amount = statement.parameters[2]
      elseif statement.query == 'UPDATE_METADATA' then
        findRow(slot).metadata = statement.parameters[2]
      end
    end
    return true
  end
}
MZOrgService = {}
MZInventoryWorldRepository = {}
MZLogService = nil
MySQL = { query = { await = function() return {} end } }
json = { encode = function() return '{}' end, decode = function() return {} end }

function GetGameTimer() return clock end
function Wait() end
function GetResourceState() return 'missing' end
function TriggerClientEvent(eventName, _, payload)
  if eventName == 'mz_core:client:inventory:equipWeapon' then equippedPayload = payload end
  if eventName == 'mz_core:client:inventory:applyWeaponAmmo' then appliedPayload = payload end
end
function joaat(value)
  if value == 'WEAPON_PISTOL' then return 453432689 end
  if value == 'WEAPON_MG' then return -1660422300 end
  return 0
end
GetHashKey = joaat

dofile('server/inventory/service.lua')

expect(MZInventoryService.usePlayerItem(1, 4) == true, 'equip inicial falhou')
local equipped = MZInventoryService.getEquippedWeaponState(1)
expect(equipped.ammo == 5 and equipped.clipAmmo == 2 and equipped.ammoRevision == 3, 'pente persistido nao foi equipado')

local nonce = equippedPayload and equippedPayload.equip_nonce
expect(type(nonce) == 'string' and nonce ~= '', 'nonce interno de teste ausente')

local ok, result = MZInventoryService.reloadEquippedWeaponFromInventory(1, {
  instance_uid = 'MZINV-PISTOL-RELOAD', equip_nonce = nonce,
  ammo_revision = 3, ammo = 5, clip_ammo = 2
})
expect(ok == true, 'recarga automatica falhou: ' .. tostring(result))
expect(result.ammo == 17 and result.clip_ammo == 12 and result.rounds_added == 12, 'resultado da recarga incorreto')
expect(findRow(5).amount == 1, 'pacote de municao nao foi consumido uma unica vez')
expect(findRow(4).metadata.ammo == 17 and findRow(4).metadata.clip_ammo == 12, 'municao nao foi persistida atomicamente')
expect(appliedPayload and appliedPayload.ammo == 17 and appliedPayload.clip_ammo == 12 and appliedPayload.ammo_revision == 4, 'payload autoritativo incorreto')

local fullOk, fullErr = MZInventoryService.reloadEquippedWeaponFromInventory(1, {
  instance_uid = 'MZINV-PISTOL-RELOAD', equip_nonce = nonce,
  ammo_revision = 4, ammo = 17, clip_ammo = 12
})
expect(fullOk == false and fullErr == 'weapon_clip_full', 'pente cheio consumiu item ou retornou erro incorreto')
expect(findRow(5).amount == 1, 'pente cheio consumiu municao')

local updateOk = MZInventoryService.updateEquippedWeaponAmmo(1, {
  instance_uid = 'MZINV-PISTOL-RELOAD', equip_nonce = nonce,
  ammo_revision = 4, ammo = 14, clip_ammo = 9
})
expect(updateOk == true, 'persistencia de disparos falhou')

local reserveOk, reserveResult = MZInventoryService.reloadEquippedWeaponFromInventory(1, {
  instance_uid = 'MZINV-PISTOL-RELOAD', equip_nonce = nonce,
  ammo_revision = 4, ammo = 14, clip_ammo = 9
})
expect(reserveOk == true and reserveResult.ammo == 14 and reserveResult.clip_ammo == 12, 'reserva interna nao recarregou o pente')
expect(reserveResult.ammo_items_consumed == 0 and findRow(5).amount == 1, 'reserva interna consumiu item do inventario')

local staleOk, staleErr = MZInventoryService.reloadEquippedWeaponFromInventory(1, {
  instance_uid = 'MZINV-PISTOL-RELOAD', equip_nonce = nonce,
  ammo_revision = 4, ammo = 14, clip_ammo = 12
})
expect(staleOk == false and staleErr == 'weapon_ammo_revision_mismatch', 'revisao antiga foi aceita')

expect(MZInventoryService.usePlayerItem(1, 4) == true, 'toggle de desequipar falhou')
rows = {
  {
    slot = 4, item = 'weapon_mg', amount = 1, instance_uid = 'MZINV-MG-RELOAD',
    metadata = { uid = 'MZINV-MG-RELOAD', ammo = 0, clip_ammo = 0, ammo_revision = 0 }
  },
  { slot = 5, item = 'ammo_heavy', amount = 4, metadata = {} }
}
expect(MZInventoryService.usePlayerItem(1, 4) == true, 'equip da arma pesada falhou')
nonce = equippedPayload and equippedPayload.equip_nonce

local multiOk, multiResult = MZInventoryService.reloadEquippedWeaponFromInventory(1, {
  instance_uid = 'MZINV-MG-RELOAD', equip_nonce = nonce,
  ammo_revision = 0, ammo = 0, clip_ammo = 0
})
expect(multiOk == true and multiResult.ammo == 60 and multiResult.clip_ammo == 54, 'recarga com varios pacotes calculou municao incorreta')
expect(multiResult.ammo_items_consumed == 3 and findRow(5).amount == 1, 'recarga pesada nao consumiu exatamente tres pacotes')

clock = clock + 1000
expect(MZInventoryService.updateEquippedWeaponAmmo(1, {
  instance_uid = 'MZINV-MG-RELOAD', equip_nonce = nonce,
  ammo_revision = 1, ammo = 0, clip_ammo = 0
}) == true, 'zerar municao para o cenario sem reserva falhou')
deleteRow(5)
local noAmmoOk, noAmmoErr = MZInventoryService.reloadEquippedWeaponFromInventory(1, {
  instance_uid = 'MZINV-MG-RELOAD', equip_nonce = nonce,
  ammo_revision = 1, ammo = 0, clip_ammo = 0
})
expect(noAmmoOk == false and noAmmoErr == 'weapon_reload_no_ammo', 'ausencia de municao compativel nao foi detectada')

local clientSource = assert(io.open('client/inventory.lua', 'rb')):read('*a')
expect(clientSource:find('DisableControlAction(0, RELOAD_CONTROL, true)', 1, true) ~= nil, 'controle nativo de recarga nao foi interceptado')
expect(clientSource:find("lib.callback.await('mz_core:server:inventory:reloadWeapon'", 1, true) ~= nil, 'callback de recarga automatica ausente')
expect(clientSource:find('clip_ammo = clipForServer', 1, true) ~= nil, 'pente nao e enviado na persistencia periodica')

local eventSource = assert(io.open('server/inventory/events.lua', 'rb')):read('*a')
expect(eventSource:find("lib.callback.register('mz_core:server:inventory:reloadWeapon'", 1, true) ~= nil, 'callback server-side de recarga ausente')

print('weapon_inventory_reload_harness: ok')
