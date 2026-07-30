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
