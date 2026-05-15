MZOrgAccountService = {}

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

  if MZOrgService.hasGlobalPermission(source, 'staff.orgs.manage') == true
    or MZOrgService.hasGlobalPermission(source, 'staff.panel.open') == true
    or MZOrgService.hasGlobalPermission(source, 'staff.logs.view') == true then
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
end

local function normalizeReason(value)
  if type(value) ~= 'string' and type(value) ~= 'number' then return nil end
  value = tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' then return nil end
  if #value > 255 then value = value:sub(1, 255) end
  return value
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

  if not asBool(org.has_shared_account) then
    return false, 'org_has_no_shared_account'
  end

  amount = math.floor(tonumber(amount) or 0)
  if amount < 0 then amount = 0 end

  local beforeBalance = 0
  local existingRow = MySQL.single.await('SELECT balance FROM mz_org_accounts WHERE org_id = ? LIMIT 1', { org.id })
  if existingRow then
    beforeBalance = math.floor(tonumber(existingRow.balance) or 0)
  end

  MySQL.insert.await([[
    INSERT INTO mz_org_accounts (org_id, balance)
    VALUES (?, ?)
    ON DUPLICATE KEY UPDATE balance = VALUES(balance)
  ]], { org.id, amount })

  logOrgAccountAction('set_balance', org, actor, beforeBalance, amount, {
    amount = amount
  })

  return true, amount
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

  if not canManageOrgAccount(source, orgCode, 'account.deposit') then
    logOrgAccountBlocked('org.account.deposit.blocked', orgCode, source, 'forbidden', { amount = amount })
    return false, 'forbidden'
  end

  local playerBankBefore = math.floor(tonumber((actorPlayer.money or {}).bank) or 0)
  if playerBankBefore < amount then
    logOrgAccountBlocked('org.account.deposit.blocked', orgCode, source, 'insufficient_player_funds', {
      amount = amount,
      player_bank_before = playerBankBefore
    })
    return false, 'insufficient_player_funds'
  end

  local removeOk, removeErr = MZAccountService.removeMoney(source, 'bank', amount, {
    actorSource = source,
    reason = reason or 'org_account_deposit',
    sourceType = 'org_account',
    sourceRef = orgCode
  })

  if not removeOk then
    local err = removeErr == 'not_enough_money' and 'insufficient_player_funds' or (removeErr or 'deposit_failed')
    logOrgAccountBlocked('org.account.deposit.blocked', orgCode, source, err, { amount = amount })
    return false, err
  end

  local balanceBefore = math.floor(tonumber(balanceOrErr) or 0)
  local balanceAfter = balanceBefore + amount
  local affected = MySQL.update.await('UPDATE mz_org_accounts SET balance = ? WHERE org_id = ?', {
    balanceAfter,
    org.id
  }) or 0

  if affected <= 0 then
    MZAccountService.addMoney(source, 'bank', amount, {
      actorSource = source,
      reason = 'org_account_deposit_rollback',
      sourceType = 'org_account',
      sourceRef = orgCode
    })
    logOrgAccountBlocked('org.account.deposit.blocked', orgCode, source, 'deposit_failed', { amount = amount })
    return false, 'deposit_failed'
  end

  local txId = recordOrgAccountTransaction(org, 'deposit', amount, balanceBefore, balanceAfter, actorPlayer, source, reason, {
    player_bank_before = playerBankBefore,
    player_bank_after = playerBankBefore - amount
  })

  logOrgAccountAction('org.account.deposit', org, source, balanceBefore, balanceAfter, {
    amount = amount,
    reason = reason,
    transaction_id = txId
  })

  return true, {
    orgCode = tostring(org.code),
    balance = balanceAfter,
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

  if not canManageOrgAccount(source, orgCode, 'account.withdraw') then
    logOrgAccountBlocked('org.account.withdraw.blocked', orgCode, source, 'forbidden', { amount = amount })
    return false, 'forbidden'
  end

  local balanceBefore = math.floor(tonumber(balanceOrErr) or 0)
  if balanceBefore < amount then
    logOrgAccountBlocked('org.account.withdraw.blocked', orgCode, source, 'insufficient_org_funds', {
      amount = amount,
      balance_before = balanceBefore
    })
    return false, 'insufficient_org_funds'
  end

  local affected = MySQL.update.await('UPDATE mz_org_accounts SET balance = balance - ? WHERE org_id = ? AND balance >= ?', {
    amount,
    org.id,
    amount
  }) or 0

  if affected <= 0 then
    logOrgAccountBlocked('org.account.withdraw.blocked', orgCode, source, 'insufficient_org_funds', {
      amount = amount,
      balance_before = balanceBefore
    })
    return false, 'insufficient_org_funds'
  end

  local playerBankBefore = math.floor(tonumber((actorPlayer.money or {}).bank) or 0)
  local addOk, addErr = MZAccountService.addMoney(source, 'bank', amount, {
    actorSource = source,
    reason = reason or 'org_account_withdraw',
    sourceType = 'org_account',
    sourceRef = orgCode
  })

  if not addOk then
    MySQL.update.await('UPDATE mz_org_accounts SET balance = balance + ? WHERE org_id = ?', {
      amount,
      org.id
    })
    logOrgAccountBlocked('org.account.withdraw.blocked', orgCode, source, addErr or 'withdraw_failed', { amount = amount })
    return false, 'withdraw_failed'
  end

  local balanceAfter = balanceBefore - amount
  local txId = recordOrgAccountTransaction(org, 'withdraw', amount, balanceBefore, balanceAfter, actorPlayer, source, reason, {
    player_bank_before = playerBankBefore,
    player_bank_after = playerBankBefore + amount
  })

  logOrgAccountAction('org.account.withdraw', org, source, balanceBefore, balanceAfter, {
    amount = amount,
    reason = reason,
    transaction_id = txId
  })

  return true, {
    orgCode = tostring(org.code),
    balance = balanceAfter,
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

  local newBalance = balance + amount

  MySQL.update.await('UPDATE mz_org_accounts SET balance = ? WHERE org_id = ?', {
    newBalance, org.id
  })

  logOrgAccountAction('add_balance', org, actor, balance, newBalance, {
    amount = amount,
    reason = reason
  })

  return true, newBalance
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

  local newBalance = balance - amount

  MySQL.update.await('UPDATE mz_org_accounts SET balance = ? WHERE org_id = ?', {
    newBalance, org.id
  })

  logOrgAccountAction('remove_balance', org, actor, balance, newBalance, {
    amount = amount,
    reason = reason
  })

  return true, newBalance
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
