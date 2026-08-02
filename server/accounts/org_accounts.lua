MZOrgAccountService = {}

local MAX_SAFE_INTEGER = 9007199254740991

local function asBool(value)
  if value == true then return true end
  if value == false or value == nil then return false end
  if type(value) == 'number' then return value == 1 end
  if type(value) == 'string' then
    value = value:lower()
    return value == '1' or value == 'true'
  end
  return false
end

local buildOrgAccountActor

local function getOrgByCode(orgCode)
  return MZOrgRepository.getOrgByCode(orgCode)
end

local function normalizeOrgCode(value)
  if type(value) ~= 'string' and type(value) ~= 'number' then return nil end
  value = tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' then return nil end
  return value
end

local function canViewOrgAccount(source, orgCode)
  source = tonumber(source)
  if not source or source <= 0 then
    return false
  end

  if MZOrgService.hasGlobalPermission(source, (Config and Config.OwnerAce) or 'group.mz_owner') == true then
    return true
  end

  return MZOrgService.canOrg(source, orgCode, 'account.view') == true
    or MZOrgService.canOrg(source, orgCode, 'org.view') == true
end

local function canManageOrgAccount(source, orgCode, capability)
  source = tonumber(source)
  if not source or source <= 0 then
    return false
  end

  if MZOrgService.hasGlobalPermission(source, (Config and Config.OwnerAce) or 'group.mz_owner') == true then
    return true
  end

  return MZOrgService.canOrg(source, orgCode, capability) == true
    or MZOrgService.canOrg(source, orgCode, 'account.manage') == true
    or MZOrgService.canOrg(source, orgCode, 'manage.account') == true
end

local function canUseOrgCommerce(source, orgCode, capability)
  source = tonumber(source)
  if not source or source <= 0 then return false end
  if MZOrgService.hasGlobalPermission(source, (Config and Config.OwnerAce) or 'group.mz_owner') == true then
    return true
  end
  return MZOrgService.canOrg(source, orgCode, capability) == true
end

local function normalizeReason(value)
  if type(value) ~= 'string' and type(value) ~= 'number' then return nil end
  value = tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' then return nil end
  if #value > 255 then value = value:sub(1, 255) end
  return value
end

local ledgerSequence = 0

local function nextLedgerRef(prefix, orgCode)
  ledgerSequence = ledgerSequence + 1
  local stamp = type(GetGameTimer) == 'function' and GetGameTimer() or os.time()
  return ('%s:%s:%s:%s'):format(
    tostring(prefix or 'org_account'),
    tostring(orgCode or 'unknown'),
    tostring(stamp),
    tostring(ledgerSequence)
  )
end

local function recordOrgLedger(data)
  if MZAccountService and type(MZAccountService.RecordEconomyTransactionSafe) == 'function' then
    return MZAccountService.RecordEconomyTransactionSafe(data)
  end

  return false, 'ledger_service_unavailable'
end

local function getPlayerDisplayName(player, source)
  if player and player.charinfo then
    local first = tostring(player.charinfo.firstname or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local last = tostring(player.charinfo.lastname or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local fullName = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+$', '')
    if fullName ~= '' then return fullName end
  end

  if source and tonumber(source) and tonumber(source) > 0 then
    local ok, name = pcall(GetPlayerName, source)
    if ok and name and name ~= '' then return name end
  end

  return nil
end

local function recordOrgAccountTransaction(org, txType, amount, beforeBalance, afterBalance, actorPlayer, actorSource, reason, metadata)
  local actorCitizenId = actorPlayer and actorPlayer.citizenid or nil
  local actorName = getPlayerDisplayName(actorPlayer, actorSource)

  local id = MySQL.insert.await([[
    INSERT INTO mz_org_account_transactions (
      org_id, org_code, type, amount, balance_before, balance_after,
      actor_citizenid, actor_name, reason, metadata_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    tonumber(org.id) or org.id,
    tostring(org.code),
    tostring(txType),
    math.floor(tonumber(amount) or 0),
    math.floor(tonumber(beforeBalance) or 0),
    math.floor(tonumber(afterBalance) or 0),
    actorCitizenId,
    actorName,
    reason,
    MZUtils.jsonEncode(metadata or {})
  })

  return id
end

local function normalizeTransactionRow(row)
  return {
    id = tonumber(row.id) or row.id,
    orgId = tonumber(row.org_id) or row.org_id,
    orgCode = row.org_code,
    type = row.type,
    amount = tonumber(row.amount) or 0,
    balanceBefore = tonumber(row.balance_before) or 0,
    balanceAfter = tonumber(row.balance_after) or 0,
    actorCitizenId = row.actor_citizenid,
    actorName = row.actor_name,
    reason = row.reason,
    createdAt = row.created_at
  }
end

local function logOrgAccountBlocked(action, orgCode, actorSource, reason, meta)
  if not MZLogService then return end

  local actorPlayer = actorSource and MZPlayerService.getPlayer(actorSource) or nil
  MZLogService.createDetailed('org_accounts', action, {
    actor = actorPlayer and MZLogService.makeActor('player', actorPlayer.citizenid, {
      source = actorSource,
      name = getPlayerDisplayName(actorPlayer, actorSource)
    }) or buildOrgAccountActor(actorSource),
    target = {
      type = 'org_account',
      id = tostring(orgCode or 'unknown')
    },
    context = {
      org_code = orgCode
    },
    meta = {
      reason = reason,
      extra = meta or {}
    }
  })
end

function buildOrgAccountActor(actor)
  if actor == nil then
    return {
      type = 'system',
      id = 'system'
    }
  end

  if tonumber(actor) == 0 then
    return {
      type = 'console',
      id = 'console'
    }
  end

  if type(actor) == 'number' then
    local player = MZPlayerService.getPlayer(actor)
    if player and player.citizenid then
      return {
        type = 'player',
        id = tostring(player.citizenid),
        source = actor
      }
    end

    return {
      type = 'source',
      id = tostring(actor)
    }
  end

  return {
    type = 'system',
    id = tostring(actor)
  }
end

local function logOrgAccountAction(action, org, actor, beforeBalance, afterBalance, meta)
  if not MZLogService or not org then
    return
  end

  MZLogService.createDetailed('org_accounts', action, {
    actor = buildOrgAccountActor(actor),
    target = {
      type = 'org_account',
      id = tostring(org.code)
    },
    context = {
      org_id = tonumber(org.id) or org.id,
      org_code = tostring(org.code),
      has_shared_account = asBool(org.has_shared_account)
    },
    before = {
      balance = math.floor(tonumber(beforeBalance) or 0)
    },
    after = {
      balance = math.floor(tonumber(afterBalance) or 0)
    },
    meta = meta or {}
  })
end

local function actorCitizenId(actor)
  if type(actor) ~= 'number' then return nil end
  local player = MZPlayerService.getPlayer(actor)
  return player and player.citizenid and tostring(player.citizenid) or nil
end

local function orgLedgerMetadata(org, reason, category, sourceType, extra)
  local options = {
    reason = reason,
    category = category,
    source_resource = 'mz_core',
    source_type = sourceType,
    sourceType = sourceType,
    related_org_code = tostring(org.code),
    external_ref = nextLedgerRef(category, org.code),
    data = {
      channel = 'org'
    }
  }
  for key, value in pairs(type(extra) == 'table' and extra or {}) do
    options.data[key] = value
  end
  return MZAccountService.NormalizeFinancialLedgerOptionsInternal(options, {
    category = category,
    reason = reason,
    sourceType = sourceType,
    sourceResource = 'mz_core'
  }), options
end

local function persistOrgBalanceChange(org, nextAmount, actor, operation, reason)
  return MZAccountService.WithFinancialLocksInternal({ ('org:%s'):format(org.id) }, function()
    local row = MySQL.single.await('SELECT balance FROM mz_org_accounts WHERE org_id = ? LIMIT 1', { org.id })
    if not row then return false, 'org_account_missing' end

    local beforeBalance = math.floor(tonumber(row.balance) or 0)
    local afterBalance = type(nextAmount) == 'function' and nextAmount(beforeBalance) or nextAmount
    if afterBalance == nil then return false, 'insufficient_funds' end
    afterBalance = math.floor(tonumber(afterBalance) or -1)
    if afterBalance < 0 or afterBalance > MAX_SAFE_INTEGER then return false, 'invalid_amount' end

    local delta = afterBalance - beforeBalance
    local metadata, options = orgLedgerMetadata(
      org,
      operation,
      'admin_org_adjustment',
      'admin_command',
      { user_reason = normalizeReason(reason), actor = tostring(actor or 'system') }
    )
    local correlationId = MZAccountService.GenerateFinancialTransactionRefInternal('mzacc-org-adjust')
    local outbox
    if delta ~= 0 then
      local outboxErr
      outbox, outboxErr = MZAccountService.BuildFinancialOutboxInternal({
        correlationId = correlationId,
        eventType = 'org_account_adjustment',
        allowMissingSourceCitizenId = true,
        sourceCitizenId = actorCitizenId(actor),
        account = 'org',
        amount = math.abs(delta),
        fee = 0,
        reason = metadata.reason,
        ledgerMetadata = metadata,
        options = options,
        entries = {
          MZAccountService.BuildFinancialLedgerEntryInternal(
            1, nil, 'org', 'adjustment', math.abs(delta), beforeBalance, afterBalance, metadata
          )
        }
      })
      if outbox == false then return false, outboxErr end
    end

    if not MZAccountRepository.updateOrgMoneyWithOutbox(org.id, afterBalance, outbox) then
      return false, 'database_error'
    end

    return true, {
      before = beforeBalance,
      after = afterBalance,
      amount = math.abs(delta),
      direction = 'adjustment',
      metadata = metadata,
      outboxPersisted = type(outbox) == 'table'
    }
  end)
end

local function persistOrgPlayerTransfer(source, org, amount, operation, userReason)
  local player = MZPlayerService.getPlayer(source)
  if not player or not player.citizenid then return false, 'player_not_loaded' end

  return MZAccountService.WithFinancialLocksInternal({
    tostring(player.citizenid),
    ('org:%s'):format(org.id)
  }, function()
    player = MZPlayerService.getPlayer(source)
    if not player or not player.citizenid then return false, 'player_not_loaded' end

    local row = MySQL.single.await('SELECT balance FROM mz_org_accounts WHERE org_id = ? LIMIT 1', { org.id })
    if not row then return false, 'org_account_missing' end

    local playerBefore = math.floor(tonumber((player.money or {}).bank) or 0)
    local orgBefore = math.floor(tonumber(row.balance) or 0)
    local playerAfter, orgAfter
    if operation == 'deposit' then
      if playerBefore < amount then return false, 'insufficient_player_funds' end
      if orgBefore > MAX_SAFE_INTEGER - amount then return false, 'amount_overflow' end
      playerAfter = playerBefore - amount
      orgAfter = orgBefore + amount
    else
      if orgBefore < amount then return false, 'insufficient_org_funds' end
      if playerBefore > MAX_SAFE_INTEGER - amount then return false, 'amount_overflow' end
      playerAfter = playerBefore + amount
      orgAfter = orgBefore - amount
    end

    local externalRef = nextLedgerRef('org_transfer', org.code)
    local common = {
      category = 'org_transfer',
      source_resource = 'mz_core',
      source_type = 'org_account',
      sourceType = 'org_account',
      related_org_code = tostring(org.code),
      external_ref = externalRef,
      counts_as_income = false,
      counts_as_expense = false,
      data = { channel = 'org', operation = operation, user_reason = userReason }
    }
    local playerOptions = {}
    for key, value in pairs(common) do playerOptions[key] = value end
    playerOptions.reason = operation == 'deposit' and 'org_deposit' or 'org_withdraw'
    local playerMetadata = MZAccountService.NormalizeFinancialLedgerOptionsInternal(playerOptions, {})

    local orgOptions = {}
    for key, value in pairs(common) do orgOptions[key] = value end
    orgOptions.reason = playerOptions.reason
    orgOptions.related_citizenid = tostring(player.citizenid)
    local orgMetadata = MZAccountService.NormalizeFinancialLedgerOptionsInternal(orgOptions, {})

    local entries
    if operation == 'deposit' then
      entries = {
        MZAccountService.BuildFinancialLedgerEntryInternal(
          1, player.citizenid, 'bank', 'out', amount, playerBefore, playerAfter, playerMetadata
        ),
        MZAccountService.BuildFinancialLedgerEntryInternal(
          2, nil, 'org', 'in', amount, orgBefore, orgAfter, orgMetadata
        )
      }
    else
      entries = {
        MZAccountService.BuildFinancialLedgerEntryInternal(
          1, nil, 'org', 'out', amount, orgBefore, orgAfter, orgMetadata
        ),
        MZAccountService.BuildFinancialLedgerEntryInternal(
          2, player.citizenid, 'bank', 'in', amount, playerBefore, playerAfter, playerMetadata
        )
      }
    end

    local outbox, outboxErr = MZAccountService.BuildFinancialOutboxInternal({
      correlationId = MZAccountService.GenerateFinancialTransactionRefInternal('mzacc-org-transfer'),
      eventType = 'org_transfer',
      sourceCitizenId = player.citizenid,
      account = 'multi',
      amount = amount,
      fee = 0,
      reason = playerMetadata.reason,
      ledgerMetadata = playerMetadata,
      options = playerOptions,
      entries = entries
    })
    if outbox == false then return false, outboxErr end

    if not MZAccountRepository.transferPlayerBankAndOrg(
      player.citizenid, playerAfter, org.id, orgAfter, outbox
    ) then
      return false, 'database_error'
    end

    player.money = player.money or {}
    player.money.bank = playerAfter
    return true, {
      player = player,
      playerBefore = playerBefore,
      playerAfter = playerAfter,
      orgBefore = orgBefore,
      orgAfter = orgAfter,
      externalRef = externalRef,
      playerMetadata = playerMetadata,
      orgMetadata = orgMetadata,
      outboxPersisted = type(outbox) == 'table'
    }
  end)
end

local function recordLegacyOrgTransfer(detail, org, amount, operation)
  local deposit = operation == 'deposit'
  recordOrgLedger({
    citizenid = tostring(detail.player.citizenid),
    license = tostring(detail.player.license or ''),
    account = 'bank', amount = amount,
    balance_before = detail.playerBefore, balance_after = detail.playerAfter,
    direction = deposit and 'out' or 'in', category = 'org_transfer',
    reason = deposit and 'org_deposit' or 'org_withdraw',
    source_resource = 'mz_core', source_type = 'org_account',
    counts_as_income = false, counts_as_expense = false,
    related_org_code = tostring(org.code), external_ref = detail.externalRef
  })
  recordOrgLedger({
    account = 'org', amount = amount,
    balance_before = detail.orgBefore, balance_after = detail.orgAfter,
    direction = deposit and 'in' or 'out', category = 'org_transfer',
    reason = deposit and 'org_deposit' or 'org_withdraw',
    source_resource = 'mz_core', source_type = 'org_account',
    counts_as_income = false, counts_as_expense = false,
    related_citizenid = tostring(detail.player.citizenid),
    related_org_code = tostring(org.code), external_ref = detail.externalRef
  })
end

function MZOrgAccountService.getBalance(orgCode)
  local org = getOrgByCode(orgCode)
  if not org then
    return false, 'org_not_found'
  end

  if not asBool(org.has_shared_account) then
    return false, 'org_has_no_shared_account'
  end

  local row = MySQL.single.await('SELECT * FROM mz_org_accounts WHERE org_id = ? LIMIT 1', { org.id })
  if not row then
    MySQL.insert.await([[
      INSERT INTO mz_org_accounts (org_id, balance)
      VALUES (?, 0)
      ON DUPLICATE KEY UPDATE org_id = org_id
    ]], { org.id })

    row = MySQL.single.await('SELECT * FROM mz_org_accounts WHERE org_id = ? LIMIT 1', { org.id })
  end

  return true, tonumber(row.balance) or 0, org
end

function MZOrgAccountService.setBalance(orgCode, amount, actor)
  local org = getOrgByCode(orgCode)
  if not org then
    return false, 'org_not_found'
  end

  if not asBool(org.active) then
    return false, 'org_archived'
  end

  if not asBool(org.has_shared_account) then
    return false, 'org_has_no_shared_account'
  end

  amount = math.floor(tonumber(amount) or 0)
  if amount < 0 then amount = 0 end

  MySQL.insert.await([[
    INSERT INTO mz_org_accounts (org_id, balance)
    VALUES (?, 0)
    ON DUPLICATE KEY UPDATE org_id = org_id
  ]], { org.id })

  local ok, detailOrErr = persistOrgBalanceChange(org, amount, actor, 'admin_org_set_balance')
  if not ok then return false, detailOrErr end
  local detail = detailOrErr

  logOrgAccountAction('set_balance', org, actor, detail.before, detail.after, {
    amount = amount
  })

  if detail.amount > 0 and detail.outboxPersisted ~= true then
    recordOrgLedger({
      account = 'org', amount = detail.amount,
      balance_before = detail.before, balance_after = detail.after,
      direction = detail.direction, category = detail.metadata.category,
      reason = detail.metadata.reason, source_resource = detail.metadata.source_resource,
      source_type = detail.metadata.source_type, counts_as_income = false,
      counts_as_expense = false, related_org_code = tostring(org.code),
      external_ref = detail.metadata.external_ref
    })
  end

  return true, detail.after
end

function MZOrgAccountService.getAccountReadOnly(source, orgCode)
  source = tonumber(source)
  orgCode = normalizeOrgCode(orgCode)

  if not source or source <= 0 then
    return false, 'invalid_source'
  end

  if not orgCode then
    return false, 'invalid_org'
  end

  local org = getOrgByCode(orgCode)
  if not org then
    return false, 'org_not_found'
  end

  if not asBool(org.active) then
    return false, 'org_archived'
  end

  if not canViewOrgAccount(source, orgCode) then
    return false, 'forbidden'
  end

  if not asBool(org.has_shared_account) then
    return false, 'org_has_no_shared_account'
  end

  local row = MySQL.single.await('SELECT balance FROM mz_org_accounts WHERE org_id = ? LIMIT 1', { org.id })

  return true, {
    orgCode = tostring(org.code),
    balance = row and (tonumber(row.balance) or 0) or 0,
    currency = 'R$',
    canView = true
  }
end

function MZOrgAccountService.deposit(source, orgCode, amount, reason)
  source = tonumber(source)
  orgCode = normalizeOrgCode(orgCode)
  amount = math.floor(tonumber(amount) or 0)
  reason = normalizeReason(reason)

  if not source or source <= 0 then return false, 'invalid_source' end
  if not orgCode then return false, 'invalid_org' end
  if amount <= 0 then return false, 'invalid_amount' end

  local actorPlayer = MZPlayerService.getPlayer(source)
  if not actorPlayer or not actorPlayer.citizenid then
    logOrgAccountBlocked('org.account.deposit.blocked', orgCode, source, 'player_not_loaded', { amount = amount })
    return false, 'player_not_loaded'
  end

  local okBalance, balanceOrErr, org = MZOrgAccountService.getBalance(orgCode)
  if not okBalance then
    logOrgAccountBlocked('org.account.deposit.blocked', orgCode, source, balanceOrErr, { amount = amount })
    return false, balanceOrErr == 'org_not_found' and 'invalid_org' or balanceOrErr
  end
  if not asBool(org.active) then
    logOrgAccountBlocked('org.account.deposit.blocked', orgCode, source, 'org_archived', { amount = amount })
    return false, 'org_archived'
  end

  if not canManageOrgAccount(source, orgCode, 'account.deposit') then
    logOrgAccountBlocked('org.account.deposit.blocked', orgCode, source, 'forbidden', { amount = amount })
    return false, 'forbidden'
  end

  local persisted, detailOrErr = persistOrgPlayerTransfer(source, org, amount, 'deposit', reason)
  if not persisted then
    logOrgAccountBlocked('org.account.deposit.blocked', orgCode, source, detailOrErr, { amount = amount })
    return false, detailOrErr
  end
  local detail = detailOrErr
  local txId = recordOrgAccountTransaction(org, 'deposit', amount, detail.orgBefore, detail.orgAfter, detail.player, source, reason, {
    player_bank_before = detail.playerBefore,
    player_bank_after = detail.playerAfter
  })

  logOrgAccountAction('org.account.deposit', org, source, detail.orgBefore, detail.orgAfter, {
    amount = amount,
    reason = reason,
    transaction_id = txId
  })

  if detail.outboxPersisted ~= true then recordLegacyOrgTransfer(detail, org, amount, 'deposit') end

  return true, {
    orgCode = tostring(org.code),
    balance = detail.orgAfter,
    currency = 'R$',
    transactionId = txId
  }
end

function MZOrgAccountService.withdraw(source, orgCode, amount, reason)
  source = tonumber(source)
  orgCode = normalizeOrgCode(orgCode)
  amount = math.floor(tonumber(amount) or 0)
  reason = normalizeReason(reason)

  if not source or source <= 0 then return false, 'invalid_source' end
  if not orgCode then return false, 'invalid_org' end
  if amount <= 0 then return false, 'invalid_amount' end

  local actorPlayer = MZPlayerService.getPlayer(source)
  if not actorPlayer or not actorPlayer.citizenid then
    logOrgAccountBlocked('org.account.withdraw.blocked', orgCode, source, 'player_not_loaded', { amount = amount })
    return false, 'player_not_loaded'
  end

  local okBalance, balanceOrErr, org = MZOrgAccountService.getBalance(orgCode)
  if not okBalance then
    logOrgAccountBlocked('org.account.withdraw.blocked', orgCode, source, balanceOrErr, { amount = amount })
    return false, balanceOrErr == 'org_not_found' and 'invalid_org' or balanceOrErr
  end
  if not asBool(org.active) then
    logOrgAccountBlocked('org.account.withdraw.blocked', orgCode, source, 'org_archived', { amount = amount })
    return false, 'org_archived'
  end

  if not canManageOrgAccount(source, orgCode, 'account.withdraw') then
    logOrgAccountBlocked('org.account.withdraw.blocked', orgCode, source, 'forbidden', { amount = amount })
    return false, 'forbidden'
  end

  local persisted, detailOrErr = persistOrgPlayerTransfer(source, org, amount, 'withdraw', reason)
  if not persisted then
    logOrgAccountBlocked('org.account.withdraw.blocked', orgCode, source, detailOrErr, { amount = amount })
    return false, detailOrErr
  end
  local detail = detailOrErr
  local txId = recordOrgAccountTransaction(org, 'withdraw', amount, detail.orgBefore, detail.orgAfter, detail.player, source, reason, {
    player_bank_before = detail.playerBefore,
    player_bank_after = detail.playerAfter
  })

  logOrgAccountAction('org.account.withdraw', org, source, detail.orgBefore, detail.orgAfter, {
    amount = amount,
    reason = reason,
    transaction_id = txId
  })

  if detail.outboxPersisted ~= true then recordLegacyOrgTransfer(detail, org, amount, 'withdraw') end

  return true, {
    orgCode = tostring(org.code),
    balance = detail.orgAfter,
    currency = 'R$',
    transactionId = txId
  }
end

function MZOrgAccountService.listTransactions(source, orgCode, filters)
  source = tonumber(source)
  orgCode = normalizeOrgCode(orgCode)
  filters = type(filters) == 'table' and filters or {}

  if not source or source <= 0 then return false, 'invalid_source' end
  if not orgCode then return false, 'invalid_org' end

  local org = getOrgByCode(orgCode)
  if not org then return false, 'invalid_org' end
  if not asBool(org.active) then return false, 'org_archived' end
  if not canViewOrgAccount(source, orgCode) then return false, 'forbidden' end

  local limit = math.floor(tonumber(filters.limit) or 50)
  if limit < 1 then limit = 1 end
  if limit > 100 then limit = 100 end

  local offset = math.floor(tonumber(filters.offset) or 0)
  if offset < 0 then offset = 0 end
  if offset > 10000 then offset = 10000 end

  local txType = normalizeReason(filters.type)
  if txType and txType ~= 'deposit' and txType ~= 'withdraw' then
    txType = nil
  end

  local rows
  if txType then
    rows = MySQL.query.await([[
      SELECT id, org_id, org_code, type, amount, balance_before, balance_after,
        actor_citizenid, actor_name, reason, created_at
      FROM mz_org_account_transactions
      WHERE org_code = ? AND type = ?
      ORDER BY id DESC
      LIMIT ? OFFSET ?
    ]], { orgCode, txType, limit, offset }) or {}
  else
    rows = MySQL.query.await([[
      SELECT id, org_id, org_code, type, amount, balance_before, balance_after,
        actor_citizenid, actor_name, reason, created_at
      FROM mz_org_account_transactions
      WHERE org_code = ?
      ORDER BY id DESC
      LIMIT ? OFFSET ?
    ]], { orgCode, limit, offset }) or {}
  end

  local out = {}
  for _, row in ipairs(rows) do
    out[#out + 1] = normalizeTransactionRow(row)
  end

  return true, out
end

function MZOrgAccountService.addBalance(orgCode, amount, actor, reason)
  local ok, balance, org = MZOrgAccountService.getBalance(orgCode)
  if not ok then
    return false, balance
  end

  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then
    return false, 'invalid_amount'
  end

  local changed, detailOrErr = persistOrgBalanceChange(org, function(current)
    if current > MAX_SAFE_INTEGER - amount then return nil end
    return current + amount
  end, actor, 'admin_org_add_balance', reason)
  if not changed then return false, detailOrErr == 'insufficient_funds' and 'amount_overflow' or detailOrErr end
  local detail = detailOrErr

  logOrgAccountAction('add_balance', org, actor, detail.before, detail.after, {
    amount = amount,
    reason = reason
  })

  if detail.outboxPersisted ~= true then recordOrgLedger({
    account = 'org',
    amount = amount,
    balance_before = detail.before,
    balance_after = detail.after,
    direction = 'adjustment',
    category = 'admin_org_adjustment',
    reason = 'admin_org_add_balance',
    source_resource = 'mz_core',
    source_type = 'admin_command',
    counts_as_income = false,
    counts_as_expense = false,
    related_org_code = tostring(org.code),
    external_ref = detail.metadata.external_ref,
    metadata = {
      operation = 'add_balance',
      user_reason = normalizeReason(reason),
      actor = tostring(actor or 'system'),
      org_id = tonumber(org.id) or org.id,
      org_code = tostring(org.code)
    }
  }) end

  return true, detail.after
end

function MZOrgAccountService.removeBalance(orgCode, amount, actor, reason)
  local ok, balance, org = MZOrgAccountService.getBalance(orgCode)
  if not ok then
    return false, balance
  end

  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then
    return false, 'invalid_amount'
  end

  if balance < amount then
    return false, 'insufficient_funds'
  end

  local changed, detailOrErr = persistOrgBalanceChange(org, function(current)
    if current < amount then return nil end
    return current - amount
  end, actor, 'admin_org_remove_balance', reason)
  if not changed then return false, detailOrErr end
  local detail = detailOrErr

  logOrgAccountAction('remove_balance', org, actor, detail.before, detail.after, {
    amount = amount,
    reason = reason
  })

  if detail.outboxPersisted ~= true then recordOrgLedger({
    account = 'org',
    amount = amount,
    balance_before = detail.before,
    balance_after = detail.after,
    direction = 'adjustment',
    category = 'admin_org_adjustment',
    reason = 'admin_org_remove_balance',
    source_resource = 'mz_core',
    source_type = 'admin_command',
    counts_as_income = false,
    counts_as_expense = false,
    related_org_code = tostring(org.code),
    external_ref = detail.metadata.external_ref,
    metadata = {
      operation = 'remove_balance',
      user_reason = normalizeReason(reason),
      actor = tostring(actor or 'system'),
      org_id = tonumber(org.id) or org.id,
      org_code = tostring(org.code)
    }
  }) end

  return true, detail.after
end

local ORG_COMMERCE_VERSION = 1
local ORG_COMMERCE_PURPOSES = {
  facility_purchase = {
    capability = 'facility.purchase',
    category = 'org_facility_purchase',
    reason = 'facility_purchase',
    resources = { mz_org_activities = true }
  }
}

local function normalizeBoundedToken(value, minLength, maxLength)
  if type(value) ~= 'string' and type(value) ~= 'number' then return nil end
  local token = tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
  if #token < minLength or #token > maxLength then return nil end
  if not token:match('^[%w%._:%-]+$') then return nil end
  return token
end

local function normalizeSourceResource(value)
  if type(value) ~= 'string' then return nil end
  value = value:gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' or #value > 100 then return nil end
  return value
end

local function encodeCommerceMetadata(data)
  local ok, encoded = pcall(MZUtils.jsonEncode, data)
  if not ok or type(encoded) ~= 'string' or encoded == '' or #encoded > 8192 then
    return nil
  end
  return encoded
end

local function commerceFingerprint(operationType, sourceResource, org, actorCitizenId, amount, purpose, relatedRef, reversalId)
  return table.concat({
    tostring(ORG_COMMERCE_VERSION), tostring(operationType), tostring(sourceResource),
    tostring(org.id), tostring(org.code), tostring(actorCitizenId), tostring(amount),
    tostring(purpose), tostring(relatedRef), tostring(reversalId or '')
  }, '|')
end

local function normalizeCommerceReceipt(row, replayed)
  return {
    schemaVersion = ORG_COMMERCE_VERSION,
    receiptId = row.receipt_id,
    correlationId = row.correlation_id,
    operationId = tonumber(row.id) or row.id,
    operationKey = row.operation_key,
    operationType = row.operation_type,
    purpose = row.purpose,
    orgCode = row.org_code,
    amount = tonumber(row.amount) or 0,
    balanceBefore = tonumber(row.balance_before) or 0,
    balanceAfter = tonumber(row.balance_after) or 0,
    relatedRef = row.related_ref,
    reversalOfOperationId = tonumber(row.reversal_of_operation_id) or row.reversal_of_operation_id,
    replayed = replayed == true
  }
end

local function recoverCommerceOperation(row, operationType, purpose, fingerprint)
  if not row then return nil, nil, false end
  if tostring(row.operation_type or '') ~= tostring(operationType)
      or tostring(row.purpose or '') ~= tostring(purpose)
      or tostring(row.request_fingerprint or '') ~= tostring(fingerprint) then
    return nil, 'idempotency_conflict', true
  end

  if tostring(row.status) == 'applied' then
    return normalizeCommerceReceipt(row, true), nil, true
  end
  if tostring(row.status) == 'rejected' then
    return nil, tostring(row.error_code or 'operation_rejected'), true
  end
  if tostring(row.status) ~= 'pending' then
    return nil, 'operation_state_invalid', true
  end
  return row, nil, false
end

local function buildCommerceFinancialData(operation, org, actorCitizenId, sourceResource, beforeBalance, afterBalance, receiptId)
  local spend = operation.operationType == 'spend'
  local category = spend and 'org_facility_purchase' or 'org_facility_refund'
  local reason = spend and 'facility_purchase' or 'facility_purchase_refund'
  local ledgerOptions = {
    __invokingResource = sourceResource,
    category = category,
    reason = reason,
    source_type = 'org_account_commerce',
    related_org_code = tostring(org.code),
    external_ref = receiptId,
    counts_as_income = false,
    counts_as_expense = spend,
    data = {
      channel = 'org',
      operation_key = operation.operationKey,
      related_ref = operation.relatedRef,
      purpose = operation.purpose
    }
  }
  local metadata = MZAccountService.NormalizeFinancialLedgerOptionsInternal(ledgerOptions, {})
  local outbox, outboxErr = MZAccountService.BuildFinancialOutboxInternal({
    correlationId = operation.correlationId,
    eventType = spend and 'org_account_spend' or 'org_account_refund',
    sourceCitizenId = actorCitizenId,
    account = 'org',
    amount = operation.amount,
    fee = 0,
    reason = reason,
    ledgerMetadata = metadata,
    options = ledgerOptions,
    entries = {
      MZAccountService.BuildFinancialLedgerEntryInternal(
        1, nil, 'org', spend and 'out' or 'in', operation.amount,
        beforeBalance, afterBalance, metadata
      )
    }
  })
  if outbox == false then return false, outboxErr end
  return {
    outbox = outbox,
    metadata = metadata,
    reason = reason,
    category = category,
    direction = spend and 'out' or 'in'
  }
end

local function applyPendingCommerceOperation(row, org, player, source, sourceResource)
  local account = MySQL.single.await(
    'SELECT balance FROM mz_org_accounts WHERE org_id = ? LIMIT 1', { org.id }
  )
  if not account then return false, 'org_account_missing' end

  local amount = math.floor(tonumber(row.amount) or 0)
  local beforeBalance = math.floor(tonumber(account.balance) or 0)
  local spend = tostring(row.operation_type) == 'spend'
  local afterBalance
  if spend then
    if beforeBalance < amount then
      MZAccountRepository.rejectOrgAccountOperation(row.id, 'insufficient_org_funds')
      return false, 'insufficient_org_funds'
    end
    afterBalance = beforeBalance - amount
  else
    if beforeBalance > MAX_SAFE_INTEGER - amount then
      MZAccountRepository.rejectOrgAccountOperation(row.id, 'amount_overflow')
      return false, 'amount_overflow'
    end
    afterBalance = beforeBalance + amount
  end

  local receiptId = MZAccountService.GenerateFinancialTransactionRefInternal(
    spend and 'mzorg-spend' or 'mzorg-refund'
  )
  local correlationId = MZAccountService.GenerateFinancialTransactionRefInternal('mzacc-org-commerce')
  local financial, financialErr = buildCommerceFinancialData({
    operationType = tostring(row.operation_type),
    operationKey = tostring(row.operation_key),
    relatedRef = tostring(row.related_ref),
    purpose = tostring(row.purpose),
    amount = amount,
    correlationId = correlationId
  }, org, tostring(player.citizenid), sourceResource, beforeBalance, afterBalance, receiptId)
  if financial == false then return false, financialErr end

  local persisted = MZAccountRepository.applyOrgAccountOperation({
    operationId = tonumber(row.id),
    balanceBefore = beforeBalance,
    balanceAfter = afterBalance,
    receiptId = receiptId,
    correlationId = correlationId,
    actorName = getPlayerDisplayName(player, source),
    reason = financial.reason
  }, financial.outbox)
  if not persisted then return false, 'database_error' end

  local applied = MZAccountRepository.getOrgAccountOperation(sourceResource, tostring(row.operation_key))
  if not applied or tostring(applied.status) ~= 'applied' then
    return false, 'balance_conflict'
  end

  local receipt = normalizeCommerceReceipt(applied, false)
  receipt.outboxPersisted = type(financial.outbox) == 'table'
  receipt.ledger = financial
  return true, receipt
end

local function recordLegacyCommerce(receipt)
  if type(receipt) ~= 'table' or receipt.outboxPersisted == true or type(receipt.ledger) ~= 'table' then
    return
  end
  local ledger = receipt.ledger
  recordOrgLedger({
    account = 'org',
    amount = receipt.amount,
    balance_before = receipt.balanceBefore,
    balance_after = receipt.balanceAfter,
    direction = ledger.direction,
    category = ledger.category,
    reason = ledger.reason,
    source_resource = ledger.metadata.source_resource,
    source_type = ledger.metadata.source_type,
    counts_as_income = false,
    counts_as_expense = ledger.metadata.counts_as_expense == true,
    related_org_code = receipt.orgCode,
    external_ref = receipt.receiptId
  })
end

function MZOrgAccountService.getCommerceCapabilities()
  local ready = MZCoreState and MZCoreState.ready == true
  return {
    schemaVersion = ORG_COMMERCE_VERSION,
    ready = ready,
    spend = ready,
    refund = ready,
    idempotent = true,
    receipt = true,
    error = ready and nil or 'core_not_ready',
    purposes = { 'facility_purchase' }
  }
end

function MZOrgAccountService.spend(source, orgCode, amount, options, sourceResource)
  source = tonumber(source)
  orgCode = normalizeOrgCode(orgCode)
  amount = math.floor(tonumber(amount) or 0)
  options = type(options) == 'table' and options or {}
  sourceResource = normalizeSourceResource(sourceResource)

  if not MZCoreState or MZCoreState.ready ~= true then return false, 'core_not_ready' end
  if not source or source <= 0 then return false, 'invalid_source' end
  if not orgCode then return false, 'invalid_org' end
  if amount <= 0 or amount > MAX_SAFE_INTEGER then return false, 'invalid_amount' end
  if not sourceResource then return false, 'invalid_source_resource' end

  local purpose = normalizeBoundedToken(options.purpose, 3, 64)
  local policy = purpose and ORG_COMMERCE_PURPOSES[purpose] or nil
  if not policy or policy.resources[sourceResource] ~= true then
    return false, 'commerce_purpose_forbidden'
  end
  local operationKey = normalizeBoundedToken(
    options.operationKey or options.idempotencyKey or options.idempotency_key, 16, 128
  )
  if not operationKey then return false, 'invalid_operation_key' end
  local relatedRef = normalizeBoundedToken(options.relatedRef or options.related_ref, 8, 128)
  if not relatedRef then return false, 'invalid_related_ref' end

  local player = MZPlayerService.getPlayer(source)
  if not player or not player.citizenid then return false, 'player_not_loaded' end
  local okBalance, balanceOrErr, org = MZOrgAccountService.getBalance(orgCode)
  if not okBalance then return false, balanceOrErr end
  if not asBool(org.active) then return false, 'org_archived' end
  if not canUseOrgCommerce(source, orgCode, policy.capability) then return false, 'forbidden' end

  local fingerprint = commerceFingerprint(
    'spend', sourceResource, org, player.citizenid, amount, purpose, relatedRef
  )
  local metadataJson = encodeCommerceMetadata({
    schemaVersion = ORG_COMMERCE_VERSION,
    operation = 'spend', purpose = purpose, relatedRef = relatedRef,
    sourceResource = sourceResource, userReason = normalizeReason(options.reason)
  })
  if not metadataJson then return false, 'invalid_metadata' end

  local lockedOk, resultOrErr = MZAccountService.WithFinancialLocksInternal({
    ('org:%s'):format(org.id),
    ('org-commerce:%s:%s'):format(sourceResource, operationKey)
  }, function()
    player = MZPlayerService.getPlayer(source)
    if not player or not player.citizenid then return false, 'player_not_loaded' end
    local currentOrg = getOrgByCode(orgCode)
    if not currentOrg or tonumber(currentOrg.id) ~= tonumber(org.id) then return false, 'org_not_found' end
    if not asBool(currentOrg.active) then return false, 'org_archived' end
    if not asBool(currentOrg.has_shared_account) then return false, 'org_has_no_shared_account' end
    if not canUseOrgCommerce(source, orgCode, policy.capability) then return false, 'forbidden' end

    local existing = MZAccountRepository.getOrgAccountOperation(sourceResource, operationKey)
    local recovered, recoverErr, terminal = recoverCommerceOperation(
      existing, 'spend', purpose, fingerprint
    )
    if terminal then
      if recovered then return true, recovered end
      return false, recoverErr
    end

    local operation = existing
    if not operation then
      local account = MySQL.single.await(
        'SELECT balance FROM mz_org_accounts WHERE org_id = ? LIMIT 1', { org.id }
      )
      if not account then return false, 'org_account_missing' end
      local insufficient = math.floor(tonumber(account.balance) or 0) < amount
      local operationId = MZAccountRepository.createOrgAccountOperation({
        sourceResource = sourceResource, operationKey = operationKey,
        operationType = 'spend', purpose = purpose, orgId = org.id,
        orgCode = tostring(org.code), actorCitizenId = tostring(player.citizenid),
        amount = amount, relatedRef = relatedRef, fingerprint = fingerprint,
        status = insufficient and 'rejected' or 'pending',
        errorCode = insufficient and 'insufficient_org_funds' or nil,
        metadataJson = metadataJson
      })
      if not operationId then return false, 'database_error' end
      if insufficient then return false, 'insufficient_org_funds' end
      operation = MZAccountRepository.getOrgAccountOperation(sourceResource, operationKey)
      if not operation then return false, 'database_error' end
    end

    return applyPendingCommerceOperation(operation, org, player, source, sourceResource)
  end)

  if not lockedOk then return false, resultOrErr end
  recordLegacyCommerce(resultOrErr)
  logOrgAccountAction('org.account.spend', org, source, resultOrErr.balanceBefore, resultOrErr.balanceAfter, {
    amount = amount, purpose = purpose, receipt_id = resultOrErr.receiptId,
    replayed = resultOrErr.replayed == true, source_resource = sourceResource
  })
  resultOrErr.ledger = nil
  resultOrErr.outboxPersisted = nil
  return true, resultOrErr
end

function MZOrgAccountService.refund(source, orgCode, spendReceiptId, options, sourceResource)
  source = tonumber(source)
  orgCode = normalizeOrgCode(orgCode)
  options = type(options) == 'table' and options or {}
  sourceResource = normalizeSourceResource(sourceResource)
  spendReceiptId = normalizeBoundedToken(spendReceiptId, 8, 128)

  if not MZCoreState or MZCoreState.ready ~= true then return false, 'core_not_ready' end
  if not source or source <= 0 then return false, 'invalid_source' end
  if not orgCode then return false, 'invalid_org' end
  if not sourceResource then return false, 'invalid_source_resource' end
  if not spendReceiptId then return false, 'invalid_receipt_id' end
  if sourceResource ~= 'mz_org_activities' then return false, 'commerce_purpose_forbidden' end

  local operationKey = normalizeBoundedToken(
    options.operationKey or options.idempotencyKey or options.idempotency_key, 16, 128
  )
  if not operationKey then return false, 'invalid_operation_key' end
  local player = MZPlayerService.getPlayer(source)
  if not player or not player.citizenid then return false, 'player_not_loaded' end
  local org = getOrgByCode(orgCode)
  if not org then return false, 'org_not_found' end
  if not asBool(org.has_shared_account) then return false, 'org_has_no_shared_account' end

  local original = MZAccountRepository.getOrgAccountOperationByReceipt(spendReceiptId)
  if not original or tostring(original.status) ~= 'applied'
      or tostring(original.operation_type) ~= 'spend'
      or tostring(original.purpose) ~= 'facility_purchase' then
    return false, 'spend_receipt_not_found'
  end
  if tostring(original.source_resource) ~= sourceResource
      or tostring(original.org_code) ~= tostring(org.code)
      or tostring(original.actor_citizenid) ~= tostring(player.citizenid) then
    return false, 'spend_receipt_forbidden'
  end

  local amount = math.floor(tonumber(original.amount) or 0)
  local purpose = 'facility_purchase_refund'
  local relatedRef = spendReceiptId
  local fingerprint = commerceFingerprint(
    'refund', sourceResource, org, player.citizenid, amount, purpose,
    relatedRef, original.id
  )
  local metadataJson = encodeCommerceMetadata({
    schemaVersion = ORG_COMMERCE_VERSION,
    operation = 'refund', purpose = purpose, relatedRef = relatedRef,
    sourceResource = sourceResource, reversalOfOperationId = tonumber(original.id),
    userReason = normalizeReason(options.reason)
  })
  if not metadataJson then return false, 'invalid_metadata' end

  local lockedOk, resultOrErr = MZAccountService.WithFinancialLocksInternal({
    ('org:%s'):format(org.id),
    ('org-commerce:%s:%s'):format(sourceResource, operationKey),
    ('org-commerce-reversal:%s'):format(original.id)
  }, function()
    local existing = MZAccountRepository.getOrgAccountOperation(sourceResource, operationKey)
    local recovered, recoverErr, terminal = recoverCommerceOperation(
      existing, 'refund', purpose, fingerprint
    )
    if terminal then
      if recovered then return true, recovered end
      return false, recoverErr
    end

    local reversal = MZAccountRepository.getOrgAccountReversal(original.id)
    if reversal and (not existing or tonumber(reversal.id) ~= tonumber(existing.id)) then
      return false, 'spend_already_refunded'
    end

    local operation = existing
    if not operation then
      local operationId = MZAccountRepository.createOrgAccountOperation({
        sourceResource = sourceResource, operationKey = operationKey,
        operationType = 'refund', purpose = purpose, orgId = org.id,
        orgCode = tostring(org.code), actorCitizenId = tostring(player.citizenid),
        amount = amount, relatedRef = relatedRef, fingerprint = fingerprint,
        status = 'pending', reversalOfOperationId = tonumber(original.id),
        metadataJson = metadataJson
      })
      if not operationId then return false, 'database_error' end
      operation = MZAccountRepository.getOrgAccountOperation(sourceResource, operationKey)
      if not operation then return false, 'database_error' end
    end

    return applyPendingCommerceOperation(operation, org, player, source, sourceResource)
  end)

  if not lockedOk then return false, resultOrErr end
  recordLegacyCommerce(resultOrErr)
  logOrgAccountAction('org.account.refund', org, source, resultOrErr.balanceBefore, resultOrErr.balanceAfter, {
    amount = amount, receipt_id = resultOrErr.receiptId,
    spend_receipt_id = spendReceiptId, replayed = resultOrErr.replayed == true,
    source_resource = sourceResource
  })
  resultOrErr.ledger = nil
  resultOrErr.outboxPersisted = nil
  return true, resultOrErr
end

exports('GetOrgAccountBalance', function(orgCode)
  return MZOrgAccountService.getBalance(orgCode)
end)

exports('SetOrgAccountBalance', function(orgCode, amount, actor)
  return MZOrgAccountService.setBalance(orgCode, amount, actor)
end)

exports('AddOrgAccountBalance', function(orgCode, amount, actor, reason)
  return MZOrgAccountService.addBalance(orgCode, amount, actor, reason)
end)

exports('RemoveOrgAccountBalance', function(orgCode, amount, actor, reason)
  return MZOrgAccountService.removeBalance(orgCode, amount, actor, reason)
end)

exports('GetOrgAccount', function(source, orgCode)
  return MZOrgAccountService.getAccountReadOnly(source, orgCode)
end)

exports('DepositOrgAccount', function(source, orgCode, amount, reason)
  return MZOrgAccountService.deposit(source, orgCode, amount, reason)
end)

exports('WithdrawOrgAccount', function(source, orgCode, amount, reason)
  return MZOrgAccountService.withdraw(source, orgCode, amount, reason)
end)

exports('ListOrgAccountTransactions', function(source, orgCode, filters)
  return MZOrgAccountService.listTransactions(source, orgCode, filters)
end)

exports('GetOrgAccountCommerceCapabilities', function()
  return MZOrgAccountService.getCommerceCapabilities()
end)

exports('SpendOrgAccount', function(source, orgCode, amount, options)
  local invokingResource = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil
  return MZOrgAccountService.spend(source, orgCode, amount, options, invokingResource)
end)

exports('RefundOrgAccount', function(source, orgCode, spendReceiptId, options)
  local invokingResource = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil
  return MZOrgAccountService.refund(source, orgCode, spendReceiptId, options, invokingResource)
end)
