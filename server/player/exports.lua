local function identityDebugEnabled()
  return Config and Config.Debug == true
end

local function aceAllowed(source, ace)
  source = tonumber(source)
  ace = tostring(ace or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if not source or source <= 0 or ace == '' then return false end
  local allowed = IsPlayerAceAllowed(source, ace)
  local normalized = tostring(allowed):lower()
  return allowed == true or allowed == 1 or normalized == '1' or normalized == 'true'
end

local function canUseIdentityDebug(source)
  if not identityDebugEnabled() then return false end
  source = tonumber(source) or 0
  if source <= 0 then return true end
  return aceAllowed(source, 'mzcore.debug')
    or aceAllowed(source, (Config and Config.OwnerAce) or 'group.mz_owner')
end

if identityDebugEnabled() then
  print('[mz_core][player/exports] loaded')
end

local LegacyPlayerReadWarnings = {}
local function warnLegacyPlayerRead(contract)
  local invokingResource = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil
  if type(invokingResource) ~= 'string' or invokingResource == '' then return end
  local key = invokingResource .. ':' .. contract
  if LegacyPlayerReadWarnings[key] then return end
  LegacyPlayerReadWarnings[key] = true
  print(('[mz_core][deprecated] resource=%s contract=%s replacement=%s'):format(
    invokingResource, contract, contract == 'GetPlayer' and 'GetPlayerSnapshot' or 'GetPlayerByCitizenIdSnapshot'
  ))
end

exports('GetPlayer', function(source)
  warnLegacyPlayerRead('GetPlayer')
  return MZPlayerService.getPlayer(source)
end)

exports('GetPlayerSnapshot', function(source)
  return MZPlayerService.getPlayerSnapshot(source)
end)

local function getLicenseForSource(source)
  for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
    if identifier:find('license:') == 1 then
      return identifier
    end
  end

  return nil
end

local function maskValue(value)
  value = tostring(value or '')
  if value == '' then return '' end
  if #value <= 12 then return value end
  return value:sub(1, 8) .. '...' .. value:sub(-4)
end

local function summarizeIdentifiers(source)
  source = tonumber(source)
  if not source or source <= 0 then
    return ''
  end

  local out = {}

  local ok, identifiers = pcall(function()
    return GetPlayerIdentifiers(source)
  end)

  if not ok or type(identifiers) ~= 'table' then
    return 'unavailable'
  end

  for _, identifier in ipairs(identifiers) do
    local kind = identifier:match('^([^:]+):') or 'unknown'
    out[#out + 1] = ('%s=%s'):format(kind, maskValue(identifier))
  end

  return table.concat(out, ',')
end

local function logIdentityResolve(source, message)
  if not identityDebugEnabled() then return end
  print(('[mz_core][ResolvePlayerIdentity][src:%s] %s'):format(tostring(source), tostring(message or '')))
end

local function buildIdentityFromRow(source, row, loadedFrom)
  if type(row) ~= 'table' or tostring(row.citizenid or '') == '' then
    return nil
  end

  return {
    ok = true,
    source = tonumber(source),
    license = tostring(row.license or ''),
    citizenid = tostring(row.citizenid or ''),
    firstname = tostring(row.firstname or ''),
    lastname = tostring(row.lastname or ''),
    phone = tostring(row.phone or ''),
    loadedFrom = loadedFrom
  }
end

local function buildIdentityFromPlayer(source, player, loadedFrom)
  if type(player) ~= 'table' or tostring(player.citizenid or '') == '' then
    return nil
  end

  local charinfo = type(player.charinfo) == 'table' and player.charinfo or {}

  return {
    ok = true,
    source = tonumber(source),
    license = tostring(player.license or ''),
    citizenid = tostring(player.citizenid or ''),
    firstname = tostring(charinfo.firstname or player.firstname or ''),
    lastname = tostring(charinfo.lastname or player.lastname or ''),
    phone = tostring(charinfo.phone or player.phone or ''),
    loadedFrom = loadedFrom
  }
end

local function resolvePlayerIdentityInternal(source)
  logIdentityResolve(source, ('source=%s type=%s'):format(tostring(source), type(source)))
  source = tonumber(source)
  logIdentityResolve(source, 'start')
  logIdentityResolve(source, ('start identifiers=%s'):format(summarizeIdentifiers(source)))

  if not source or source <= 0 then
    logIdentityResolve(source, 'result error=invalid_source')
    return { ok = false, error = 'invalid_source' }
  end

  local player = MZPlayerService.getPlayer(source)
  local identity = buildIdentityFromPlayer(source, player, 'cache')
  if identity then
    logIdentityResolve(source, ('result ok source=cache citizenid=%s phone=%s'):format(maskValue(identity.citizenid), identity.phone ~= '' and 'set' or 'empty'))
    return identity
  end

  local session = MZPlayerService.getPlayerSession(source)
  logIdentityResolve(source, ('cache=nil session=%s'):format(type(session)))
  if type(session) == 'table' and tostring(session.citizenid or '') ~= '' then
    local ok, row = pcall(function()
      return MZPlayerRepository.getByCitizenId(session.citizenid)
    end)

    if not ok then
      logIdentityResolve(source, ('result error=database_error stage=session detail=%s'):format(tostring(row)))
      return { ok = false, error = 'database_error', detail = tostring(row) }
    end

    identity = buildIdentityFromRow(source, row, 'session')
    if identity then
      logIdentityResolve(source, ('result ok source=session citizenid=%s phone=%s'):format(maskValue(identity.citizenid), identity.phone ~= '' and 'set' or 'empty'))
      return identity
    end
  end

  local license = getLicenseForSource(source)
  if not license then
    logIdentityResolve(source, 'result error=missing_license')
    return { ok = false, error = 'missing_license' }
  end

  logIdentityResolve(source, ('license=%s'):format(maskValue(license)))
  logIdentityResolve(source, ('query mz_players by license=%s'):format(maskValue(license)))

  local ok, row = pcall(function()
    return MySQL.single.await([[
      SELECT id, license, citizenid, firstname, lastname, phone
      FROM mz_players
      WHERE license = ?
      LIMIT 1
    ]], { license })
  end)

  if not ok then
    logIdentityResolve(source, ('result error=database_error detail=%s'):format(tostring(row)))
    return { ok = false, error = 'database_error', detail = tostring(row) }
  end

  identity = buildIdentityFromRow(source, row, 'database')
  if identity then
    logIdentityResolve(source, ('result ok source=database citizenid=%s phone=%s'):format(maskValue(identity.citizenid), identity.phone ~= '' and 'set' or 'empty'))
    return identity
  end

  logIdentityResolve(source, 'result error=player_not_found')
  return { ok = false, error = 'player_not_found' }
end

exports('ResolvePlayerIdentity', function(source)
  return resolvePlayerIdentityInternal(source)
end)

if identityDebugEnabled() then
  print('[mz_core][player/exports] ResolvePlayerIdentity registered')
end

RegisterCommand('mzcore_identity_debug', function(commandSource, args)
  if not canUseIdentityDebug(commandSource) then return end

  local targetSource = tonumber(args and args[1])

  if commandSource and commandSource > 0 and not targetSource then
    targetSource = commandSource
  end

  if not targetSource or targetSource <= 0 then
    print('[mz_core][identity_debug] uso: mzcore_identity_debug ID')
    return
  end

  print(('===== mz_core identity debug source=%s ====='):format(tostring(targetSource)))
  print(('identifiers=%s'):format(summarizeIdentifiers(targetSource)))

  local license = getLicenseForSource(targetSource)
  print(('license=%s'):format(license and maskValue(license) or 'missing'))

  local identity = resolvePlayerIdentityInternal(targetSource)
  if identity and identity.ok == true then
    print(('result=ok source=%s citizenid=%s phone=%s'):format(
      tostring(identity.loadedFrom or ''),
      maskValue(identity.citizenid),
      identity.phone ~= '' and identity.phone or 'empty'
    ))
  else
    print(('result=failed error=%s detail=%s'):format(
      tostring(identity and identity.error or 'unknown'),
      tostring(identity and identity.detail or '')
    ))
  end

  print('==========================================')
end, false)

exports('SetPlayerPhoneByCitizenId', function(citizenid, phone)
  citizenid = tostring(citizenid or '')
  phone = tostring(phone or '')

  if citizenid == '' then
    return false, 'missing_citizenid'
  end

  local ok, err = pcall(function()
    MZPlayerRepository.updatePhone(citizenid, phone)
  end)

  if not ok then
    return false, 'database_error'
  end

  local player = MZPlayerService.getPlayerByCitizenId(citizenid)
  if player then
    player.charinfo = player.charinfo or {}
    player.charinfo.phone = phone
  end

  return true
end)

exports('EnsurePlayerLoaded', function(source)
  source = tonumber(source)
  if not source or source <= 0 then
    return nil, 'invalid_source'
  end

  local player = MZPlayerService.getPlayer(source)
  if player then
    MZPlayerService.touchPlayer(source)
    return player, 'already_loaded'
  end

  local loadErr
  player, loadErr = MZPlayerService.loadPlayer(source)
  if not player then
    return nil, loadErr or 'load_failed'
  end

  if MZOrgService and MZOrgService.loadPlayerOrgs then
    local orgOk, orgErr = pcall(function()
      MZOrgService.loadPlayerOrgs(source)
    end)

    if not orgOk then
      print(('[mz_core] EnsurePlayerLoaded org load failed source=%s error=%s'):format(tostring(source), tostring(orgErr)))
    end
  end

  local identityOk, syncIdentity = MZPlayerStateService.getSyncIdentity(source)
  TriggerClientEvent(
    'mz_core:client:playerLoaded',
    source,
    player,
    identityOk and syncIdentity.sessionToken or nil
  )

  if MZPlayerStateSyncService and MZPlayerStateSyncService.sync then
    MZPlayerStateSyncService.sync(source, 'ensure_player_loaded', {
      forcePhysicalApply = true,
      sessionReset = true
    })
  end

  return player, 'loaded'
end)

exports('GetPlayerByCitizenId', function(citizenid)
  warnLegacyPlayerRead('GetPlayerByCitizenId')
  return MZPlayerService.getPlayerByCitizenId(citizenid)
end)

exports('GetPlayerByCitizenIdSnapshot', function(citizenid)
  return MZPlayerService.getPlayerByCitizenIdSnapshot(citizenid)
end)

exports('GetSourceByCitizenId', function(citizenid)
  return MZPlayerService.getSourceByCitizenId(citizenid)
end)

exports('SetMetadataValue', function(source, key, value)
  return MZPlayerService.setMetadataValue(source, key, value, {
    internal = false,
    invokingResource = GetInvokingResource(),
    reason = 'legacy_metadata_export'
  })
end)

exports('GetMetadataValue', function(source, key)
  return MZPlayerService.getMetadataValue(source, key)
end)

exports('SetCharinfo', function(source, charinfo)
  return MZPlayerService.setCharinfo(source, charinfo)
end)

exports('GetPlayerSession', function(source)
  return MZPlayerService.getPlayerSession(source)
end)

exports('IsPlayerLoaded', function(source)
  return MZPlayerService.isPlayerLoaded(source)
end)

exports('GetHUDState', function(source)
  return MZPlayerHUDService.getStateForSource(source)
end)
