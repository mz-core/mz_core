local function expect(condition, message)
  if not condition then error(message, 2) end
end

MZ_INVENTORY_PHONE_ACCESS_TESTING = true

local rows = {
  { slot = 1, item = 'cellphone', amount = 1, metadata = { owner = 'MZ000001' }, instance_uid = 'phone-instance-1' },
  { slot = 2, item = 'cellphone', amount = 1, metadata = {}, instance_uid = 'phone-instance-2' }
}
local uidSequence = 0
local clock = 1000
local handlers = {}

Config = { Inventory = { defaultSlots = 40, defaultWeight = 50000 }, Weapons = {} }
MZConstants = { InventoryTypes = { MAIN = 'main', STASH = 'stash', TRUNK = 'trunk', GLOVEBOX = 'glovebox', DROP = 'drop' } }
MZItems = { cellphone = { label = 'Phone', weight = 500, stack = false, unique = true, usable = true } }
MZUtils = {
  tableClone = function(input)
    local output = {}
    for key, value in pairs(input or {}) do output[key] = value end
    return output
  end,
  generateInstanceUid = function(prefix)
    uidSequence = uidSequence + 1
    return ('%s-%s'):format(prefix or 'UID', uidSequence)
  end,
  generateItemSerial = function() return 'serial' end,
  jsonEncode = function() return '{}' end,
  jsonDecode = function(_, fallback) return fallback or {} end
}
MZPlayerService = { getPlayer = function(source)
  return tonumber(source) == 1 and { source = 1, citizenid = 'MZ000001' }
    or tonumber(source) == 2 and { source = 2, citizenid = 'MZ000002' } or nil
end }
MZPlayerStateService = { canPerformAction = function() return true, { allowed = true } end }
MZInventoryRepository = {
  getInventory = function(ownerType, ownerId, inventoryType)
    if ownerType == 'player' and ownerId == 'MZ000001' and inventoryType == 'main' then return rows end
    return {}
  end,
  runTransaction = function() return true end,
  clearInvalidPlayerHotbarRefs = function() return 0 end
}
MZOrgService = {}
MZLogService = nil
MySQL = { query = { await = function() return {} end } }
json = { encode = function() return '{}' end, decode = function() return {} end }

function GetGameTimer() return clock end
function Wait(milliseconds) clock = clock + math.max(1, tonumber(milliseconds) or 1) end
function TriggerEvent() end
function TriggerClientEvent() end
function AddEventHandler(name, handler)
  handlers[name] = handlers[name] or {}
  handlers[name][#handlers[name] + 1] = handler
end
function joaat() return 0 end
GetHashKey = joaat

dofile('server/inventory/service.lua')

local ok, ambiguousErr = MZInventoryService.acquireItemAccess(1, nil, 'cellphone', 'phone.device', 'mz_phone')
expect(ok == false and ambiguousErr == 'item_selection_required', 'seletor ambiguo nao foi rejeitado')

local acquired, lease = MZInventoryService.acquireItemAccess(1, 'phone-instance-1', 'cellphone', 'phone.device', 'mz_phone')
expect(acquired == true and lease.instance_uid == 'phone-instance-1', 'lease da instancia nao foi adquirido')
expect(lease.metadata.owner == 'MZ000001', 'snapshot de metadata nao foi preservado')

local wrongHolder, wrongHolderErr = MZInventoryService.validateItemAccess(2, lease.access_token, 'mz_phone')
expect(wrongHolder == false and wrongHolderErr == 'item_access_holder_mismatch', 'holder incorreto validou lease')

local begun, permit = MZInventoryService.beginItemOperation(1, lease.access_token, 'mz_phone')
expect(begun == true and permit.permit_token ~= nil, 'permit nao foi iniciado')

clock = clock + 600000
local blocked, blockedErr = MZInventoryService.acquireItemAccess(1, 'phone-instance-2', 'cellphone', 'phone.device', 'mz_phone')
expect(blocked == false and blockedErr == 'inventory_busy', 'deadline liberou lock ativo silenciosamente')

local wrongEnd, wrongEndErr = MZInventoryService.endItemOperation(2, permit.permit_token, 'mz_phone')
expect(wrongEnd == false and wrongEndErr == 'item_operation_holder_mismatch', 'outro holder encerrou permit')

local ended = MZInventoryService.endItemOperation(1, permit.permit_token, 'mz_phone')
expect(ended == true, 'fim explicito nao liberou permit')

local acquiredAfterEnd = MZInventoryService.acquireItemAccess(1, 'phone-instance-2', 'cellphone', 'phone.device', 'mz_phone')
expect(acquiredAfterEnd == true, 'lock permaneceu depois do fim explicito')

local lifecycleLeaseOk, lifecycleLease = MZInventoryService.acquireItemAccess(1, 'phone-instance-1', 'cellphone', 'phone.device', 'mz_phone')
expect(lifecycleLeaseOk == true, 'lease para cleanup nao foi criado')
for _, handler in ipairs(handlers.playerDropped or {}) do
  source = 1
  handler()
end
local stillValid = MZInventoryService.validateItemAccess(1, lifecycleLease.access_token, 'mz_phone')
expect(stillValid == false, 'playerDropped deixou lease ativo')

local stopLeaseOk, stopLease = MZInventoryService.acquireItemAccess(1, 'phone-instance-1', 'cellphone', 'phone.device', 'mz_phone')
expect(stopLeaseOk == true, 'lease para resource stop nao foi criado')
local stopBegun = MZInventoryService.beginItemOperation(1, stopLease.access_token, 'mz_phone')
expect(stopBegun == true, 'permit para resource stop nao foi criado')
for _, handler in ipairs(handlers.onResourceStop or {}) do handler('mz_phone') end
local afterStop = MZInventoryService.validateItemAccess(1, stopLease.access_token, 'mz_phone')
expect(afterStop == false, 'mz_phone stop deixou lease/permit ativo')

print('inventory_item_access_harness: ok')
