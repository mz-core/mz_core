MZBridgeAdapter = MZBridgeAdapter or {}

local function cloneTable(value)
  if type(value) ~= 'table' then
    return value
  end

  local out = {}
  for k, v in pairs(value) do
    out[k] = cloneTable(v)
  end

  return out
end

local function buildQBRole(orgData, defaultType)
  defaultType = tostring(defaultType or 'job')

  if type(orgData) ~= 'table' then
    return {
      name = 'unemployed',
      label = 'Unemployed',
      onduty = false,
      isboss = false,
      type = defaultType,
      grade = {
        name = 'none',
        level = 0
      }
    }
  end

  local permissions = type(orgData.permissions) == 'table' and orgData.permissions or {}

  return {
    name = tostring(orgData.code or 'unknown'),
    label = tostring(orgData.name or orgData.code or 'Unknown'),
    onduty = orgData.duty == true,
    isboss = permissions.manage_members == true,
    type = tostring(orgData.type or defaultType),
    grade = {
      name = tostring(orgData.grade and orgData.grade.name or 'none'),
      level = tonumber(orgData.grade and orgData.grade.level) or 0
    }
  }
end

local function normalizeInventoryItem(row)
  row = type(row) == 'table' and row or {}

  local itemName = tostring(row.item or row.name or '')
  local itemDef = type(MZItems) == 'table' and MZItems[itemName] or nil

  return {
    slot = tonumber(row.slot) or 0,
    name = itemName,
    item = itemName,
    amount = tonumber(row.amount) or 0,
    metadata = cloneTable(type(row.metadata) == 'table' and row.metadata or {}),
    instance_uid = row.instance_uid and tostring(row.instance_uid) or nil,
    label = tostring(itemDef and itemDef.label or itemName),
    weight = tonumber(itemDef and itemDef.weight or 0) or 0,
    unique = itemDef and itemDef.unique == true or false
  }
end

local function getPlayerBase(source, opts)
  opts = opts or {}

  local player = MZPlayerService.getPlayer(source)
  local loadedNow = false

  if not player and opts.ensureLoaded ~= false then
    player = MZPlayerService.loadPlayer(source)
    loadedNow = player ~= nil
  end

  if player and (loadedNow or opts.reloadOrgs == true) and MZOrgService and MZOrgService.loadPlayerOrgs then
    MZOrgService.loadPlayerOrgs(source)
    player = MZPlayerService.getPlayer(source) or player
  end

  return player
end

function MZBridgeAdapter.getBridgeConfig()
  return {
    Player = cloneTable(Config.Player or {}),
    StarterMoney = cloneTable(Config.StarterMoney or {})
  }
end

function MZBridgeAdapter.getSharedItems()
  return cloneTable(MZItems or {})
end

function MZBridgeAdapter.getPlayerSnapshot(source, opts)
  local player = getPlayerBase(source, opts)
  if not player then
    return nil
  end

  local items = {}

  if MZInventoryService and MZInventoryService.getPlayerInventory then
    local ok, inventoryRows = MZInventoryService.getPlayerInventory(player.source)
    if ok and type(inventoryRows) == 'table' then
      for _, row in ipairs(inventoryRows) do
        items[#items + 1] = normalizeInventoryItem(row)
      end
    end
  end

  return {
    source = player.source,
    license = player.license,
    citizenid = player.citizenid,
    charinfo = cloneTable(player.charinfo or {}),
    metadata = cloneTable(player.metadata or {}),
    money = cloneTable(player.money or {}),
    orgs = cloneTable(player.orgs or {}),
    job = buildQBRole(player.job, 'job'),
    gang = buildQBRole(player.gang, 'gang'),
    items = items,
    state = cloneTable(player.state or {}),
    session = cloneTable(player.session or {})
  }
end

function MZBridgeAdapter.getSourceByCitizenId(citizenid)
  return MZPlayerService.getSourceByCitizenId(citizenid)
end

function MZBridgeAdapter.getIdentifier(source, idType)
  idType = tostring(idType or 'license')

  local player = MZPlayerService.getPlayer(source)
  if not player then
    return nil
  end

  if idType == 'license' then
    return player.license
  end

  if idType == 'citizenid' then
    return player.citizenid
  end

  return nil
end

function MZBridgeAdapter.getMoneyAmount(source, moneyType)
  local money = MZAccountService.getMoney(source) or {}
  return tonumber(money[tostring(moneyType or ''):lower()]) or 0
end

function MZBridgeAdapter.hasPlayerItem(source, itemName, amount)
  return MZInventoryService.hasPlayerItem(source, itemName, amount or 1)
end

function MZBridgeAdapter.getMetadataValue(source, key)
  return MZPlayerService.getMetadataValue(source, key)
end

function MZBridgeAdapter.setMetadataValue(source, key, value)
  return MZPlayerService.setMetadataValue(source, key, value)
end

function MZBridgeAdapter.setCharinfo(source, charinfo)
  return MZPlayerService.setCharinfo(source, charinfo)
end

function MZBridgeAdapter.listLoadedSources()
  local sources = {}

  for source, _ in pairs(MZCache.playersBySource or {}) do
    sources[#sources + 1] = source
  end

  table.sort(sources)

  return sources
end
