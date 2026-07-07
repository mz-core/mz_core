MZAccountService = {}

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

function MZAccountService.setMoney(source, moneyType, amount, options)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, 'player_not_loaded' end

  options = normalizeServiceOptions(options)

  local normalizedMoneyType, moneyTypeErr = MZAccountService.NormalizeMoneyAccount(moneyType)
  if not normalizedMoneyType then return false, moneyTypeErr end
  moneyType = normalizedMoneyType

  if type(amount) ~= 'number' or amount < 0 then
    return false, 'invalid_amount'
  end

  local nextAmount = math.floor(amount)
  local currentAmount = math.floor(tonumber((player.money or {})[moneyType]) or 0)

  local ok = MZAccountRepository.updatePlayerMoney(player.citizenid, moneyType, nextAmount)
  if not ok then return false, 'invalid_money_type' end

  player.money[moneyType] = nextAmount

  logMoneyChange('set_money', player, moneyType, currentAmount, nextAmount, nextAmount - currentAmount, options)

  local delta = nextAmount - currentAmount
  if delta ~= 0 then
    local ledgerDirection = 'adjustment'
    local ledgerAmount = math.abs(delta)

    if options and options.__ledgerFromWrapper == true then
      ledgerDirection = options.__ledgerDirection or ledgerDirection
      ledgerAmount = tonumber(options.__ledgerAmount) or ledgerAmount
    end

    recordLedgerChange(player, moneyType, currentAmount, nextAmount, ledgerDirection, ledgerAmount, options)
  end

  return true
end

function MZAccountService.addMoney(source, moneyType, amount, options)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, 'player_not_loaded' end

  local normalizedMoneyType, moneyTypeErr = MZAccountService.NormalizeMoneyAccount(moneyType)
  if not normalizedMoneyType then return false, moneyTypeErr end
  moneyType = normalizedMoneyType

  if type(amount) ~= 'number' or amount <= 0 then return false, 'invalid_amount' end

  local value = math.floor(amount)
  local current = math.floor(tonumber((player.money or {})[moneyType]) or 0)

  options = normalizeServiceOptions(options)
  options.reason = options.reason or 'add_money'
  options.__ledgerFromWrapper = true
  options.__ledgerDirection = 'in'
  options.__ledgerAmount = value

  local ok, err = MZAccountService.setMoney(source, moneyType, current + value, options)
  if not ok then
    return false, err
  end

  return true
end

function MZAccountService.removeMoney(source, moneyType, amount, options)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, 'player_not_loaded' end

  local normalizedMoneyType, moneyTypeErr = MZAccountService.NormalizeMoneyAccount(moneyType)
  if not normalizedMoneyType then return false, moneyTypeErr end
  moneyType = normalizedMoneyType

  if type(amount) ~= 'number' or amount <= 0 then return false, 'invalid_amount' end

  local value = math.floor(amount)
  local current = math.floor(tonumber((player.money or {})[moneyType]) or 0)

  if current < value then return false, 'not_enough_money' end

  options = normalizeServiceOptions(options)
  options.reason = options.reason or 'remove_money'
  options.__ledgerFromWrapper = true
  options.__ledgerDirection = 'out'
  options.__ledgerAmount = value

  local ok, err = MZAccountService.setMoney(source, moneyType, current - value, options)
  if not ok then
    return false, err
  end

  return true
end
