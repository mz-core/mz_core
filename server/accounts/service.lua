MZAccountService = {}

local AccountLocks = {}
local LOCK_TIMEOUT_MS = 10000

local MONEY_ACCOUNT_ALIASES = {
  cash = 'wallet',
  money = 'wallet',
  wallet = 'wallet',
  bank = 'bank',
  dirty = 'dirty',
  black_money = 'dirty'
}

local function trim(value)
  local text = tostring(value or '')
  text = text:gsub('^%s+', '')
  text = text:gsub('%s+$', '')
  return text
end

local function normalizeMoneyType(moneyType)
  local account = trim(moneyType):lower()
  return MONEY_ACCOUNT_ALIASES[account] or account
end

function MZAccountService.NormalizeMoneyAccount(moneyType)
  local account = normalizeMoneyType(moneyType)
  if account ~= 'wallet' and account ~= 'bank' and account ~= 'dirty' then
    return nil, 'invalid_money_type'
  end

  return account
end

local function boolValue(value)
  if value == true or value == 1 then return true end
  local normalized = trim(value):lower()
  return normalized == 'true' or normalized == '1' or normalized == 'yes' or normalized == 'sim'
end

local function cloneTable(value)
  if type(value) ~= 'table' then return value end

  local out = {}
  for key, item in pairs(value) do
    out[key] = cloneTable(item)
  end
  return out
end

local function generateTransactionRef(prefix)
  return ('%s-%s-%s-%06d'):format(
    tostring(prefix or 'mzacc'),
    tostring(os.time()),
    tostring(type(GetGameTimer) == 'function' and GetGameTimer() or 0),
    math.random(0, 999999)
  )
end

local function normalizeLockKeys(keys)
  local seen = {}
  local out = {}

  for _, value in ipairs(keys or {}) do
    local key = tostring(value or '')
    if key ~= '' and not seen[key] then
      seen[key] = true
      out[#out + 1] = key
    end
  end

  table.sort(out)
  return out
end

local function acquireAccountLocks(keys)
  keys = normalizeLockKeys(keys)
  local startedAt = type(GetGameTimer) == 'function' and GetGameTimer() or 0

  while true do
    local available = true
    for _, key in ipairs(keys) do
      if AccountLocks[key] then
        available = false
        break
      end
    end

    if available then
      for _, key in ipairs(keys) do
        AccountLocks[key] = true
      end
      return true, keys
    end

    local now = type(GetGameTimer) == 'function' and GetGameTimer() or startedAt
    if now - startedAt >= LOCK_TIMEOUT_MS then
      return false, 'account_busy'
    end

    Wait(0)
  end
end

local function releaseAccountLocks(keys)
  for _, key in ipairs(keys or {}) do
    AccountLocks[key] = nil
  end
end

local function withAccountLocks(keys, handler)
  local acquired, lockKeysOrErr = acquireAccountLocks(keys)
  if not acquired then
    return false, lockKeysOrErr
  end

  local results = table.pack(pcall(handler))
  releaseAccountLocks(lockKeysOrErr)

  if results[1] ~= true then
    print(('[mz_core][accounts] locked operation failed: %s'):format(tostring(results[2])))
    return false, 'database_error'
  end

  return table.unpack(results, 2, results.n)
end

local function getInvokingResourceSafe()
  if type(GetInvokingResource) ~= 'function' then return nil end

  local ok, resource = pcall(GetInvokingResource)
  if ok and trim(resource) ~= '' then
    return trim(resource)
  end

  return nil
end

local function isMzEconomyStarted()
  if type(GetResourceState) ~= 'function' then return false end

  local ok, state = pcall(GetResourceState, 'mz_economy')
  return ok and tostring(state) == 'started'
end

local function debugLedger(message)
  if Config and Config.Debug == true then
    print(('[mz_core][accounts][ledger] %s'):format(tostring(message)))
  end
end

local function normalizeLedgerOptions(options, defaults)
  defaults = type(defaults) == 'table' and defaults or {}

  local rawMetadata = options and options.__rawMetadata or nil
  if options ~= nil and type(options) ~= 'table' then
    rawMetadata = options
    options = {}
  end

  options = type(options) == 'table' and cloneTable(options) or {}

  local data = {}
  if type(options.data) == 'table' then
    data = cloneTable(options.data)
  elseif type(options.meta) == 'table' then
    data = cloneTable(options.meta)
  elseif rawMetadata ~= nil then
    data.raw_metadata = tostring(rawMetadata)
    data.raw_metadata_type = type(rawMetadata)
    debugLedger('metadata nao-tabela normalizada')
  end

  local category = trim(options.category)
  if category == '' then
    category = trim(defaults.category)
  end
  if category == '' then category = 'unknown' end

  local reason = trim(options.reason)
  if reason == '' then
    reason = trim(defaults.reason)
  end
  if reason == '' then reason = 'legacy_call' end

  local sourceResource = trim(options.source_resource or options.sourceResource or options.__invokingResource)
  if sourceResource == '' then
    sourceResource = getInvokingResourceSafe() or ''
  end
  if sourceResource == '' then
    sourceResource = trim(defaults.sourceResource)
  end
  if sourceResource == '' then sourceResource = 'mz_core' end

  local sourceType = trim(options.source_type or options.sourceType)
  if sourceType == '' then
    sourceType = trim(defaults.sourceType)
  end
  if sourceType == '' then sourceType = 'core_legacy' end

  local relatedOrgCode = trim(options.related_org_code or options.relatedOrgCode)
  if relatedOrgCode == '' and sourceType == 'org_account' then
    relatedOrgCode = trim(options.sourceRef or options.source_ref)
  end

  local externalRef = trim(options.external_ref or options.externalRef or options.sourceRef or options.source_ref)

  return {
    reason = reason,
    category = category,
    source_resource = sourceResource,
    source_type = sourceType,
    counts_as_income = boolValue(options.counts_as_income or options.countsAsIncome),
    counts_as_expense = boolValue(options.counts_as_expense or options.countsAsExpense),
    related_citizenid = trim(options.related_citizenid or options.relatedCitizenid or options.relatedCitizenId),
    related_org_code = relatedOrgCode,
    external_ref = externalRef,
    data = data,
    original = options
  }
end

local function normalizeServiceOptions(options)
  if type(options) == 'table' then
    return cloneTable(options)
  end

  if options == nil then
    return {}
  end

  return {
    __rawMetadata = options,
    data = {
      raw_metadata = tostring(options),
      raw_metadata_type = type(options)
    }
  }
end

local function logLedgerFailure(player, action, error, detail)
  local message = ('RecordTransaction failed action=%s citizenid=%s error=%s detail=%s'):format(
    tostring(action or 'unknown'),
    tostring(player and player.citizenid or 'unknown'),
    tostring(error or 'unknown'),
    tostring(detail or '')
  )

  print(('[mz_core][accounts][ledger] %s'):format(message))

  if MZLogService and type(MZLogService.create) == 'function' then
    pcall(function()
      MZLogService.create('accounts', 'economy_ledger_failed', 'system', player and player.citizenid or 'unknown', {
        message = message,
        action = action,
        error = error,
        detail = detail
      })
    end)
  end
end

local function logStandaloneLedgerFailure(data, error, detail)
  data = type(data) == 'table' and data or {}

  local identity = data.citizenid or data.related_citizenid or data.related_org_code or data.external_ref or 'unknown'
  local message = ('RecordTransaction failed source=%s category=%s identity=%s error=%s detail=%s'):format(
    tostring(data.source_resource or 'unknown'),
    tostring(data.category or 'unknown'),
    tostring(identity),
    tostring(error or 'unknown'),
    tostring(detail or '')
  )

  print(('[mz_core][accounts][ledger] %s'):format(message))

  if MZLogService and type(MZLogService.create) == 'function' then
    pcall(function()
      MZLogService.create('accounts', 'economy_ledger_failed', 'system', tostring(identity), {
        message = message,
        error = error,
        detail = detail,
        source_resource = data.source_resource,
        source_type = data.source_type,
        category = data.category,
        external_ref = data.external_ref
      })
    end)
  end
end

function MZAccountService.RecordEconomyTransactionSafe(data)
  data = type(data) == 'table' and cloneTable(data) or {}
  data.amount = math.floor(tonumber(data.amount) or 0)

  if data.amount <= 0 then
    return false, 'invalid_amount'
  end

  if not isMzEconomyStarted() then
    debugLedger('mz_economy nao iniciado; ledger ignorado')
    return false, 'economy_offline'
  end

  local ok, result = pcall(function()
    return exports['mz_economy']:RecordTransaction(data)
  end)

  if not ok then
    logStandaloneLedgerFailure(data, 'pcall_failed', result)
    return false, 'pcall_failed'
  end

  if type(result) == 'table' and result.ok == true then
    return true, result
  end

  local error = result and result.error or 'record_failed'
  local detail = result and result.detail or nil
  logStandaloneLedgerFailure(data, error, detail)
  return false, error
end

local function recordLedgerChange(player, moneyType, beforeAmount, afterAmount, direction, amount, options)
  if not player or not player.citizenid then return end
  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then return end

  if not isMzEconomyStarted() then
    debugLedger('mz_economy nao iniciado; ledger ignorado')
    return
  end

  local defaults = {
    category = direction == 'adjustment' and 'admin_adjustment' or 'unknown',
    reason = 'legacy_call',
    sourceType = 'core_legacy',
    sourceResource = 'mz_core'
  }

  local metadata = normalizeLedgerOptions(options, defaults)

  local ok, result = pcall(function()
    return exports['mz_economy']:RecordTransaction({
      citizenid = tostring(player.citizenid),
      license = tostring(player.license or ''),
      account = moneyType,
      amount = amount,
      balance_before = math.floor(tonumber(beforeAmount) or 0),
      balance_after = math.floor(tonumber(afterAmount) or 0),
      direction = direction,
      category = metadata.category,
      reason = metadata.reason,
      source_resource = metadata.source_resource,
      source_type = metadata.source_type,
      counts_as_income = metadata.counts_as_income,
      counts_as_expense = metadata.counts_as_expense,
      related_citizenid = metadata.related_citizenid ~= '' and metadata.related_citizenid or nil,
      related_org_code = metadata.related_org_code ~= '' and metadata.related_org_code or nil,
      external_ref = metadata.external_ref ~= '' and metadata.external_ref or nil,
      metadata = metadata.data
    })
  end)

  if not ok then
    logLedgerFailure(player, direction, 'pcall_failed', result)
    return
  end

  if type(result) == 'table' and result.ok == true then
    return
  end

  logLedgerFailure(player, direction, result and result.error or 'record_failed', result and result.detail or nil)
end

local function normalizeAccountActor(source)
  if source == nil then
    return {
      type = 'system',
      id = 'system'
    }
  end

  if tonumber(source) == 0 then
    return {
      type = 'console',
      id = 'console'
    }
  end

  local player = MZPlayerService.getPlayer(source)
  if player and player.citizenid then
    return {
      type = 'player',
      id = tostring(player.citizenid),
      source = source
    }
  end

  return {
    type = 'source',
    id = tostring(source)
  }
end

local function logMoneyChange(action, player, moneyType, beforeAmount, afterAmount, delta, options)
  if not MZLogService or not player then
    return
  end

  options = options or {}

  MZLogService.createDetailed('accounts', action, {
    actor = options.actor or normalizeAccountActor(options.actorSource),
    target = {
      type = 'player_account',
      id = tostring(player.citizenid)
    },
    context = {
      citizenid = tostring(player.citizenid),
      money_type = moneyType
    },
    before = {
      amount = math.floor(tonumber(beforeAmount) or 0)
    },
    after = {
      amount = math.floor(tonumber(afterAmount) or 0)
    },
    meta = {
      delta = math.floor(tonumber(delta) or 0),
      reason = options.reason,
      source_type = options.sourceType,
      source_ref = options.sourceRef,
      extra = options.meta or {}
    }
  })
end

function MZAccountService.getMoney(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then return nil end
  return player.money
end

local function persistSingleMoneyChange(source, moneyType, nextAmount, options, direction, ledgerAmount)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, 'player_not_loaded' end

  local ok, detailOrErr = withAccountLocks({ player.citizenid }, function()
    player = MZPlayerService.getPlayer(source)
    if not player then return false, 'player_not_loaded' end

    local currentAmount = math.floor(tonumber((player.money or {})[moneyType]) or 0)
    local resolvedAmount = type(nextAmount) == 'function' and nextAmount(currentAmount) or nextAmount
    if resolvedAmount == nil then return false, 'not_enough_money' end

    resolvedAmount = math.floor(tonumber(resolvedAmount) or -1)
    if resolvedAmount < 0 then return false, 'invalid_amount' end

    local persisted = MZAccountRepository.updatePlayerMoney(player.citizenid, moneyType, resolvedAmount)
    if not persisted then return false, 'database_error' end

    player.money = player.money or {}
    player.money[moneyType] = resolvedAmount
    return true, {
      player = player,
      before = currentAmount,
      after = resolvedAmount
    }
  end)

  if not ok then return false, detailOrErr end

  local detail = detailOrErr
  local delta = detail.after - detail.before
  logMoneyChange('set_money', detail.player, moneyType, detail.before, detail.after, delta, options)

  if delta ~= 0 then
    recordLedgerChange(
      detail.player,
      moneyType,
      detail.before,
      detail.after,
      direction or 'adjustment',
      math.floor(tonumber(ledgerAmount) or math.abs(delta)),
      options
    )
  end

  return true
end

function MZAccountService.setMoney(source, moneyType, amount, options)
  local normalizedMoneyType, moneyTypeErr = MZAccountService.NormalizeMoneyAccount(moneyType)
  if not normalizedMoneyType then return false, moneyTypeErr end
  if type(amount) ~= 'number' or amount < 0 then return false, 'invalid_amount' end

  options = normalizeServiceOptions(options)
  local direction = options.__ledgerFromWrapper == true and options.__ledgerDirection or 'adjustment'
  local ledgerAmount = options.__ledgerFromWrapper == true and options.__ledgerAmount or nil
  return persistSingleMoneyChange(source, normalizedMoneyType, math.floor(amount), options, direction, ledgerAmount)
end

function MZAccountService.addMoney(source, moneyType, amount, options)
  local normalizedMoneyType, moneyTypeErr = MZAccountService.NormalizeMoneyAccount(moneyType)
  if not normalizedMoneyType then return false, moneyTypeErr end
  if type(amount) ~= 'number' or amount <= 0 then return false, 'invalid_amount' end

  local value = math.floor(amount)
  options = normalizeServiceOptions(options)
  options.reason = options.reason or 'add_money'

  return persistSingleMoneyChange(source, normalizedMoneyType, function(current)
    return current + value
  end, options, 'in', value)
end

function MZAccountService.removeMoney(source, moneyType, amount, options)
  local normalizedMoneyType, moneyTypeErr = MZAccountService.NormalizeMoneyAccount(moneyType)
  if not normalizedMoneyType then return false, moneyTypeErr end
  if type(amount) ~= 'number' or amount <= 0 then return false, 'invalid_amount' end

  local value = math.floor(amount)
  options = normalizeServiceOptions(options)
  options.reason = options.reason or 'remove_money'

  return persistSingleMoneyChange(source, normalizedMoneyType, function(current)
    if current < value then return nil end
    return current - value
  end, options, 'out', value)
end

function MZAccountService.transferMoneyBetweenAccounts(source, fromAccount, toAccount, amount, options)
  local player = MZPlayerService.getPlayer(source)
  if not player then return { ok = false, error = 'player_not_loaded' } end

  local fromNormalized, fromErr = MZAccountService.NormalizeMoneyAccount(fromAccount)
  if not fromNormalized then return { ok = false, error = fromErr } end

  local toNormalized, toErr = MZAccountService.NormalizeMoneyAccount(toAccount)
  if not toNormalized then return { ok = false, error = toErr } end
  if fromNormalized == toNormalized then return { ok = false, error = 'same_account' } end

  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then return { ok = false, error = 'invalid_amount' } end

  options = normalizeServiceOptions(options)
  options.external_ref = trim(options.external_ref or options.externalRef)
  if options.external_ref == '' then
    options.external_ref = generateTransactionRef('mzacc-own')
  end

  local ok, detailOrErr = withAccountLocks({ player.citizenid }, function()
    player = MZPlayerService.getPlayer(source)
    if not player then return false, 'player_not_loaded' end

    local fromBefore = math.floor(tonumber((player.money or {})[fromNormalized]) or 0)
    local toBefore = math.floor(tonumber((player.money or {})[toNormalized]) or 0)
    if fromBefore < amount then return false, 'not_enough_money' end

    local fromAfter = fromBefore - amount
    local toAfter = toBefore + amount
    local persisted = MZAccountRepository.transferPlayerMoney(
      player.citizenid,
      fromNormalized,
      toNormalized,
      fromAfter,
      toAfter
    )
    if not persisted then return false, 'database_error' end

    player.money[fromNormalized] = fromAfter
    player.money[toNormalized] = toAfter
    return true, {
      player = player,
      fromBefore = fromBefore,
      fromAfter = fromAfter,
      toBefore = toBefore,
      toAfter = toAfter
    }
  end)

  if not ok then return { ok = false, error = detailOrErr } end

  local detail = detailOrErr
  logMoneyChange('transfer_between_accounts_out', detail.player, fromNormalized, detail.fromBefore, detail.fromAfter, -amount, options)
  logMoneyChange('transfer_between_accounts_in', detail.player, toNormalized, detail.toBefore, detail.toAfter, amount, options)
  recordLedgerChange(detail.player, fromNormalized, detail.fromBefore, detail.fromAfter, 'out', amount, options)
  recordLedgerChange(detail.player, toNormalized, detail.toBefore, detail.toAfter, 'in', amount, options)

  return {
    ok = true,
    balances = cloneTable(detail.player.money),
    transactionRef = options.external_ref
  }
end

function MZAccountService.transferBankBetweenPlayers(source, target, amount, options)
  local sender = MZPlayerService.getPlayer(source)
  if not sender then return { ok = false, error = 'player_not_loaded' } end

  local targetSource = tonumber(target)
  local recipient
  if targetSource and targetSource > 0 then
    recipient = MZPlayerService.getPlayer(targetSource)
  else
    recipient = MZPlayerService.getPlayerByCitizenId(tostring(target or ''))
    targetSource = recipient and recipient.source or nil
  end

  if not recipient or not targetSource then return { ok = false, error = 'recipient_offline' } end
  if tostring(sender.citizenid) == tostring(recipient.citizenid) then
    return { ok = false, error = 'self_transfer' }
  end

  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then return { ok = false, error = 'invalid_amount' } end

  options = normalizeServiceOptions(options)
  local fee = math.floor(tonumber(options.fee) or 0)
  if fee < 0 then return { ok = false, error = 'invalid_fee' } end
  local totalCost = amount + fee

  options.external_ref = trim(options.external_ref or options.externalRef)
  if options.external_ref == '' then
    options.external_ref = generateTransactionRef('mzacc-transfer')
  end
  options.related_citizenid = tostring(recipient.citizenid)
  options.data = type(options.data) == 'table' and options.data or {}
  options.data.fee = fee
  options.data.transfer_amount = amount

  local ok, detailOrErr = withAccountLocks({ sender.citizenid, recipient.citizenid }, function()
    sender = MZPlayerService.getPlayer(source)
    recipient = MZPlayerService.getPlayer(targetSource)
    if not sender or not recipient then return false, 'recipient_offline' end

    local senderBefore = math.floor(tonumber((sender.money or {}).bank) or 0)
    local recipientBefore = math.floor(tonumber((recipient.money or {}).bank) or 0)
    if senderBefore < totalCost then return false, 'not_enough_money' end

    local senderAfter = senderBefore - totalCost
    local recipientAfter = recipientBefore + amount
    local persisted = MZAccountRepository.transferBankBetweenPlayers(
      sender.citizenid,
      senderAfter,
      recipient.citizenid,
      recipientAfter
    )
    if not persisted then return false, 'database_error' end

    sender.money.bank = senderAfter
    recipient.money.bank = recipientAfter
    return true, {
      sender = sender,
      recipient = recipient,
      senderBefore = senderBefore,
      senderAfter = senderAfter,
      recipientBefore = recipientBefore,
      recipientAfter = recipientAfter
    }
  end)

  if not ok then return { ok = false, error = detailOrErr } end

  local detail = detailOrErr
  logMoneyChange('transfer_bank_out', detail.sender, 'bank', detail.senderBefore, detail.senderAfter, -totalCost, options)
  recordLedgerChange(detail.sender, 'bank', detail.senderBefore, detail.senderAfter, 'out', totalCost, options)

  local recipientOptions = cloneTable(options)
  recipientOptions.related_citizenid = tostring(detail.sender.citizenid)
  recipientOptions.reason = options.recipient_reason or options.reason
  logMoneyChange('transfer_bank_in', detail.recipient, 'bank', detail.recipientBefore, detail.recipientAfter, amount, recipientOptions)
  recordLedgerChange(detail.recipient, 'bank', detail.recipientBefore, detail.recipientAfter, 'in', amount, recipientOptions)

  return {
    ok = true,
    balances = {
      sender = detail.senderAfter,
      recipient = detail.recipientAfter
    },
    targetSource = targetSource,
    targetCitizenId = tostring(detail.recipient.citizenid),
    transactionRef = options.external_ref,
    fee = fee
  }
end
