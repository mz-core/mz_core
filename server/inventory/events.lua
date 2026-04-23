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

lib.callback.register('mz_core:server:inventory:errors', function()
  return MZInventoryService.getPublicInventoryErrorCatalog()
end)
