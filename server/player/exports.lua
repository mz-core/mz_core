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

local function resolvePlayerIdentityInternal(source)
  local identity = MZIdentityService.resolvePlayerIdentity(source)
  logIdentityResolve(source, ('result ok=%s error=%s account=%s character=%s'):format(
    tostring(identity and identity.ok), tostring(identity and identity.error),
    tostring(identity and identity.accountId), tostring(identity and identity.characterId)
  ))
  return identity
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
  if GetInvokingResource() ~= 'mz_phone' then return false, 'not_authorized' end
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

exports('GetPlayerByCitizenIdSnapshot', function(citizenid)
  return MZPlayerService.getPlayerByCitizenIdSnapshot(citizenid)
end)

exports('GetCharacterByCitizenId', function(citizenid)
  citizenid = tostring(citizenid or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if citizenid == '' then return nil end
  local row = MZPlayerRepository.getByCitizenId(citizenid)
  if type(row) ~= 'table' then return nil end
  return {
    id = tonumber(row.id),
    accountId = tonumber(row.account_id),
    citizenid = tostring(row.citizenid or ''),
    firstname = tostring(row.firstname or ''),
    lastname = tostring(row.lastname or ''),
    phone = tostring(row.phone or ''),
    characterStatus = tostring(row.character_status or 'active')
  }
end)

exports('SearchCharacters', function(search, page, pageSize)
  search = tostring(search or ''):gsub('%c', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 64)
  if #search < 2 then
    return { items = {}, total = 0, page = 1, pageSize = 25, hasMore = false }
  end
  page = math.max(1, math.floor(tonumber(page) or 1))
  pageSize = math.max(1, math.min(50, math.floor(tonumber(pageSize) or 25)))
  local rows, total = MZIdentityRepository.searchCharacters(search, pageSize, (page - 1) * pageSize)
  local items = {}
  for _, row in ipairs(rows or {}) do
    items[#items + 1] = {
      characterId = tonumber(row.id),
      accountId = tonumber(row.account_id),
      citizenid = tostring(row.citizenid or ''),
      firstname = tostring(row.firstname or ''),
      lastname = tostring(row.lastname or ''),
      characterStatus = tostring(row.character_status or 'active')
    }
  end
  total = math.max(0, tonumber(total) or 0)
  return {
    items = items,
    total = total,
    page = page,
    pageSize = pageSize,
    hasMore = page * pageSize < total
  }
end)

exports('GetSourceByCitizenId', function(citizenid)
  return MZPlayerService.getSourceByCitizenId(citizenid)
end)

exports('SetCharinfo', function(source, charinfo)
  if GetInvokingResource() ~= 'mz_creator' then return false, 'not_authorized' end
  return MZPlayerService.setCharinfo(source, charinfo)
end)

exports('GetPlayerSession', function(source)
  return MZIdentityService.getSessionSnapshot(source)
end)

exports('IsPlayerLoaded', function(source)
  return MZPlayerService.isPlayerLoaded(source)
end)

exports('GetAccountId', function(source)
  return MZIdentityService.getAccountId(source)
end)

exports('GetActiveCharacterId', function(source)
  return MZIdentityService.getActiveCharacterId(source)
end)

exports('GetActiveCharacter', function(source)
  local characterId = MZIdentityService.getActiveCharacterId(source)
  return characterId and MZIdentityService.getCharacterSnapshot(characterId) or nil
end)

exports('GetCharacterSnapshot', function(characterId)
  return MZIdentityService.getCharacterSnapshot(characterId)
end)

exports('GetCharactersForAccount', function(accountId)
  return MZIdentityService.getCharactersForAccount(accountId)
end)

exports('IsCharacterActive', function(source)
  local session = MZIdentityService.getSession(source)
  return session ~= nil and session.isActive == true
    and session.lifecycle == 'CHARACTER_ACTIVE'
    and session.activeCharacterId ~= nil
end)

exports('GetCharacterRosterForSource', function(source)
  return MZIdentityService.getRosterForSource(source)
end)

exports('GetPendingCharacterSnapshot', function(source)
  return MZIdentityService.getPendingCharacterSnapshot(source)
end)

local function mutationCallerAllowed(expected)
  local caller = GetInvokingResource()
  if expected then return caller == expected end
  return caller and (Config.Multichar or {}).mutationCallers
    and Config.Multichar.mutationCallers[caller] == true
end

exports('CreateCharacterDraft', function(source, requestKey)
  if not mutationCallerAllowed('mz_multichar') then return nil, 'not_authorized' end
  return MZIdentityService.createCharacterDraft(source, requestKey)
end)

exports('ActivateCharacter', function(source, characterId, requestKey)
  if not mutationCallerAllowed('mz_multichar') then return nil, 'not_authorized' end
  return MZIdentityService.activateCharacter(source, characterId, requestKey)
end)

exports('FinalizePendingCharacter', function(source, charinfo, requestKey)
  if not mutationCallerAllowed('mz_creator') then return nil, 'not_authorized' end
  return MZIdentityService.finalizePendingCharacter(source, charinfo, requestKey)
end)

exports('CancelPendingCharacter', function(source)
  if not mutationCallerAllowed() then return false, 'not_authorized' end
  return MZIdentityService.cancelPendingCharacter(source)
end)

exports('ReturnToCharacterSelection', function()
  return false, 'hot_switch_not_safe'
end)
