local function isAceAllowed(src, ace)
  local sourceId = tonumber(src)
  if not sourceId or sourceId <= 0 then return false end

  ace = tostring(ace or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if ace == '' then return false end

  local allowed = IsPlayerAceAllowed(sourceId, ace)
  local normalized = tostring(allowed):lower()
  return allowed == true or allowed == 1 or normalized == '1' or normalized == 'true'
end

local function canUseAccountCommand(src)
  if src == 0 then
    return true
  end

  return isAceAllowed(src, 'mzcore.orgs.manage')
end

local function reply(message)
  print(('[mz_core] %s'):format(message))
end

local function replyPlayer(source, message)
  TriggerClientEvent('chat:addMessage', source, {
    color = { 255, 80, 80 },
    args = { 'mz_core', tostring(message or '') }
  })
end

local function joinReason(args, startIndex)
  local parts = {}
  for index = startIndex, #(args or {}) do
    parts[#parts + 1] = tostring(args[index])
  end

  local reason = table.concat(parts, ' ')
  reason = reason:gsub('^%s+', ''):gsub('%s+$', '')
  if reason == '' then
    return 'console_money_add'
  end

  return reason
end

RegisterCommand('mz_money_add', function(source, args)
  if tonumber(source) ~= 0 then
    return replyPlayer(source, 'Este comando so pode ser usado pelo console do servidor.')
  end

  args = type(args) == 'table' and args or {}

  local targetArg = tostring(args[1] or '')
  local accountArg = tostring(args[2] or '')
  local amountArg = tostring(args[3] or '')

  if targetArg == '' or accountArg == '' or amountArg == '' then
    return reply('mz_money_add ERRO: uso mz_money_add <source> <wallet|bank|dirty|cash|money|black_money> <amount> [reason]')
  end

  local targetSource = tonumber(targetArg)
  if not targetSource or targetSource <= 0 or math.floor(targetSource) ~= targetSource then
    return reply('mz_money_add ERRO: neste MVP o target deve ser source online numerico')
  end

  local player = MZPlayerService.getPlayer(targetSource)
  if not player or not player.citizenid then
    return reply(('mz_money_add ERRO: target nao carregado no mz_core (%s)'):format(targetArg))
  end

  local normalizedAccount, accountErr = MZAccountService.NormalizeMoneyAccount(accountArg)
  if not normalizedAccount then
    return reply(('mz_money_add ERRO: %s'):format(accountErr or 'invalid_account'))
  end

  local amount = tonumber(amountArg)
  if not amount or amount ~= amount or amount <= 0 or math.floor(amount) ~= amount then
    return reply('mz_money_add ERRO: amount deve ser inteiro positivo')
  end
  amount = math.floor(amount)

  local reason = joinReason(args, 4)
  local ok, err = MZAccountService.addMoney(targetSource, normalizedAccount, amount, {
    reason = reason,
    category = 'admin_adjustment',
    source_resource = 'mz_core',
    source_type = 'console_command',
    counts_as_income = false,
    counts_as_expense = false,
    data = {
      command = 'mz_money_add',
      target = targetArg,
      account = normalizedAccount,
      amount = amount
    }
  })

  if not ok then
    return reply(('mz_money_add ERRO: %s'):format(tostring(err or 'unknown')))
  end

  reply(('mz_money_add OK: target=%s account=%s amount=%s'):format(targetArg, normalizedAccount, amount))
end, false)

RegisterCommand('mzorg_balance', function(source, args)
  if not canUseAccountCommand(source) then
    return reply('Sem permissão.')
  end

  local orgCode = args[1]
  if not orgCode then
    return reply('Uso: mzorg_balance [org]')
  end

  local ok, balance = exports['mz_core']:GetOrgAccountBalance(orgCode)
  if not ok then
    return reply(('Erro: %s'):format(balance or 'unknown'))
  end

  reply(('Saldo de %s: %s'):format(orgCode, balance))
end, true)

RegisterCommand('mzorg_deposit', function(source, args)
  if not canUseAccountCommand(source) then
    return reply('Sem permissão.')
  end

  local orgCode = args[1]
  local amount = tonumber(args[2])

  if not orgCode or not amount then
    return reply('Uso: mzorg_deposit [org] [amount]')
  end

  local ok, result = exports['mz_core']:AddOrgAccountBalance(orgCode, amount, source, 'command_deposit')
  if not ok then
    return reply(('Erro: %s'):format(result or 'unknown'))
  end

  reply(('Novo saldo de %s: %s'):format(orgCode, result))
end, true)

RegisterCommand('mzorg_withdraw', function(source, args)
  if not canUseAccountCommand(source) then
    return reply('Sem permissão.')
  end

  local orgCode = args[1]
  local amount = tonumber(args[2])

  if not orgCode or not amount then
    return reply('Uso: mzorg_withdraw [org] [amount]')
  end

  local ok, result = exports['mz_core']:RemoveOrgAccountBalance(orgCode, amount, source, 'command_withdraw')
  if not ok then
    return reply(('Erro: %s'):format(result or 'unknown'))
  end

  reply(('Novo saldo de %s: %s'):format(orgCode, result))
end, true)

RegisterCommand('mzpay_citizen', function(source, args)
  if not canUseAccountCommand(source) then
    return reply('Sem permissão.')
  end

  local citizenid = args[1]
  if not citizenid then
    return reply('Uso: mzpay_citizen [citizenid]')
  end

  local ok, result = exports['mz_core']:PayCitizenSalary(citizenid, source)
  if not ok then
    return reply(('Erro: %s'):format(result or 'unknown'))
  end

  reply(('Salários pagos para %s'):format(citizenid))
  for _, payment in ipairs(result) do
    reply(('- %s: %s (%s)'):format(payment.org, payment.amount, payment.source))
  end
end, true)

RegisterCommand('mzpay_tick', function(source)
  if not canUseAccountCommand(source) then
    return reply('Sem permissão.')
  end

  local count = exports['mz_core']:RunPayrollTick()
  reply(('Payroll tick executado. Players pagos: %s'):format(count or 0))
end, true)
