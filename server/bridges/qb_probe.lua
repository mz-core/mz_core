local DEBUG_ACE = 'mzcore.debug'
local DEBUG_ALLOW_CONSOLE = true

local function isAceAllowed(src, ace)
  local sourceId = tonumber(src)
  if not sourceId or sourceId <= 0 then return false end

  ace = tostring(ace or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if ace == '' then return false end

  local allowed = IsPlayerAceAllowed(sourceId, ace)
  local normalized = tostring(allowed):lower()
  return allowed == true or allowed == 1 or normalized == '1' or normalized == 'true'
end

local function isDebugAllowed(source)
  if source == 0 then
    return DEBUG_ALLOW_CONSOLE
  end

  return isAceAllowed(source, DEBUG_ACE)
end

local function probePrint(source, message)
  if source == 0 then
    print(('[mz_core][qb_probe] %s'):format(message))
    return
  end

  TriggerClientEvent('chat:addMessage', source, {
    color = { 255, 200, 0 },
    multiline = false,
    args = { 'mz_core', message }
  })
end

local function arrayHasValue(list, expected)
  if type(list) ~= 'table' then
    return false
  end

  for _, value in ipairs(list) do
    if tonumber(value) == tonumber(expected) then
      return true
    end
  end

  return false
end

local function encodeJson(value)
  if type(value) ~= 'table' then
    return '{}'
  end

  return json.encode(value) or '{}'
end

local function callBridgeMethod(method, ...)
  if type(method) ~= 'function' then
    return false, 'missing_method'
  end

  return method(method, ...)
end

local function pickCharinfoField(charinfo)
  charinfo = type(charinfo) == 'table' and charinfo or {}

  for _, field in ipairs({ 'firstname', 'lastname', 'birthdate', 'gender', 'nationality', 'phone' }) do
    if charinfo[field] ~= nil then
      return field, charinfo[field]
    end
  end

  return nil, nil
end

RegisterCommand('mqb_probe', function(source, args)
  if not isDebugAllowed(source) then
    probePrint(source, 'Sem permissão.')
    return
  end

  local targetSource = tonumber(args[1])
  if not targetSource then
    probePrint(source, 'Uso: mqb_probe [source]')
    return
  end

  local QB = exports['mz_core']:GetCoreObject()
  if type(QB) ~= 'table' or type(QB.Functions) ~= 'table' then
    probePrint(source, 'Bridge QB indisponível.')
    return
  end

  local Player = QB.Functions.GetPlayer(targetSource)
  if not Player or type(Player.PlayerData) ~= 'table' then
    probePrint(source, ('Player não encontrado para source=%s'):format(targetSource))
    return
  end

  local playerData = Player.PlayerData
  local citizenid = tostring(playerData.citizenid or 'nil')
  local orgCount = type(playerData.orgs) == 'table' and #playerData.orgs or 0
  local itemCount = type(playerData.items) == 'table' and #playerData.items or 0
  local token = tostring(os.time())
  local metadataKey = '__mz_qb_probe_meta'
  local metadataSpdKey = '__mz_qb_probe_spd_meta'
  local metadataValue = ('setmeta_%s'):format(token)
  local metadataSpdValue = ('setplayer_%s'):format(token)

  probePrint(source, ('snapshot | citizenid=%s | job=%s | gang=%s | orgs=%s | items=%s'):format(
    citizenid,
    tostring(playerData.job and playerData.job.name or 'nil'),
    tostring(playerData.gang and playerData.gang.name or 'nil'),
    tostring(orgCount),
    tostring(itemCount)
  ))

  local playerByCitizen = QB.Functions.GetPlayerByCitizenId(playerData.citizenid)
  local lookupSource = QB.Functions.GetSource(playerData.citizenid)
  local loadedPlayers = QB.Functions.GetPlayers()
  local qbPlayers = QB.Functions.GetQBPlayers()

  probePrint(source, ('lookups | by_citizenid=%s | getsource=%s | getplayers_has=%s | getqbplayers_has=%s'):format(
    tostring(playerByCitizen ~= nil),
    tostring(lookupSource),
    tostring(arrayHasValue(loadedPlayers, targetSource)),
    tostring(type(qbPlayers) == 'table' and qbPlayers[targetSource] ~= nil)
  ))

  local bankDot = nil
  if Player.Functions and type(Player.Functions.GetMoney) == 'function' then
    bankDot = Player.Functions.GetMoney('bank')
  end

  local bankBound = nil
  if Player.Functions and type(Player.Functions.GetMoney) == 'function' then
    bankBound = Player.Functions.GetMoney(Player.Functions, 'bank')
  end

  local bankPlayerData = tonumber(playerData.money and playerData.money.bank or 0) or 0
  probePrint(source, ('money | dot=%s | bound=%s | playerdata=%s'):format(
    tostring(bankDot),
    tostring(bankBound),
    tostring(bankPlayerData)
  ))

  local oldMetadataValue = nil
  if Player.Functions and type(Player.Functions.GetMetaData) == 'function' then
    oldMetadataValue = Player.Functions.GetMetaData(Player.Functions, metadataKey)
  end

  local oldMetadataSpdValue = nil
  if Player.Functions and type(Player.Functions.GetMetaData) == 'function' then
    oldMetadataSpdValue = Player.Functions.GetMetaData(Player.Functions, metadataSpdKey)
  end

  local setMetaOk, setMetaResult = callBridgeMethod(Player.Functions.SetMetaData, metadataKey, metadataValue)
  local getMetaValue = Player.Functions.GetMetaData and Player.Functions.GetMetaData(Player.Functions, metadataKey) or nil
  local staleBeforeUpdate = Player.PlayerData.metadata and Player.PlayerData.metadata[metadataKey] or nil
  Player.Functions.UpdatePlayerData(Player.Functions)
  local metadataAfterUpdate = Player.PlayerData.metadata and Player.PlayerData.metadata[metadataKey] or nil

  probePrint(source, ('metadata | set_ok=%s | set_result=%s | get=%s | playerdata_before_update=%s | playerdata_after_update=%s'):format(
    tostring(setMetaOk),
    tostring(setMetaResult),
    tostring(getMetaValue),
    tostring(staleBeforeUpdate),
    tostring(metadataAfterUpdate)
  ))

  local setPlayerMetadataOk, setPlayerMetadataResult = callBridgeMethod(Player.Functions.SetPlayerData, 'metadata', {
    [metadataSpdKey] = metadataSpdValue
  })
  local playerMetadataAfterSet = Player.PlayerData.metadata and Player.PlayerData.metadata[metadataSpdKey] or nil

  probePrint(source, ('setplayerdata(metadata) | ok=%s | result=%s | playerdata=%s'):format(
    tostring(setPlayerMetadataOk),
    tostring(setPlayerMetadataResult),
    tostring(playerMetadataAfterSet)
  ))

  local charinfoField, oldCharinfoValue = pickCharinfoField(Player.PlayerData.charinfo)
  local charinfoRestored = 'skipped'

  if charinfoField then
    local tempCharinfoValue = ('qb_probe_%s_%s'):format(charinfoField, token)
    local setCharinfoOk, setCharinfoResult = callBridgeMethod(Player.Functions.SetPlayerData, 'charinfo', {
      [charinfoField] = tempCharinfoValue
    })
    local charinfoAfterSet = Player.PlayerData.charinfo and Player.PlayerData.charinfo[charinfoField] or nil

    probePrint(source, ('setplayerdata(charinfo) | field=%s | ok=%s | result=%s | before=%s | after=%s'):format(
      tostring(charinfoField),
      tostring(setCharinfoOk),
      tostring(setCharinfoResult),
      tostring(oldCharinfoValue),
      tostring(charinfoAfterSet)
    ))

    local restoreOk = callBridgeMethod(Player.Functions.SetPlayerData, 'charinfo', {
      [charinfoField] = oldCharinfoValue
    })
    charinfoRestored = tostring(restoreOk)
  else
    probePrint(source, 'setplayerdata(charinfo) | skipped=no_non_nil_field')
  end

  Player.Functions.SetMetaData(Player.Functions, metadataKey, oldMetadataValue)
  Player.Functions.SetMetaData(Player.Functions, metadataSpdKey, oldMetadataSpdValue)
  Player.Functions.UpdatePlayerData(Player.Functions)

  local restoredMetaValue = Player.PlayerData.metadata and Player.PlayerData.metadata[metadataKey] or nil
  local restoredSpdMetaValue = Player.PlayerData.metadata and Player.PlayerData.metadata[metadataSpdKey] or nil
  local restoredCharinfoValue = charinfoField and Player.PlayerData.charinfo and Player.PlayerData.charinfo[charinfoField] or nil

  probePrint(source, ('cleanup | meta=%s | spd_meta=%s | charinfo_restored=%s | charinfo_value=%s'):format(
    tostring(restoredMetaValue),
    tostring(restoredSpdMetaValue),
    tostring(charinfoRestored),
    tostring(restoredCharinfoValue)
  ))

  for index = 1, math.min(itemCount, 2) do
    local item = Player.PlayerData.items[index]
    if type(item) == 'table' then
      probePrint(source, ('item[%s] | slot=%s | name=%s | item=%s | amount=%s | uid=%s | label=%s | weight=%s | unique=%s | metadata=%s'):format(
        tostring(index),
        tostring(item.slot),
        tostring(item.name),
        tostring(item.item),
        tostring(item.amount),
        tostring(item.instance_uid),
        tostring(item.label),
        tostring(item.weight),
        tostring(item.unique),
        encodeJson(item.metadata)
      ))
    end
  end
end, false)
