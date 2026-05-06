lib.callback.register('mz_core:server:inventory:openPlayer', function(source)
  return MZInventoryService.openPlayerInventory(source)
end)

lib.callback.register('mz_core:server:inventory:openContainer', function(source, descriptor)
  return MZInventoryService.openInventoryContainer(source, descriptor)
end)

lib.callback.register('mz_core:server:inventory:snapshot', function(source, descriptor)
  return MZInventoryService.getInventorySnapshot(source, descriptor)
end)

lib.callback.register('mz_core:server:inventory:view', function(source, request)
  return MZInventoryService.getInventoryViewSnapshot(source, request)
end)

lib.callback.register('mz_core:server:inventory:move', function(source, request)
  return MZInventoryService.moveInventoryItem(source, request)
end)

lib.callback.register('mz_core:server:inventory:split', function(source, request)
  return MZInventoryService.splitInventoryStack(source, request)
end)

lib.callback.register('mz_core:server:inventory:merge', function(source, request)
  return MZInventoryService.mergeInventorySlots(source, request)
end)

lib.callback.register('mz_core:server:inventory:swap', function(source, request)
  return MZInventoryService.swapInventorySlots(source, request)
end)

lib.callback.register('mz_core:server:inventory:use', function(source, request)
  return MZInventoryService.useInventoryItemAction(source, request)
end)

lib.callback.register('mz_core:server:inventory:drop', function(source, request)
  return MZInventoryService.dropInventoryItemAction(source, request)
end)

lib.callback.register('mz_core:server:inventory:errors', function()
  return MZInventoryService.getPublicInventoryErrorCatalog()
end)

local function buildHotbarCallbackResponse(ok, resultOrErr)
  if ok then
    return {
      ok = true,
      data = resultOrErr or {}
    }
  end

  return {
    ok = false,
    error = {
      code = tostring(resultOrErr or 'unknown_error'),
      message = tostring(resultOrErr or 'unknown_error'),
      internal_code = tostring(resultOrErr or 'unknown_error')
    }
  }
end

lib.callback.register('mz_core:server:inventory:getHotbar', function(source)
  return buildHotbarCallbackResponse(MZInventoryService.getPlayerHotbar(source))
end)

lib.callback.register('mz_core:server:inventory:bindHotbarSlot', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  return buildHotbarCallbackResponse(MZInventoryService.bindHotbarSlot(
    source,
    payload.hotbar_slot or payload.hotbarSlot,
    payload.inventory_slot or payload.inventorySlot or payload.slot
  ))
end)

lib.callback.register('mz_core:server:inventory:clearHotbarSlot', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  return buildHotbarCallbackResponse(MZInventoryService.clearHotbarSlot(
    source,
    payload.hotbar_slot or payload.hotbarSlot
  ))
end)

lib.callback.register('mz_core:server:inventory:useHotbarSlot', function(source, payload)
  payload = type(payload) == 'table' and payload or {}
  return buildHotbarCallbackResponse(MZInventoryService.useHotbarSlot(
    source,
    payload.hotbar_slot or payload.hotbarSlot
  ))
end)

RegisterNetEvent('mz_core:server:inventory:updateWeaponAmmo', function(payload)
  MZInventoryService.updateEquippedWeaponAmmo(source, payload)
end)

RegisterNetEvent('mz_core:server:inventory:unauthorizedWeaponDetected', function(payload)
  MZInventoryService.logUnauthorizedWeapon(source, payload)
end)

RegisterNetEvent('mz_core:server:inventory:useHotbarSlot', function(payload)
  payload = type(payload) == 'table' and payload or {}
  MZInventoryService.useHotbarSlot(source, payload.hotbar_slot or payload.hotbarSlot)
end)
