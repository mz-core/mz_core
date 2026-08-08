local function expect(condition, message)
  if not condition then error(message, 2) end
end

MZ_INVENTORY_TRANSFER_TESTING = true

local players = {
  [1] = { source = 1, citizenid = 'MZ000001' },
  [2] = { source = 2, citizenid = 'MZ000002' },
  [3] = { source = 3, citizenid = 'MZ000003' }
}
local allowed = { [1] = true, [2] = true, [3] = true }
local coords = {
  [1] = { x = 0, y = 0, z = 0 },
  [2] = { x = 2, y = 0, z = 0 },
  [3] = { x = 8, y = 0, z = 0 }
}
local buckets = { [1] = 0, [2] = 0, [3] = 0 }
local inventoryRows = {
  MZ000001 = {
    { slot = 1, item = 'water', amount = 5, metadata = {}, instance_uid = 'water-source' }
  },
  MZ000002 = {},
  MZ000003 = {}
}
local transactions = {}
local clientEvents = {}
local clock = 1000

Config = {
  Inventory = {
    defaultSlots = 40,
    defaultWeight = 50000,
    playerTransferDistance = 3.0
  },
  Weapons = {}
}
MZConstants = {
  InventoryTypes = {
    MAIN = 'main',
    STASH = 'stash',
    TRUNK = 'trunk',
    GLOVEBOX = 'glovebox',
    DROP = 'drop'
  }
}
MZItems = {
  water = {
    label = 'Agua',
    weight = 500,
    stack = true,
    unique = false,
    usable = true
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
  getPlayer = function(source) return players[tonumber(source)] end
}
MZPlayerStateService = {
  canPerformAction = function(source)
    local permitted = allowed[tonumber(source)] == true
    return permitted, { allowed = permitted }
  end
}
MZInventoryRepository = {
  getInventory = function(_, ownerId)
    return inventoryRows[tostring(ownerId)] or {}
  end,
  runTransaction = function(statements)
    transactions[#transactions + 1] = statements
    return true
  end,
  buildSetSlotStatement = function(payload)
    return { query = 'set', parameters = payload }
  end,
  buildDeleteSlotStatement = function(_, ownerId, _, slot)
    return { query = 'delete', parameters = { ownerId, slot } }
  end,
  buildUpdateAmountBySlotStatement = function(_, ownerId, _, slot, amount)
    return { query = 'update_amount', parameters = { ownerId, slot, amount } }
  end,
  buildUpdateMetadataBySlotStatement = function()
    return { query = 'update_metadata', parameters = {} }
  end,
  clearInvalidPlayerHotbarRefs = function() return 0 end
}
MZOrgService = {}
MZLogService = nil
MySQL = { query = { await = function() return {} end } }
json = {
  encode = function() return '{}' end,
  decode = function() return {} end
}

function GetPlayers() return { '1', '2', '3' } end
function GetPlayerPed(source) return tonumber(source) or 0 end
function GetEntityCoords(ped) return coords[tonumber(ped)] end
function GetPlayerRoutingBucket(source) return buckets[tonumber(source)] end
function GetPlayerName(source) return ('Player %s'):format(tostring(source)) end
function GetGameTimer() clock = clock + 1 return clock end
function Wait() clock = clock + 1 end
function GetResourceState() return 'missing' end
function TriggerClientEvent(eventName, target, payload)
  clientEvents[#clientEvents + 1] = {
    event = eventName,
    target = target,
    payload = payload
  }
end
function joaat() return 0 end
GetHashKey = joaat

dofile('server/inventory/service.lua')

local nearest, distance = MZInventoryService._transferTest.findClosestPlayerTransferTarget(1)
expect(nearest == 2 and math.abs(distance - 2) < 0.001, 'jogador mais proximo nao foi resolvido')

local response = MZInventoryService.giveInventoryItemAction(1, { slot = 1, amount = 2 })
expect(response.ok == true, 'entrega valida foi rejeitada')
expect(response.data.target_source == 2 and response.data.amount == 2, 'destinatario ou quantidade incorretos')
expect(response.data.to_slot == 1, 'primeiro slot livre nao foi escolhido')
expect(#transactions == 1 and #transactions[1] == 2, 'entrega nao gerou mutacao atomica esperada')
expect(#clientEvents == 1 and clientEvents[1].target == 2, 'destinatario nao recebeu notificacao')

inventoryRows.MZ000002 = {
  { slot = 4, item = 'water', amount = 3, metadata = {}, instance_uid = 'water-target' }
}
response = MZInventoryService.giveInventoryItemAction(1, { slot = 1, amount = 2 })
expect(response.ok == true and response.data.to_slot == 4, 'stack compativel do destinatario nao foi reutilizado')

allowed[2] = false
response = MZInventoryService.giveInventoryItemAction(1, { slot = 1, amount = 1 })
expect(response.ok == false and response.error.code == 'target_state_blocked', 'destinatario bloqueado recebeu item')
allowed[2] = true

buckets[2] = 1
response = MZInventoryService.giveInventoryItemAction(1, { slot = 1, amount = 1 })
expect(response.ok == false and response.error.code == 'no_nearby_player', 'jogador de outra dimensao foi aceito')
buckets[2] = 0

coords[2] = { x = 4, y = 0, z = 0 }
response = MZInventoryService.giveInventoryItemAction(1, { slot = 1, amount = 1 })
expect(response.ok == false and response.error.code == 'no_nearby_player', 'distancia maxima nao foi aplicada')

print('inventory_player_transfer_harness: ok')
