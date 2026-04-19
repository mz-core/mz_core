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

local function getOrgByCode(orgCode)
  return MZOrgRepository.getOrgByCode(orgCode)
end

local function buildOrgAccountActor(actor)
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
