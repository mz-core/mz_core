local function expect(condition, message)
  if not condition then error(message, 2) end
end

MZ_INVENTORY_CONSUMABLE_TESTING = true
dofile('config.lua')
dofile('shared/items.lua')

local clock = 1000
local transactions = {}
local failAtTransaction = nil
local rows = {}

function GetGameTimer() clock = clock + 1 return clock end
function Wait() clock = clock + 1 end

MZInventoryRepository = {
  getInventory = function() return rows end,
  runTransaction = function(statements)
    transactions[#transactions + 1] = statements
    if failAtTransaction == #transactions then return false, 'forced_transaction_failure' end
    return true
  end
}
MZPlayerService = { getPlayer = function() return nil end }

dofile('server/inventory/service.lua')

local execute = MZInventoryService._consumableTest.executeInventoryMutation
local buildUsePlan = MZInventoryService._consumableTest.buildUsePlayerItemMutationPlan
local normalizeUseResult = MZInventoryService._consumableTest.normalizeUseResult
local normalizeCallable = MZInventoryService._consumableTest.normalizeCallable
local context = { ownerType = 'player', ownerId = 'MZ000001', inventoryType = 'main' }
local removeStatement = { query = 'remove', parameters = { 1 } }
local restoreStatement = { query = 'restore', parameters = { 1 } }

local remoteCalls = 0
local remoteFunctionReference = setmetatable({ __cfx_functionReference = 'mz_status:consumable:test' }, {
  __call = function(_, ...)
    remoteCalls = remoteCalls + 1
    return true, ...
  end
})
local normalizedRemote = normalizeCallable(remoteFunctionReference)
expect(type(normalizedRemote) == 'function' and normalizedRemote('payload') == true and remoteCalls == 1,
  'referencia de funcao Cfx valida nao foi normalizada')
expect(normalizeCallable({ __cfx_functionReference = 'forged-without-call' }) == nil,
  'tabela comum foi aceita como referencia de funcao Cfx')
local normalizedHooks = normalizeUseResult({ ok = true, afterCommit = remoteFunctionReference,
  onAbort = remoteFunctionReference })
expect(type(normalizedHooks.afterCommit) == 'function' and type(normalizedHooks.onAbort) == 'function',
  'hooks Cfx de commit/rollback foram descartados')
local registeredRemote, registeredRemoteErr = MZInventoryService.registerItemUseHandler('remote_test', remoteFunctionReference)
expect(registeredRemote == true and registeredRemoteErr == nil,
  'handler Cfx remoto nao foi registrado')

local effectCalls = 0
local ok, result = execute(nil, { context }, 'consume_success', function()
  return {
    statements = { removeStatement },
    rollbackStatements = { restoreStatement },
    afterCommit = function()
      effectCalls = effectCalls + 1
      return true, { operationId = 'op-success' }
    end,
    result = { ok = true, consume = true, data = {} }
  }
end)
expect(ok and effectCalls == 1 and #transactions == 1, 'sucesso nao executou remove->efeito exatamente uma vez')
expect(result.data.effect.operationId == 'op-success', 'resultado do efeito nao foi confirmado')

transactions, effectCalls = {}, 0
ok, result = execute(nil, { context }, 'consume_effect_failure', function()
  return {
    statements = { removeStatement },
    rollbackStatements = { restoreStatement },
    afterCommit = function() effectCalls = effectCalls + 1 return false, 'invalid_state' end
  }
end)
expect(not ok and result == 'invalid_state' and effectCalls == 1, 'falha de efeito nao foi propagada')
expect(#transactions == 2 and transactions[2][1] == restoreStatement, 'falha de efeito nao restaurou item sob fluxo oficial')

transactions, effectCalls = {}, 0
failAtTransaction = 1
local abortCalls = 0
ok, result = execute(nil, { context }, 'consume_remove_failure', function()
  return {
    statements = { removeStatement },
    rollbackStatements = { restoreStatement },
    onAbort = function() abortCalls = abortCalls + 1 end,
    afterCommit = function() effectCalls = effectCalls + 1 return true end
  }
end)
expect(not ok and effectCalls == 0 and #transactions == 1, 'efeito ocorreu apesar de falha na remocao')
expect(abortCalls == 1, 'falha na remocao nao limpou operacao ativa')

transactions, effectCalls = {}, 0
failAtTransaction = 2
ok, result = execute(nil, { context }, 'consume_rollback_failure', function()
  return {
    statements = { removeStatement },
    rollbackStatements = { restoreStatement },
    afterCommit = function() effectCalls = effectCalls + 1 return false, 'effect_failed' end
  }
end)
expect(not ok and result == 'inventory_rollback_failed' and #transactions == 2, 'falha de rollback nao foi tornada explicita')

transactions, effectCalls, failAtTransaction = {}, 0, nil
ok, result = execute(nil, { context }, 'consume_persistence_pending', function()
  return {
    statements = { removeStatement },
    rollbackStatements = { restoreStatement },
    afterCommit = function()
      effectCalls = effectCalls + 1
      return true, { operationId = 'op-pending', persistencePending = true }
    end,
    result = { ok = true, consume = true, data = {} }
  }
end)
expect(ok and #transactions == 1 and result.data.effect.persistencePending == true,
  'persistence_pending funcional devolveu/duplicou item')

local source = assert(io.open('server/inventory/service.lua', 'rb')):read('*a')
expect(source:find("MZPlayerStateService.canPerformAction(source, 'inventory.use')", 1, true) ~= nil,
  'guard server-side inventory.use ausente')
expect(source:find('rollbackStatements', 1, true) ~= nil, 'contrato de compensacao ausente')
expect(source:find('MZInventoryRepository.buildSetSlotStatement', 1, true) ~= nil,
  'rollback de stack removida nao restaura row exata')

local plan, planErr = buildUsePlan({ ownerType = 'player', ownerId = 'MZ000001', inventoryType = 'main', maxSlots = 10 }, 1, 0)
expect(plan == false and planErr == 'invalid_slot', 'slot invalido foi aceito')
plan, planErr = buildUsePlan({ ownerType = 'player', ownerId = 'MZ000001', inventoryType = 'main', maxSlots = 10 }, 1, 1)
expect(plan == false and planErr == 'slot_empty', 'slot vazio foi aceito')
rows = { { slot = 1, item = 'missing_item', amount = 1, metadata = {}, instance_uid = 'x' } }
plan, planErr = buildUsePlan({ ownerType = 'player', ownerId = 'MZ000001', inventoryType = 'main', maxSlots = 10 }, 1, 1)
expect(plan == false and planErr == 'item_not_found', 'item inexistente foi aceito')
rows = { { slot = 1, item = 'water', amount = 0, metadata = {}, instance_uid = 'x' } }
plan, planErr = buildUsePlan({ ownerType = 'player', ownerId = 'MZ000001', inventoryType = 'main', maxSlots = 10 }, 1, 1)
expect(plan == false and planErr == 'not_enough_amount', 'quantidade insuficiente foi aceita')

print('inventory_consumable_contract_harness: ok')
