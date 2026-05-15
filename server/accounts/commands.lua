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
