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
    amount = 24,
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
    type = 'ammo', ammoType = 'ammo_pistol', reloadAmount = 1,
    stack = true, usable = true
  },
  weapon_mg = {
    type = 'weapon', weapon = 'WEAPON_MG', ammoType = 'ammo_heavy',
    unique = true, usable = true, maxAmmo = 240, defaultAmmo = 0, clipSize = 54
  },
  ammo_heavy = {
    type = 'ammo', ammoType = 'ammo_heavy', reloadAmount = 1,
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
expect(result.ammo == 12 and result.clip_ammo == 12 and result.rounds_added == 7, 'resultado da recarga por bala incorreto')
expect(result.ammo_items_consumed == 7, 'recarga nao consumiu exatamente as balas faltantes')
expect(findRow(5).amount == 17, 'saldo de balas do inventario incorreto')
expect(findRow(4).metadata.ammo == 12 and findRow(4).metadata.clip_ammo == 12, 'municao nao foi persistida atomicamente')
expect(appliedPayload and appliedPayload.ammo == 12 and appliedPayload.clip_ammo == 12 and appliedPayload.ammo_revision == 4, 'payload autoritativo incorreto')
expect(appliedPayload.animate_reload == true, 'recarga automatica nao solicitou animacao nativa')
expect(appliedPayload.inventory_ammo == 17, 'saldo de municao do inventario nao foi publicado')

local fullOk, fullErr = MZInventoryService.reloadEquippedWeaponFromInventory(1, {
  instance_uid = 'MZINV-PISTOL-RELOAD', equip_nonce = nonce,
  ammo_revision = 4, ammo = 12, clip_ammo = 12
})
expect(fullOk == false and fullErr == 'weapon_clip_full', 'pente cheio consumiu item ou retornou erro incorreto')
expect(findRow(5).amount == 17, 'pente cheio consumiu municao')

local updateOk = MZInventoryService.updateEquippedWeaponAmmo(1, {
  instance_uid = 'MZINV-PISTOL-RELOAD', equip_nonce = nonce,
  ammo_revision = 4, ammo = 9, clip_ammo = 9
})
expect(updateOk == true, 'persistencia de disparos falhou')

local refillOk, refillResult = MZInventoryService.reloadEquippedWeaponFromInventory(1, {
  instance_uid = 'MZINV-PISTOL-RELOAD', equip_nonce = nonce,
  ammo_revision = 4, ammo = 9, clip_ammo = 9
})
expect(refillOk == true and refillResult.ammo == 12 and refillResult.clip_ammo == 12, 'recarga parcial por bala falhou')
expect(refillResult.ammo_items_consumed == 3 and findRow(5).amount == 14, 'recarga parcial nao consumiu tres balas')

local staleOk, staleErr = MZInventoryService.reloadEquippedWeaponFromInventory(1, {
  instance_uid = 'MZINV-PISTOL-RELOAD', equip_nonce = nonce,
  ammo_revision = 4, ammo = 12, clip_ammo = 12
})
expect(staleOk == false and staleErr == 'weapon_ammo_revision_mismatch', 'revisao antiga foi aceita')

expect(MZInventoryService.usePlayerItem(1, 4) == true, 'toggle de desequipar falhou')
rows = {
  {
    slot = 4, item = 'weapon_mg', amount = 1, instance_uid = 'MZINV-MG-RELOAD',
    metadata = { uid = 'MZINV-MG-RELOAD', ammo = 0, clip_ammo = 0, ammo_revision = 0 }
  },
  { slot = 5, item = 'ammo_heavy', amount = 80, metadata = {} }
}
expect(MZInventoryService.usePlayerItem(1, 4) == true, 'equip da arma pesada falhou')
nonce = equippedPayload and equippedPayload.equip_nonce

local multiOk, multiResult = MZInventoryService.reloadEquippedWeaponFromInventory(1, {
  instance_uid = 'MZINV-MG-RELOAD', equip_nonce = nonce,
  ammo_revision = 0, ammo = 0, clip_ammo = 0
})
expect(multiOk == true and multiResult.ammo == 54 and multiResult.clip_ammo == 54, 'recarga pesada por bala calculou municao incorreta')
expect(multiResult.ammo_items_consumed == 54 and findRow(5).amount == 26, 'recarga pesada nao consumiu exatamente cinquenta e quatro balas')

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
expect(clientSource:find("RegisterKeyMapping('mz_weapon_reload'", 1, true) ~= nil, 'mapeamento confiavel da tecla R ausente')
expect(clientSource:find('MakePedReload(ped)', 1, true) ~= nil, 'animacao nativa de recarga ausente')
expect(clientSource:find("publishWeaponHudState('reload_started')", 1, true) ~= nil, 'HUD nao recebe o inicio da recarga')
expect(clientSource:find("RegisterNetEvent('mz_core:client:inventory:weaponInventoryAmmo'", 1, true) ~= nil, 'saldo de balas do inventario nao atualiza a HUD')
expect(clientSource:find('clip_ammo = clipForServer', 1, true) ~= nil, 'pente nao e enviado na persistencia periodica')
expect(clientSource:find("sendWeaponAmmoUpdate('before_hotbar_use', true)", 1, true) ~= nil, 'hotbar nao persiste disparos antes da troca')
expect(clientSource:find("exports('FlushEquippedWeaponAmmo'", 1, true) ~= nil, 'export de flush para o inventario ausente')
local clipResultCheck = assert(clientSource:find("if type(clip) == 'number' then", 1, true))
local boolResultCheck = assert(clientSource:find("if type(ok) == 'number' then", 1, true))
expect(clipResultCheck < boolResultCheck, 'quantidade real do pente nao tem prioridade sobre o BOOL numerico')

local eventSource = assert(io.open('server/inventory/events.lua', 'rb')):read('*a')
expect(eventSource:find("lib.callback.register('mz_core:server:inventory:reloadWeapon'", 1, true) ~= nil, 'callback server-side de recarga ausente')
expect(eventSource:find("lib.callback.register('mz_core:server:inventory:syncWeaponAmmo'", 1, true) ~= nil, 'flush sincrono de municao ausente')

local itemsSource = assert(io.open('shared/items.lua', 'rb')):read('*a')
local ammoItems = { 'ammo_pistol', 'ammo_smg', 'ammo_shotgun', 'ammo_rifle', 'ammo_sniper', 'ammo_heavy', 'ammo_rpg' }
for index, ammoItem in ipairs(ammoItems) do
  local blockStart = assert(itemsSource:find(ammoItem .. ' = {', 1, true))
  local nextItem = ammoItems[index + 1]
  local blockEnd = nextItem and assert(itemsSource:find(nextItem .. ' = {', blockStart + 1, true)) or #itemsSource
  local block = itemsSource:sub(blockStart, blockEnd - 1)
  expect(block and block:find('reloadAmount%s*=%s*1'), ammoItem .. ' ainda representa pacote/pente')
end

local prepareSource = assert(io.open('server/prepare.lua', 'rb')):read('*a')
expect(prepareSource:find('inventory_ammo_individual_rounds_v1', 1, true) ~= nil, 'migracao idempotente de pacotes para balas ausente')

print('weapon_inventory_reload_harness: ok')
