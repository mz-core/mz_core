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

local function isAceAllowed(src, ace)
  local sourceId = tonumber(src)
  if not sourceId or sourceId <= 0 then return false end

  ace = tostring(ace or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if ace == '' then return false end

  local allowed = IsPlayerAceAllowed(sourceId, ace)
  local normalized = tostring(allowed):lower()
  return allowed == true or allowed == 1 or normalized == '1' or normalized == 'true'
end

local function canUseOrgCommand(src)
  if src == 0 then
    return true
  end

  return isAceAllowed(src, 'mzcore.orgs.manage')
end

RegisterCommand('mzcore_ace_test', function(source)
  if not Config or Config.Debug ~= true then
    return
  end

  local src = tonumber(source) or 0
  if src <= 0 then
    print('[mz_core][ace_test] use dentro do jogo')
    return
  end

  local ownerAce = (Config and Config.OwnerAce) or 'group.mz_owner'
  local rawOwner = IsPlayerAceAllowed(src, 'group.mz_owner')
  local rawOwnerCfg = IsPlayerAceAllowed(src, ownerAce)
  local rawCommand = IsPlayerAceAllowed(src, 'command')

  local okExportOwner, exportedOwner = pcall(function()
    return exports['mz_core']:HasGlobalPermission(src, 'group.mz_owner')
  end)

  local okExportOwnerCfg, exportedOwnerCfg = pcall(function()
    return exports['mz_core']:HasGlobalPermission(src, ownerAce)
  end)

  print('[mz_core][ace_test] resource=', GetCurrentResourceName())
  print('[mz_core][ace_test] source=', src, 'type=', type(source))
  print('[mz_core][ace_test] name=', GetPlayerName(src))
  print('[mz_core][ace_test] Config.OwnerAce=', ownerAce)
  print('[mz_core][ace_test] raw group.mz_owner=', rawOwner, 'type=', type(rawOwner))
  print('[mz_core][ace_test] raw Config.OwnerAce=', rawOwnerCfg, 'type=', type(rawOwnerCfg))
  print('[mz_core][ace_test] raw command=', rawCommand, 'type=', type(rawCommand))
  print('[mz_core][ace_test] export HasGlobalPermission(group.mz_owner) ok=', okExportOwner, 'result=', exportedOwner, 'type=', type(exportedOwner))
  print('[mz_core][ace_test] export HasGlobalPermission(Config.OwnerAce) ok=', okExportOwnerCfg, 'result=', exportedOwnerCfg, 'type=', type(exportedOwnerCfg))
end, false)

local function reply(src, message)
  print(('[mz_core] %s'):format(message))
end

local function toBool(value)
  if value == nil then return false end
  value = tostring(value):lower()
  return value == '1' or value == 'true' or value == 'on' or value == 'yes'
end

local function reloadTarget(targetSource)
  local player = MZPlayerService.getPlayer(targetSource)
  if not player then
    return false, 'player_not_loaded'
  end

  MZOrgService.loadPlayerOrgs(targetSource)
  TriggerClientEvent('mz_core:client:playerLoaded', targetSource, player)
  return true
end

RegisterCommand('mzorg_add', function(source, args)
  if not canUseOrgCommand(source) then
    return reply(source, 'Sem permissão.')
  end

  local citizenid = args[1]
  local orgCode = args[2]
  local level = tonumber(args[3])
  local isPrimary = toBool(args[4])

  if not citizenid or not orgCode or not level then
    return reply(source, 'Uso: mzorg_add [citizenid] [org] [level] [primary 0/1]')
  end

  local ok, err = exports['mz_core']:AddMemberToOrg(citizenid, orgCode, level, {
    is_primary = isPrimary,
    duty = false
  }, source)

  if not ok then
    return reply(source, ('Erro: %s'):format(err or 'unknown'))
  end

  reply(source, ('Membro %s adicionado em %s nível %s'):format(citizenid, orgCode, level))
end, true)

RegisterCommand('mzorg_remove', function(source, args)
  if not canUseOrgCommand(source) then
    return reply(source, 'Sem permissão.')
  end

  local citizenid = args[1]
  local orgCode = args[2]

  if not citizenid or not orgCode then
    return reply(source, 'Uso: mzorg_remove [citizenid] [org]')
  end

  local ok, err = exports['mz_core']:RemoveMemberFromOrg(citizenid, orgCode, source)
  if not ok then
    return reply(source, ('Erro: %s'):format(err or 'unknown'))
  end

  reply(source, ('Membro %s removido de %s'):format(citizenid, orgCode))
end, true)

RegisterCommand('mzorg_promote', function(source, args)
  if not canUseOrgCommand(source) then
    return reply(source, 'Sem permissão.')
  end

  local citizenid = args[1]
  local orgCode = args[2]

  if not citizenid or not orgCode then
    return reply(source, 'Uso: mzorg_promote [citizenid] [org]')
  end

  local ok, result = exports['mz_core']:PromoteOrgMember(citizenid, orgCode, source)
  if not ok then
    return reply(source, ('Erro: %s'):format(result or 'unknown'))
  end

  reply(source, ('Membro %s promovido em %s para nível %s'):format(citizenid, orgCode, result.level))
end, true)

RegisterCommand('mzorg_demote', function(source, args)
  if not canUseOrgCommand(source) then
    return reply(source, 'Sem permissão.')
  end

  local citizenid = args[1]
  local orgCode = args[2]

  if not citizenid or not orgCode then
    return reply(source, 'Uso: mzorg_demote [citizenid] [org]')
  end

  local ok, result = exports['mz_core']:DemoteOrgMember(citizenid, orgCode, source)
  if not ok then
    return reply(source, ('Erro: %s'):format(result or 'unknown'))
  end

  reply(source, ('Membro %s rebaixado em %s para nível %s'):format(citizenid, orgCode, result.level))
end, true)

RegisterCommand('mzorg_duty', function(source, args)
  if not canUseOrgCommand(source) then
    return reply(source, 'Sem permissão.')
  end

  local citizenid = args[1]
  local orgCode = args[2]
  local duty = toBool(args[3])

  if not citizenid or not orgCode or args[3] == nil then
    return reply(source, 'Uso: mzorg_duty [citizenid] [org] [on/off]')
  end

  local ok, err = exports['mz_core']:SetOrgMemberDuty(citizenid, orgCode, duty, source)
  if not ok then
    return reply(source, ('Erro: %s'):format(err or 'unknown'))
  end

  reply(source, ('Duty de %s em %s = %s'):format(citizenid, orgCode, tostring(duty)))
end, true)

RegisterCommand('mzorg_primary', function(source, args)
  if not canUseOrgCommand(source) then
    return reply(source, 'Sem permissão.')
  end

  local citizenid = args[1]
  local orgCode = args[2]

  if not citizenid or not orgCode then
    return reply(source, 'Uso: mzorg_primary [citizenid] [org]')
  end

  local ok, err = exports['mz_core']:SetOrgMemberPrimary(citizenid, orgCode, source)
  if not ok then
    return reply(source, ('Erro: %s'):format(err or 'unknown'))
  end

  reply(source, ('Org primária de %s definida para %s'):format(citizenid, orgCode))
end, true)

RegisterCommand('mzorg_reload', function(source, args)
  if not canUseOrgCommand(source) then
    return reply(source, 'Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  if not targetSource then
    return reply(source, 'Uso: mzorg_reload [source]')
  end

  local ok, err = reloadTarget(targetSource)
  if not ok then
    return reply(source, ('Erro: %s'):format(err or 'unknown'))
  end

  reply(source, ('Orgs recarregadas para source %s'):format(targetSource))
end, true)

RegisterCommand('mzorg_info', function(source, args)
  if not canUseOrgCommand(source) then
    return reply(source, 'Sem permissão.')
  end

  local citizenid = args[1]
  if not citizenid then
    return reply(source, 'Uso: mzorg_info [citizenid]')
  end

  local rows = MZOrgRepository.getPlayerMemberships(citizenid)
  if not rows or #rows == 0 then
    return reply(source, ('Nenhuma org encontrada para %s'):format(citizenid))
  end

  reply(source, ('Orgs de %s:'):format(citizenid))
  for _, row in ipairs(rows) do
    reply(source, ('- %s (%s) | grade %s [%s] | primary=%s duty=%s'):format(
      row.org_name or row.org_code,
      row.org_code,
      tostring(row.grade_level),
      row.grade_name or row.grade_code,
      tostring(asBool(row.is_primary)),
      tostring(asBool(row.duty))
    ))
  end
end, true)
