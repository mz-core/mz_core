MZBridgeQB = MZBridgeQB or {}

local function getPlayerWrapper(source)
  local snapshot = MZBridgeAdapter.getPlayerSnapshot(source)
  if not snapshot then
    return nil
  end

  local wrapper = {
    PlayerData = snapshot,
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
    return MZBridgeAdapter.getMoneyAmount(source, moneyType)
  end

  wrapper.Functions.AddItem = function(_, itemName, amount, metadata)
    return MZInventoryService.addPlayerItem(source, itemName, amount, metadata)
  end

  wrapper.Functions.RemoveItem = function(_, itemName, amount)
    return MZInventoryService.removePlayerItem(source, itemName, amount)
  end

  wrapper.Functions.HasItem = function(_, itemName, amount)
    return MZBridgeAdapter.hasPlayerItem(source, itemName, amount or 1)
  end

  wrapper.Functions.SetMetaData = function(_, key, value)
    return MZBridgeAdapter.setMetadataValue(source, key, value)
  end

  wrapper.Functions.GetMetaData = function(_, key)
    return MZBridgeAdapter.getMetadataValue(source, key)
  end

  wrapper.Functions.SetPlayerData = function(_, field, value)
    if field == 'metadata' and type(value) == 'table' then
      local ok = true
      for metaKey, metaValue in pairs(value) do
        local updated = MZBridgeAdapter.setMetadataValue(source, metaKey, metaValue)
        ok = ok and updated == true
      end
      wrapper.PlayerData = MZBridgeAdapter.getPlayerSnapshot(source, {
        ensureLoaded = false
      })
      return ok
    end

    if field == 'charinfo' and type(value) == 'table' then
      local ok = MZBridgeAdapter.setCharinfo(source, value)
      wrapper.PlayerData = MZBridgeAdapter.getPlayerSnapshot(source, {
        ensureLoaded = false
      })
      return ok
    end

    return false, 'unsupported_field'
  end

  wrapper.Functions.UpdatePlayerData = function(_)
    wrapper.PlayerData = MZBridgeAdapter.getPlayerSnapshot(source, {
      ensureLoaded = false,
      reloadOrgs = true
    })
    return wrapper.PlayerData
  end

  return wrapper
end

function MZBridgeQB.getCoreObject()
  return {
    Config = MZBridgeAdapter.getBridgeConfig(),
    Shared = {
      Items = MZBridgeAdapter.getSharedItems()
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
        local source = MZBridgeAdapter.getSourceByCitizenId(citizenid)
        return source and getPlayerWrapper(source) or nil
      end,
      GetIdentifier = function(source, idType)
        return MZBridgeAdapter.getIdentifier(source, idType)
      end,
      GetSource = function(citizenid)
        return MZBridgeAdapter.getSourceByCitizenId(citizenid)
      end,
      GetPlayers = function()
        return MZBridgeAdapter.listLoadedSources()
      end,
      GetQBPlayers = function()
        local players = {}
        for _, source in ipairs(MZBridgeAdapter.listLoadedSources()) do
          players[source] = getPlayerWrapper(source)
        end
        return players
      end,
      GetItems = function()
        return MZBridgeAdapter.getSharedItems()
      end
    }
  }
end

exports('GetCoreObject', function()
  return MZBridgeQB.getCoreObject()
end)
