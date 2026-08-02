local function expect(condition, message)
  if not condition then error(message, 2) end
end

Config = { OwnerAce = 'group.mz_owner' }
MZCoreState = { ready = true }
local balance = 1000
local sequence = 0
local operations = {}
local receipts = {}
local reversals = {}
local org = {
  id = 4, code = 'mafia', active = true,
  has_shared_account = true
}
local player = { citizenid = 'CID001', charinfo = { firstname = 'Teste', lastname = 'Mafia' } }

MZUtils = { jsonEncode = function() return '{}' end }
MZPlayerService = { getPlayer = function(source) return source == 1 and player or nil end }
MZOrgRepository = { getOrgByCode = function(code) return code == 'mafia' and org or nil end }
MZOrgService = {
  hasGlobalPermission = function() return false end,
  canOrg = function(source, code, capability)
    return source == 1 and code == 'mafia' and capability == 'facility.purchase'
  end
}
MZAccountService = {
  WithFinancialLocksInternal = function(_, handler) return handler() end,
  GenerateFinancialTransactionRefInternal = function(prefix)
    sequence = sequence + 1
    return ('%s-%04d'):format(prefix, sequence)
  end,
  NormalizeFinancialLedgerOptionsInternal = function(options)
    return {
      category = options.category, reason = options.reason,
      source_resource = options.__invokingResource,
      source_type = options.source_type,
      counts_as_expense = options.counts_as_expense,
      related_org_code = options.related_org_code,
      external_ref = options.external_ref
    }
  end,
  BuildFinancialOutboxInternal = function() return nil end,
  BuildFinancialLedgerEntryInternal = function() return {} end,
  RecordEconomyTransactionSafe = function() return true end
}
MZAccountRepository = {}

function MZAccountRepository.getOrgAccountOperation(resource, key)
  return operations[resource .. '|' .. key]
end
function MZAccountRepository.getOrgAccountOperationByReceipt(receipt)
  return receipts[receipt]
end
function MZAccountRepository.getOrgAccountReversal(operationId)
  return reversals[tonumber(operationId)]
end
function MZAccountRepository.createOrgAccountOperation(data)
  sequence = sequence + 1
  local row = {
    id = sequence, source_resource = data.sourceResource,
    operation_key = data.operationKey, operation_type = data.operationType,
    purpose = data.purpose, org_id = data.orgId, org_code = data.orgCode,
    actor_citizenid = data.actorCitizenId, amount = data.amount,
    related_ref = data.relatedRef, request_fingerprint = data.fingerprint,
    status = data.status, error_code = data.errorCode,
    reversal_of_operation_id = data.reversalOfOperationId
  }
  operations[data.sourceResource .. '|' .. data.operationKey] = row
  if data.reversalOfOperationId then reversals[data.reversalOfOperationId] = row end
  return row.id
end
function MZAccountRepository.rejectOrgAccountOperation(operationId, errorCode)
  for _, row in pairs(operations) do
    if row.id == operationId and row.status == 'pending' then
      row.status, row.error_code = 'rejected', errorCode
      return true
    end
  end
  return false
end
function MZAccountRepository.applyOrgAccountOperation(data)
  for _, row in pairs(operations) do
    if row.id == data.operationId and row.status == 'pending' and balance == data.balanceBefore then
      balance = data.balanceAfter
      row.status, row.balance_before, row.balance_after = 'applied', data.balanceBefore, data.balanceAfter
      row.receipt_id, row.correlation_id = data.receiptId, data.correlationId
      receipts[data.receiptId] = row
      return true
    end
  end
  return true
end

MySQL = {
  single = { await = function(query)
    if query:find('mz_org_accounts', 1, true) then return { balance = balance } end
  end },
  insert = { await = function() return 1 end },
  query = { await = function() return {} end },
  update = { await = function() return 1 end }
}
function GetPlayerName() return 'Teste Mafia' end
function GetGameTimer() return sequence end
function GetInvokingResource() return 'mz_org_activities' end
exports = function() end

dofile('mz_core/server/accounts/org_accounts.lua')

local spendOk, spend = MZOrgAccountService.spend(1, 'mafia', 400, {
  operationKey = 'facility_purchase:test0001',
  purpose = 'facility_purchase', relatedRef = 'facility_purchase:test0001',
  reason = 'test purchase'
}, 'mz_org_activities')
expect(spendOk and spend.amount == 400 and spend.balanceAfter == 600, 'spend must debit once')
expect(balance == 600 and spend.replayed == false, 'spend balance or replay flag invalid')

local replayOk, replay = MZOrgAccountService.spend(1, 'mafia', 400, {
  operationKey = 'facility_purchase:test0001',
  purpose = 'facility_purchase', relatedRef = 'facility_purchase:test0001',
  reason = 'test purchase'
}, 'mz_org_activities')
expect(replayOk and replay.replayed == true and balance == 600, 'spend replay duplicated debit')

local conflictOk, conflictErr = MZOrgAccountService.spend(1, 'mafia', 300, {
  operationKey = 'facility_purchase:test0001',
  purpose = 'facility_purchase', relatedRef = 'facility_purchase:test0001'
}, 'mz_org_activities')
expect(not conflictOk and conflictErr == 'idempotency_conflict', 'changed replay must conflict')

local refundOk, refund = MZOrgAccountService.refund(1, 'mafia', spend.receiptId, {
  operationKey = 'facility_refund:test0001', reason = 'persistence failed'
}, 'mz_org_activities')
expect(refundOk and refund.amount == 400 and balance == 1000, 'refund must restore exact spend')

local refundReplayOk, refundReplay = MZOrgAccountService.refund(1, 'mafia', spend.receiptId, {
  operationKey = 'facility_refund:test0001', reason = 'persistence failed'
}, 'mz_org_activities')
expect(refundReplayOk and refundReplay.replayed == true and balance == 1000,
  'refund replay duplicated credit')

local secondRefundOk, secondRefundErr = MZOrgAccountService.refund(1, 'mafia', spend.receiptId, {
  operationKey = 'facility_refund:test0002', reason = 'duplicate refund'
}, 'mz_org_activities')
expect(not secondRefundOk and secondRefundErr == 'spend_already_refunded',
  'a spend receipt must allow only one refund')

local insufficientOk, insufficientErr = MZOrgAccountService.spend(1, 'mafia', 1500, {
  operationKey = 'facility_purchase:test0002',
  purpose = 'facility_purchase', relatedRef = 'facility_purchase:test0002'
}, 'mz_org_activities')
expect(not insufficientOk and insufficientErr == 'insufficient_org_funds',
  'insufficient spend must be rejected')
balance = 2000
local rejectedReplayOk, rejectedReplayErr = MZOrgAccountService.spend(1, 'mafia', 1500, {
  operationKey = 'facility_purchase:test0002',
  purpose = 'facility_purchase', relatedRef = 'facility_purchase:test0002'
}, 'mz_org_activities')
expect(not rejectedReplayOk and rejectedReplayErr == 'insufficient_org_funds' and balance == 2000,
  'rejected key must not become payable after balance changes')

print('[mz_core][test] org account commerce harness passed')
