local function expect(condition, message)
  if not condition then error(message, 2) end
end

local clock = 1000
local clientEvents = 0
local loaded = { [1] = true, [3] = true }
local players = {
  [1] = { source = 1, citizenid = 'MZ000001' },
  [3] = { source = 3, citizenid = 'MZ000003' }
}
local rows = {
  {
    slot = 4,
    item = 'weapon_pistol',
    amount = 1,
    instance_uid = 'MZINV-PISTOL-1',
    metadata = { uid = 'MZINV-PISTOL-1', serial = 'SERIAL-1', ammo = 12, ammo_revision = 3, durability = 98 }
  }
}

Config = {
  Inventory = { defaultSlots = 40, defaultWeight = 50000 },
  Weapons = { enforceInventoryWeapons = true }
}
MZConstants = { InventoryTypes = { MAIN = 'main', STASH = 'stash', TRUNK = 'trunk', GLOVEBOX = 'glovebox', DROP = 'drop' } }
MZItems = {
  weapon_pistol = {
    type = 'weapon', weapon = 'WEAPON_PISTOL', ammoType = 'ammo_pistol',
    unique = true, usable = true, maxAmmo = 120, defaultAmmo = 12, clipSize = 12
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
  getPlayer = function(source) return players[tonumber(source)] end,
  isPlayerLoaded = function(source) return loaded[tonumber(source)] == true end
}
MZPlayerStateService = {
  canPerformAction = function(source, action)
    return loaded[tonumber(source)] == true, {
      allowed = loaded[tonumber(source)] == true and action == 'inventory.use'
    }
  end
}
MZInventoryRepository = {
  getInventory = function() return rows end,
  buildDeleteSlotStatement = function()
    return { query = 'DELETE FROM mz_inventory_items', parameters = {} }
  end,
  runTransaction = function(statements)
    for _, statement in ipairs(statements or {}) do
      if tostring(statement.query or ''):find('DELETE FROM mz_inventory_items', 1, true) then rows = {} end
    end
    return true
  end,
  clearInvalidPlayerHotbarRefs = function() return 0 end,
  updateMetadataBySlot = function() return true end
}
MZOrgService = {}
MZInventoryWorldRepository = {}
MZLogService = nil
MySQL = { query = { await = function() return {} end } }
json = { encode = function() return '{}' end, decode = function() return {} end }

function GetGameTimer() return clock end
function Wait() end
function GetResourceState() return 'missing' end
function TriggerClientEvent() clientEvents = clientEvents + 1 end
function joaat(value)
  if value == 'WEAPON_PISTOL' then return 453432689 end
  return 0
end
GetHashKey = joaat

dofile('server/inventory/service.lua')

local invalid, invalidReason = MZInventoryService.getEquippedWeaponState(0)
expect(invalid == nil and invalidReason == 'invalid_source', 'source invalido foi aceito')

local missing, missingReason = MZInventoryService.getEquippedWeaponState(2)
expect(missing == nil and missingReason == 'player_not_loaded', 'jogador nao carregado foi aceito')

local empty, emptyReason = MZInventoryService.getEquippedWeaponState(3)
expect(empty and empty.equipped == false and emptyReason == 'weapon_not_equipped', 'estado sem arma incorreto')

local equippedOk = MZInventoryService.usePlayerItem(1, 4)
expect(equippedOk == true, 'equip controlado falhou')

local state = MZInventoryService.getEquippedWeaponState(1)
expect(state and state.equipped == true, 'arma equipada nao foi retornada')
expect(state.weaponHash == 453432689 and state.itemName == 'weapon_pistol', 'estado sanitizado incorreto')
expect(state.ammo == 12 and state.ammoRevision == 3 and state.durability == 98, 'metadata sanitizada incorreta')
expect(state.transitionRevision == 1, 'revisao inicial da transicao nao foi registrada')
expect(state.equip_nonce == nil and state.equipNonce == nil, 'nonce foi exposto')

local authorized, authorizedReason = MZInventoryService.isWeaponAuthorized(1, 453432689)
expect(authorized == true and authorizedReason == 'weapon_authorized', 'hash correto foi negado')

local mismatch, mismatchReason = MZInventoryService.isWeaponAuthorized(1, -1074790547)
expect(mismatch == false and mismatchReason == 'weapon_hash_mismatch', 'hash diferente foi aceito')

state.ammo = 999
state.weaponName = 'MUTATED'
local fresh = MZInventoryService.getEquippedWeaponState(1)
expect(fresh.ammo == 12 and fresh.weaponName == 'WEAPON_PISTOL', 'retorno compartilha referencia mutavel')

local eventsBeforeReads = clientEvents
for _ = 1, 20 do
  local repeated = MZInventoryService.getEquippedWeaponState(1)
  expect(repeated and repeated.ammo == 12, 'consulta repetida alterou o contrato')
end
expect(clientEvents == eventsBeforeReads, 'consulta read-only produziu efeito colateral')

local removed = MZInventoryService.removePlayerItem(1, 'weapon_pistol', 1)
expect(removed == true, 'remocao controlada falhou')
local afterRemoval, afterRemovalReason = MZInventoryService.getEquippedWeaponState(1)
expect(afterRemoval and afterRemoval.equipped == false and afterRemovalReason == 'weapon_not_equipped', 'arma removida permaneceu equipada')
expect(afterRemoval.lastTransitionAt >= 1000, 'transicao server-side nao foi registrada')
expect(afterRemoval.transitionRevision == 2, 'revisao da remocao nao foi incrementada')

rows = {
  {
    slot = 4, item = 'weapon_pistol', amount = 1, instance_uid = 'MZINV-PISTOL-2',
    metadata = { uid = 'MZINV-PISTOL-2', ammo = 6, ammo_revision = 4 }
  }
}
clock = 2000
expect(MZInventoryService.usePlayerItem(1, 4) == true, 'reequip controlado falhou')
MZInventoryService.handlePlayerDropped(1, 'contract_test')
players[1], loaded[1] = nil, false
local disconnected, disconnectedReason = MZInventoryService.getEquippedWeaponState(1)
expect(disconnected == nil and disconnectedReason == 'player_not_loaded', 'disconnect manteve estado consultavel')

local exportsSource = assert(io.open('server/inventory/exports.lua', 'rb')):read('*a')
expect(exportsSource:find("exports('GetEquippedWeaponState'", 1, true) ~= nil, 'export GetEquippedWeaponState ausente')
expect(exportsSource:find("exports('IsWeaponAuthorized'", 1, true) ~= nil, 'export IsWeaponAuthorized ausente')

print('weapon_authority_contract_harness: ok')
