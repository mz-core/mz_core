exports('GetPlayerInventory', function(source)
  return MZInventoryService.getPlayerInventory(source)
end)

exports('GetPlayerInventoryWeight', function(source)
  return MZInventoryService.getPlayerWeight(source)
end)

exports('GetPersonalStash', function(source)
  return MZInventoryService.getPersonalStash(source)
end)

exports('GetPersonalStashWeight', function(source)
  return MZInventoryService.getPersonalStashWeight(source)
end)

exports('MovePlayerItemToPersonalStash', function(source, fromSlot, toSlot, amount)
  return MZInventoryService.movePlayerToPersonalStash(source, fromSlot, toSlot, amount)
end)

exports('MovePersonalStashItemToPlayer', function(source, fromSlot, toSlot, amount)
  return MZInventoryService.movePersonalStashToPlayer(source, fromSlot, toSlot, amount)
end)

exports('GetOrgStash', function(source, orgCode)
  return MZInventoryService.getOrgStash(source, orgCode)
end)

exports('GetOrgStashWeight', function(source, orgCode)
  return MZInventoryService.getOrgStashWeight(source, orgCode)
end)

exports('MovePlayerItemToOrgStash', function(source, orgCode, fromSlot, toSlot, amount)
  return MZInventoryService.movePlayerToOrgStash(source, orgCode, fromSlot, toSlot, amount)
end)

exports('MoveOrgStashItemToPlayer', function(source, orgCode, fromSlot, toSlot, amount)
  return MZInventoryService.moveOrgStashToPlayer(source, orgCode, fromSlot, toSlot, amount)
end)

exports('GetVehicleTrunk', function(source, plate)
  return MZInventoryService.getVehicleTrunk(source, plate)
end)

exports('GetVehicleTrunkWeight', function(source, plate)
  return MZInventoryService.getVehicleTrunkWeight(source, plate)
end)

exports('MovePlayerItemToVehicleTrunk', function(source, plate, fromSlot, toSlot, amount)
  return MZInventoryService.movePlayerToVehicleTrunk(source, plate, fromSlot, toSlot, amount)
end)

exports('MoveVehicleTrunkItemToPlayer', function(source, plate, fromSlot, toSlot, amount)
  return MZInventoryService.moveVehicleTrunkToPlayer(source, plate, fromSlot, toSlot, amount)
end)

exports('GetVehicleGlovebox', function(source, plate)
  return MZInventoryService.getVehicleGlovebox(source, plate)
end)

exports('GetVehicleGloveboxWeight', function(source, plate)
  return MZInventoryService.getVehicleGloveboxWeight(source, plate)
end)

exports('MovePlayerItemToVehicleGlovebox', function(source, plate, fromSlot, toSlot, amount)
  return MZInventoryService.movePlayerToVehicleGlovebox(source, plate, fromSlot, toSlot, amount)
end)

exports('MoveVehicleGloveboxItemToPlayer', function(source, plate, fromSlot, toSlot, amount)
  return MZInventoryService.moveVehicleGloveboxToPlayer(source, plate, fromSlot, toSlot, amount)
end)

exports('CreateWorldDrop', function(coords, label, metadata)
  return MZInventoryService.createWorldDrop(coords, label, metadata)
end)

exports('DeleteWorldDrop', function(dropUid)
  return MZInventoryService.deleteWorldDrop(dropUid)
end)

exports('GetWorldDrop', function(dropUid)
  return MZInventoryService.getWorldDrop(dropUid)
end)

exports('GetWorldDropWeight', function(dropUid)
  return MZInventoryService.getWorldDropWeight(dropUid)
end)

exports('MovePlayerItemToWorldDrop', function(source, dropUid, fromSlot, toSlot, amount)
  return MZInventoryService.movePlayerToWorldDrop(source, dropUid, fromSlot, toSlot, amount)
end)

exports('MoveWorldDropItemToPlayer', function(source, dropUid, fromSlot, toSlot, amount)
  return MZInventoryService.moveWorldDropToPlayer(source, dropUid, fromSlot, toSlot, amount)
end)

exports('ListWorldDrops', function()
  return MZInventoryService.listWorldDrops()
end)

exports('GetItemDefinition', function(itemName)
  return MZInventoryService.getItemDefinition(itemName)
end)

exports('HasPlayerItem', function(source, itemName, amount)
  return MZInventoryService.hasPlayerItem(source, itemName, amount)
end)

exports('AddPlayerItem', function(source, itemName, amount, metadata)
  return MZInventoryService.addPlayerItem(source, itemName, amount, metadata)
end)

exports('RemovePlayerItem', function(source, itemName, amount)
  return MZInventoryService.removePlayerItem(source, itemName, amount)
end)

exports('SetPlayerSlot', function(source, slot, item, amount, metadata)
  return MZInventoryService.setPlayerSlot(source, slot, item, amount, metadata)
end)

exports('ClearPlayerSlot', function(source, slot)
  return MZInventoryService.clearPlayerSlot(source, slot)
end)

exports('MovePlayerSlot', function(source, fromSlot, toSlot, amount)
  return MZInventoryService.movePlayerSlot(source, fromSlot, toSlot, amount)
end)

exports('SetPlayerSlotMetadata', function(source, slot, metadata, mode)
  return MZInventoryService.setPlayerSlotMetadata(source, slot, metadata, mode)
end)

exports('RegisterItemUseHandler', function(itemName, handler)
  return MZInventoryService.registerItemUseHandler(itemName, handler)
end)

exports('UsePlayerItem', function(source, slot)
  return MZInventoryService.usePlayerItem(source, slot)
end)