MZBridgeQB = MZBridgeQB or {}

local function cloneTable(value)
  if type(value) ~= 'table' then
    return value
  end

  local out = {}
  for k, v in pairs(value) do
    if type(v) == 'table' then
      out[k] = cloneTable(v)
    else
      out[k] = v
    end
  end
  return out
end

local function buildQBJob(orgData)
  if type(orgData) ~= 'table' then
    return {
      name = 'unemployed',
      label = 'Unemployed',
      onduty = false,
      isboss = false,
      type = 'job',
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
    type = tostring(orgData.type or 'job'),
    grade = {
      name = tostring(orgData.grade and orgData.grade.name or 'none'),
      level = tonumber(orgData.grade and orgData.grade.level) or 0
    }
  }
end

local function buildQBGang(orgData)
  local gang = buildQBJob(orgData)
  gang.type = 'gang'
  return gang
end

local function buildQBPlayerData(player)
  if not player then
    return nil
  end

  local orgs = cloneTable(player.orgs or {})
  local items = {}

  if MZInventoryService and MZInventoryService.getPlayerInventory then
    local ok, inventoryRows = MZInventoryService.getPlayerInventory(player.source)
    if ok and type(inventoryRows) == 'table' then
      items = inventoryRows
    end
  end

  return {
    source = player.source,
    license = player.license,
    citizenid = player.citizenid,
    charinfo = cloneTable(player.charinfo or {}),
    metadata = cloneTable(player.metadata or {}),
    money = cloneTable(player.money or {}),
    orgs = orgs,
    job = buildQBJob(player.job),
    gang = buildQBGang(player.gang),
    items = items,
    state = cloneTable(player.state or {}),
    session = cloneTable(player.session or {})
  }
end

local function getPlayerWrapper(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then
    player = MZPlayerService.loadPlayer(source)
    if player and MZOrgService and MZOrgService.loadPlayerOrgs then
      MZOrgService.loadPlayerOrgs(source)
    end
  end

  if not player then
    return nil
  end

  local wrapper = {
    PlayerData = buildQBPlayerData(player),
    Functions = {}
  }

  wrapper.Functions.AddMoney = function(_, moneyType, amount, reason)
    return MZAccountService.addMoney(source, moneyType, amount, {
      actorSource = source,
      reason = reason or 'qb_bridge_add_money',
      sourceType = 'qb_bridge'
    })
  end

  wrapper.Functions.RemoveMoney = function(_, moneyType, amount, reason)
    return MZAccountService.removeMoney(source, moneyType, amount, {
      actorSource = source,
      reason = reason or 'qb_bridge_remove_money',
      sourceType = 'qb_bridge'
    })
  end

  wrapper.Functions.SetMoney = function(_, moneyType, amount, reason)
    return MZAccountService.setMoney(source, moneyType, amount, {
      actorSource = source,
      reason = reason or 'qb_bridge_set_money',
      sourceType = 'qb_bridge'
    })
  end

  wrapper.Functions.GetMoney = function(_, moneyType)
    local money = MZAccountService.getMoney(source) or {}
    return tonumber(money[tostring(moneyType or ''):lower()]) or 0
  end

  wrapper.Functions.AddItem = function(_, itemName, amount, metadata)
    return MZInventoryService.addPlayerItem(source, itemName, amount, metadata)
  end

  wrapper.Functions.RemoveItem = function(_, itemName, amount)
    return MZInventoryService.removePlayerItem(source, itemName, amount)
  end

  wrapper.Functions.HasItem = function(_, itemName, amount)
    return MZInventoryService.hasPlayerItem(source, itemName, amount or 1)
  end

  wrapper.Functions.SetMetaData = function(_, key, value)
    return MZPlayerService.setMetadataValue(source, key, value)
  end

  wrapper.Functions.GetMetaData = function(_, key)
    return MZPlayerService.getMetadataValue(source, key)
  end

  wrapper.Functions.SetPlayerData = function(_, field, value)
    if field == 'metadata' and type(value) == 'table' then
      local ok = true
      for metaKey, metaValue in pairs(value) do
        local updated = MZPlayerService.setMetadataValue(source, metaKey, metaValue)
        ok = ok and updated == true
      end
      wrapper.PlayerData = buildQBPlayerData(MZPlayerService.getPlayer(source))
      return ok
    end

    if field == 'charinfo' and type(value) == 'table' then
      local ok = MZPlayerService.setCharinfo(source, value)
      wrapper.PlayerData = buildQBPlayerData(MZPlayerService.getPlayer(source))
      return ok
    end

    return false, 'unsupported_field'
  end

  wrapper.Functions.UpdatePlayerData = function(_)
    local current = MZPlayerService.getPlayer(source)
    if current and MZOrgService and MZOrgService.loadPlayerOrgs then
      MZOrgService.loadPlayerOrgs(source)
    end
    wrapper.PlayerData = buildQBPlayerData(current)
    return wrapper.PlayerData
  end

  return wrapper
end

function MZBridgeQB.getCoreObject()
  return {
    Config = {
      Player = cloneTable(Config.Player or {}),
      StarterMoney = cloneTable(Config.StarterMoney or {})
    },
    Shared = {
      Items = cloneTable(MZItems or {})
    },
    Functions = {
      GetPlayer = function(source)
        return getPlayerWrapper(source)
      end,
      GetPlayerData = function(source)
        local wrapper = getPlayerWrapper(source)
        return wrapper and wrapper.PlayerData or nil
      end,
      GetPlayerByCitizenId = function(citizenid)
        local source = MZPlayerService.getSourceByCitizenId(citizenid)
        return source and getPlayerWrapper(source) or nil
      end,
      GetIdentifier = function(source, idType)
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
      end,
      GetSource = function(citizenid)
        return MZPlayerService.getSourceByCitizenId(citizenid)
      end,
      GetPlayers = function()
        local sources = {}
        for source, _ in pairs(MZCache.playersBySource or {}) do
          sources[#sources + 1] = source
        end
        table.sort(sources)
        return sources
      end,
      GetQBPlayers = function()
        local players = {}
        for source, _ in pairs(MZCache.playersBySource or {}) do
          players[source] = getPlayerWrapper(source)
        end
        return players
      end,
      GetItems = function()
        return cloneTable(MZItems or {})
      end
    }
  }
end

exports('GetCoreObject', function()
  return MZBridgeQB.getCoreObject()
end)
