local function canUseInventoryCommand(src)
  if src == 0 then
    return true
  end

  return IsPlayerAceAllowed(src, 'mzcore.inventory.manage')
end

local function reply(message)
  print(('[mz_core] %s'):format(message))
end

local function joinArgs(args, startIndex)
  local out = {}
  for index = startIndex, #args do
    out[#out + 1] = tostring(args[index])
  end
  return table.concat(out, ' ')
end

RegisterCommand('minv_give', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local itemName = args[2]
  local amount = tonumber(args[3]) or 1

  if not targetSource or not itemName then
    return reply('Uso: minv_give [source] [item] [amount]')
  end

  local ok, err = exports['mz_core']:AddPlayerItem(targetSource, itemName, amount, {})
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Item entregue: source=%s item=%s amount=%s'):format(targetSource, itemName, amount))
end, true)

RegisterCommand('minv_give_meta', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissÃ£o.')
  end

  local targetSource = tonumber(args[1])
  local itemName = args[2]
  local amount = tonumber(args[3]) or 1
  local metadataJson = joinArgs(args, 4)

  if not targetSource or not itemName or metadataJson == '' then
    return reply('Uso: minv_give_meta [source] [item] [amount] [json_metadata]')
  end

  local decodeOk, metadata = pcall(json.decode, metadataJson)
  if not decodeOk then
    return reply('Erro: json_metadata invÃ¡lido')
  end

  if type(metadata) ~= 'table' then
    return reply('Erro: json_metadata deve decodificar para objeto/tabela')
  end

  local ok, err = exports['mz_core']:AddPlayerItem(targetSource, itemName, amount, metadata)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Item entregue com metadata: source=%s item=%s amount=%s metadata=%s'):format(
    targetSource,
    itemName,
    amount,
    metadataJson
  ))
end, true)

RegisterCommand('minv_take', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local itemName = args[2]
  local amount = tonumber(args[3]) or 1

  if not targetSource or not itemName then
    return reply('Uso: minv_take [source] [item] [amount]')
  end

  local ok, err = exports['mz_core']:RemovePlayerItem(targetSource, itemName, amount)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Item removido: source=%s item=%s amount=%s'):format(targetSource, itemName, amount))
end, true)

RegisterCommand('minv_has', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local itemName = args[2]
  local amount = tonumber(args[3]) or 1

  if not targetSource or not itemName then
    return reply('Uso: minv_has [source] [item] [amount]')
  end

  local hasItem, total = exports['mz_core']:HasPlayerItem(targetSource, itemName, amount)
  reply(('HasItem source=%s item=%s need=%s -> %s (total=%s)'):format(
    targetSource, itemName, amount, tostring(hasItem), tostring(total or 0)
  ))
end, true)

RegisterCommand('minv_weight', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  if not targetSource then
    return reply('Uso: minv_weight [source]')
  end

  local ok, current, maxWeight = exports['mz_core']:GetPlayerInventoryWeight(targetSource)
  if not ok then
    return reply(('Erro: %s'):format(current or 'unknown'))
  end

  reply(('Peso source=%s -> %s / %s'):format(targetSource, current, maxWeight))
end, true)

RegisterCommand('minv_move', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local fromSlot = tonumber(args[2])
  local toSlot = tonumber(args[3])
  local amount = tonumber(args[4])

  if not targetSource or not fromSlot or not toSlot then
    return reply('Uso: minv_move [source] [fromSlot] [toSlot] [amount opcional]')
  end

  local ok, err = exports['mz_core']:MovePlayerSlot(targetSource, fromSlot, toSlot, amount)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Movido source=%s from=%s to=%s amount=%s'):format(
    targetSource,
    fromSlot,
    toSlot,
    tostring(amount or 'all')
  ))
end, true)

RegisterCommand('minv_show', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  if not targetSource then
    return reply('Uso: minv_show [source]')
  end

  local ok, inventory = exports['mz_core']:GetPlayerInventory(targetSource)
  if not ok then
    return reply(('Erro: %s'):format(inventory or 'unknown'))
  end

  reply(('Inventário do source %s:'):format(targetSource))

  if type(inventory) ~= 'table' or #inventory == 0 then
    return reply('(vazio)')
  end

  table.sort(inventory, function(a, b)
    return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0)
  end)

  for _, row in ipairs(inventory) do
    local metadataText = '{}'
    if type(row.metadata) == 'table' then
      metadataText = json.encode(row.metadata) or '{}'
    end

    reply(('- slot %s | %s x%s | uid=%s | metadata=%s'):format(
      tostring(row.slot),
      tostring(row.item),
      tostring(row.amount),
      tostring(row.instance_uid),
      metadataText
    ))
  end
end, true)

RegisterCommand('minv_use', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local slot = tonumber(args[2])

  if not targetSource or not slot then
    return reply('Uso: minv_use [source] [slot]')
  end

  local ok, result = exports['mz_core']:UsePlayerItem(targetSource, slot)
  if not ok then
    return reply(('Erro: %s'):format(result or 'unknown'))
  end

  reply(('Item usado: source=%s slot=%s'):format(targetSource, slot))
end, true)

RegisterCommand('minv_hotbar_bind', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissÃ£o.')
  end

  local targetSource = tonumber(args[1])
  local hotbarSlot = tonumber(args[2])
  local inventorySlot = tonumber(args[3])

  if not targetSource or not hotbarSlot or not inventorySlot then
    return reply('Uso: minv_hotbar_bind [source] [hotbarSlot] [inventorySlot]')
  end

  local ok, resultOrErr = exports['mz_core']:BindHotbarSlot(targetSource, hotbarSlot, inventorySlot)
  if not ok then
    return reply(('Erro: %s'):format(resultOrErr or 'unknown'))
  end

  reply(('Hotbar vinculada: source=%s hotbar=%s inventory_slot=%s uid=%s item=%s'):format(
    targetSource,
    tostring(resultOrErr.hotbar_slot),
    tostring(resultOrErr.inventory_slot),
    tostring(resultOrErr.instance_uid),
    tostring(resultOrErr.item)
  ))
end, true)

RegisterCommand('minv_hotbar_clear', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissÃ£o.')
  end

  local targetSource = tonumber(args[1])
  local hotbarSlot = tonumber(args[2])

  if not targetSource or not hotbarSlot then
    return reply('Uso: minv_hotbar_clear [source] [hotbarSlot]')
  end

  local ok, resultOrErr = exports['mz_core']:ClearHotbarSlot(targetSource, hotbarSlot)
  if not ok then
    return reply(('Erro: %s'):format(resultOrErr or 'unknown'))
  end

  reply(('Hotbar limpa: source=%s hotbar=%s removed=%s'):format(
    targetSource,
    tostring(resultOrErr.hotbar_slot),
    tostring(resultOrErr.removed)
  ))
end, true)

RegisterCommand('minv_hotbar_show', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissÃ£o.')
  end

  local targetSource = tonumber(args[1])
  if not targetSource then
    return reply('Uso: minv_hotbar_show [source]')
  end

  local ok, resultOrErr = exports['mz_core']:GetPlayerHotbar(targetSource)
  if not ok then
    return reply(('Erro: %s'):format(resultOrErr or 'unknown'))
  end

  reply(('Hotbar do source %s:'):format(targetSource))
  for _, slot in ipairs(type(resultOrErr.slots) == 'table' and resultOrErr.slots or {}) do
    reply(('- hotbar %s | uid=%s | valid=%s | inv_slot=%s | item=%s | label=%s'):format(
      tostring(slot.hotbar_slot),
      tostring(slot.instance_uid or ''),
      tostring(slot.valid == true),
      tostring(slot.inventory_slot or ''),
      tostring(slot.item or ''),
      tostring(slot.label or '')
    ))
  end
end, true)

RegisterCommand('minv_hotbar_use', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissÃ£o.')
  end

  local targetSource = tonumber(args[1])
  local hotbarSlot = tonumber(args[2])

  if not targetSource or not hotbarSlot then
    return reply('Uso: minv_hotbar_use [source] [hotbarSlot]')
  end

  local ok, resultOrErr = exports['mz_core']:UseHotbarSlot(targetSource, hotbarSlot)
  if not ok then
    return reply(('Erro: %s'):format(resultOrErr or 'unknown'))
  end

  reply(('Hotbar usada: source=%s hotbar=%s inv_slot=%s item=%s uid=%s'):format(
    targetSource,
    tostring(resultOrErr.hotbar_slot),
    tostring(resultOrErr.inventory_slot),
    tostring(resultOrErr.item),
    tostring(resultOrErr.instance_uid)
  ))
end, true)

-----

RegisterCommand('minv_stash_show', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  if not targetSource then
    return reply('Uso: minv_stash_show [source]')
  end

  local ok, inventory = exports['mz_core']:GetPersonalStash(targetSource)
  if not ok then
    return reply(('Erro: %s'):format(inventory or 'unknown'))
  end

  reply(('Stash pessoal do source %s:'):format(targetSource))

  if type(inventory) ~= 'table' or #inventory == 0 then
    return reply('(vazio)')
  end

  table.sort(inventory, function(a, b)
    return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0)
  end)

  for _, row in ipairs(inventory) do
    local metadataText = '{}'
    if type(row.metadata) == 'table' then
      metadataText = json.encode(row.metadata) or '{}'
    end

    reply(('- slot %s | %s x%s | uid=%s | metadata=%s'):format(
      tostring(row.slot),
      tostring(row.item),
      tostring(row.amount),
      tostring(row.instance_uid),
      metadataText
    ))
  end
end, true)

RegisterCommand('minv_stash_weight', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  if not targetSource then
    return reply('Uso: minv_stash_weight [source]')
  end

  local ok, current, maxWeight = exports['mz_core']:GetPersonalStashWeight(targetSource)
  if not ok then
    return reply(('Erro: %s'):format(current or 'unknown'))
  end

  reply(('Peso stash source=%s -> %s / %s'):format(targetSource, current, maxWeight))
end, true)

RegisterCommand('minv_stash_put', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local fromMainSlot = tonumber(args[2])
  local toStashSlot = tonumber(args[3])
  local amount = tonumber(args[4])

  if not targetSource or not fromMainSlot or not toStashSlot then
    return reply('Uso: minv_stash_put [source] [fromMainSlot] [toStashSlot] [amount opcional]')
  end

  local ok, err = exports['mz_core']:MovePlayerItemToPersonalStash(targetSource, fromMainSlot, toStashSlot, amount)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Movido MAIN -> STASH source=%s from=%s to=%s amount=%s'):format(
    targetSource,
    fromMainSlot,
    toStashSlot,
    tostring(amount or 'all')
  ))
end, true)

RegisterCommand('minv_stash_take', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local fromStashSlot = tonumber(args[2])
  local toMainSlot = tonumber(args[3])
  local amount = tonumber(args[4])

  if not targetSource or not fromStashSlot or not toMainSlot then
    return reply('Uso: minv_stash_take [source] [fromStashSlot] [toMainSlot] [amount opcional]')
  end

  local ok, err = exports['mz_core']:MovePersonalStashItemToPlayer(targetSource, fromStashSlot, toMainSlot, amount)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Movido STASH -> MAIN source=%s from=%s to=%s amount=%s'):format(
    targetSource,
    fromStashSlot,
    toMainSlot,
    tostring(amount or 'all')
  ))
end, true)

RegisterCommand('minv_orgstash_show', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local orgCode = tostring(args[2] or '')

  if not targetSource or orgCode == '' then
    return reply('Uso: minv_orgstash_show [source] [orgCode]')
  end

  local ok, inventory = exports['mz_core']:GetOrgStash(targetSource, orgCode)
  if not ok then
    return reply(('Erro: %s'):format(inventory or 'unknown'))
  end

  reply(('Stash da org %s para source %s:'):format(orgCode, targetSource))

  if type(inventory) ~= 'table' or #inventory == 0 then
    return reply('(vazio)')
  end

  table.sort(inventory, function(a, b)
    return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0)
  end)

  for _, row in ipairs(inventory) do
    local metadataText = '{}'
    if type(row.metadata) == 'table' then
      metadataText = json.encode(row.metadata) or '{}'
    end

    reply(('- slot %s | %s x%s | uid=%s | metadata=%s'):format(
      tostring(row.slot),
      tostring(row.item),
      tostring(row.amount),
      tostring(row.instance_uid),
      metadataText
    ))
  end
end, true)

RegisterCommand('minv_orgstash_weight', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local orgCode = tostring(args[2] or '')

  if not targetSource or orgCode == '' then
    return reply('Uso: minv_orgstash_weight [source] [orgCode]')
  end

  local ok, current, maxWeight = exports['mz_core']:GetOrgStashWeight(targetSource, orgCode)
  if not ok then
    return reply(('Erro: %s'):format(current or 'unknown'))
  end

  reply(('Peso org stash source=%s org=%s -> %s / %s'):format(targetSource, orgCode, current, maxWeight))
end, true)

RegisterCommand('minv_orgstash_put', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local orgCode = tostring(args[2] or '')
  local fromMainSlot = tonumber(args[3])
  local toStashSlot = tonumber(args[4])
  local amount = tonumber(args[5])

  if not targetSource or orgCode == '' or not fromMainSlot or not toStashSlot then
    return reply('Uso: minv_orgstash_put [source] [orgCode] [fromMainSlot] [toStashSlot] [amount opcional]')
  end

  local ok, err = exports['mz_core']:MovePlayerItemToOrgStash(targetSource, orgCode, fromMainSlot, toStashSlot, amount)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Movido MAIN -> ORG STASH source=%s org=%s from=%s to=%s amount=%s'):format(
    targetSource,
    orgCode,
    fromMainSlot,
    toStashSlot,
    tostring(amount or 'all')
  ))
end, true)

RegisterCommand('minv_orgstash_take', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local orgCode = tostring(args[2] or '')
  local fromStashSlot = tonumber(args[3])
  local toMainSlot = tonumber(args[4])
  local amount = tonumber(args[5])

  if not targetSource or orgCode == '' or not fromStashSlot or not toMainSlot then
    return reply('Uso: minv_orgstash_take [source] [orgCode] [fromStashSlot] [toMainSlot] [amount opcional]')
  end

  local ok, err = exports['mz_core']:MoveOrgStashItemToPlayer(targetSource, orgCode, fromStashSlot, toMainSlot, amount)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Movido ORG STASH -> MAIN source=%s org=%s from=%s to=%s amount=%s'):format(
    targetSource,
    orgCode,
    fromStashSlot,
    toMainSlot,
    tostring(amount or 'all')
  ))
end, true)

RegisterCommand('minv_trunk_show', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local plate = tostring(args[2] or '')

  if not targetSource or plate == '' then
    return reply('Uso: minv_trunk_show [source] [plate]')
  end

  local ok, inventory = exports['mz_core']:GetVehicleTrunk(targetSource, plate)
  if not ok then
    return reply(('Erro: %s'):format(inventory or 'unknown'))
  end

  reply(('Trunk plate=%s source=%s:'):format(plate, targetSource))

  if type(inventory) ~= 'table' or #inventory == 0 then
    return reply('(vazio)')
  end

  table.sort(inventory, function(a, b)
    return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0)
  end)

  for _, row in ipairs(inventory) do
    local metadataText = '{}'
    if type(row.metadata) == 'table' then
      metadataText = json.encode(row.metadata) or '{}'
    end

    reply(('- slot %s | %s x%s | uid=%s | metadata=%s'):format(
      tostring(row.slot),
      tostring(row.item),
      tostring(row.amount),
      tostring(row.instance_uid),
      metadataText
    ))
  end
end, true)

RegisterCommand('minv_trunk_weight', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local plate = tostring(args[2] or '')

  if not targetSource or plate == '' then
    return reply('Uso: minv_trunk_weight [source] [plate]')
  end

  local ok, current, maxWeight = exports['mz_core']:GetVehicleTrunkWeight(targetSource, plate)
  if not ok then
    return reply(('Erro: %s'):format(current or 'unknown'))
  end

  reply(('Peso trunk source=%s plate=%s -> %s / %s'):format(targetSource, plate, current, maxWeight))
end, true)

RegisterCommand('minv_trunk_put', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local plate = tostring(args[2] or '')
  local fromMainSlot = tonumber(args[3])
  local toTrunkSlot = tonumber(args[4])
  local amount = tonumber(args[5])

  if not targetSource or plate == '' or not fromMainSlot or not toTrunkSlot then
    return reply('Uso: minv_trunk_put [source] [plate] [fromMainSlot] [toTrunkSlot] [amount opcional]')
  end

  local ok, err = exports['mz_core']:MovePlayerItemToVehicleTrunk(targetSource, plate, fromMainSlot, toTrunkSlot, amount)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Movido MAIN -> TRUNK source=%s plate=%s from=%s to=%s amount=%s'):format(
    targetSource,
    plate,
    fromMainSlot,
    toTrunkSlot,
    tostring(amount or 'all')
  ))
end, true)

RegisterCommand('minv_trunk_take', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local plate = tostring(args[2] or '')
  local fromTrunkSlot = tonumber(args[3])
  local toMainSlot = tonumber(args[4])
  local amount = tonumber(args[5])

  if not targetSource or plate == '' or not fromTrunkSlot or not toMainSlot then
    return reply('Uso: minv_trunk_take [source] [plate] [fromTrunkSlot] [toMainSlot] [amount opcional]')
  end

  local ok, err = exports['mz_core']:MoveVehicleTrunkItemToPlayer(targetSource, plate, fromTrunkSlot, toMainSlot, amount)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Movido TRUNK -> MAIN source=%s plate=%s from=%s to=%s amount=%s'):format(
    targetSource,
    plate,
    fromTrunkSlot,
    toMainSlot,
    tostring(amount or 'all')
  ))
end, true)

RegisterCommand('minv_glovebox_show', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local plate = tostring(args[2] or '')

  if not targetSource or plate == '' then
    return reply('Uso: minv_glovebox_show [source] [plate]')
  end

  local ok, inventory = exports['mz_core']:GetVehicleGlovebox(targetSource, plate)
  if not ok then
    return reply(('Erro: %s'):format(inventory or 'unknown'))
  end

  reply(('Glovebox plate=%s source=%s:'):format(plate, targetSource))

  if type(inventory) ~= 'table' or #inventory == 0 then
    return reply('(vazio)')
  end

  table.sort(inventory, function(a, b)
    return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0)
  end)

  for _, row in ipairs(inventory) do
    local metadataText = '{}'
    if type(row.metadata) == 'table' then
      metadataText = json.encode(row.metadata) or '{}'
    end

    reply(('- slot %s | %s x%s | uid=%s | metadata=%s'):format(
      tostring(row.slot),
      tostring(row.item),
      tostring(row.amount),
      tostring(row.instance_uid),
      metadataText
    ))
  end
end, true)

RegisterCommand('minv_glovebox_weight', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local plate = tostring(args[2] or '')

  if not targetSource or plate == '' then
    return reply('Uso: minv_glovebox_weight [source] [plate]')
  end

  local ok, current, maxWeight = exports['mz_core']:GetVehicleGloveboxWeight(targetSource, plate)
  if not ok then
    return reply(('Erro: %s'):format(current or 'unknown'))
  end

  reply(('Peso glovebox source=%s plate=%s -> %s / %s'):format(targetSource, plate, current, maxWeight))
end, true)

RegisterCommand('minv_glovebox_put', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local plate = tostring(args[2] or '')
  local fromMainSlot = tonumber(args[3])
  local toGloveboxSlot = tonumber(args[4])
  local amount = tonumber(args[5])

  if not targetSource or plate == '' or not fromMainSlot or not toGloveboxSlot then
    return reply('Uso: minv_glovebox_put [source] [plate] [fromMainSlot] [toGloveboxSlot] [amount opcional]')
  end

  local ok, err = exports['mz_core']:MovePlayerItemToVehicleGlovebox(targetSource, plate, fromMainSlot, toGloveboxSlot, amount)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Movido MAIN -> GLOVEBOX source=%s plate=%s from=%s to=%s amount=%s'):format(
    targetSource,
    plate,
    fromMainSlot,
    toGloveboxSlot,
    tostring(amount or 'all')
  ))
end, true)

RegisterCommand('minv_glovebox_take', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local plate = tostring(args[2] or '')
  local fromGloveboxSlot = tonumber(args[3])
  local toMainSlot = tonumber(args[4])
  local amount = tonumber(args[5])

  if not targetSource or plate == '' or not fromGloveboxSlot or not toMainSlot then
    return reply('Uso: minv_glovebox_take [source] [plate] [fromGloveboxSlot] [toMainSlot] [amount opcional]')
  end

  local ok, err = exports['mz_core']:MoveVehicleGloveboxItemToPlayer(targetSource, plate, fromGloveboxSlot, toMainSlot, amount)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Movido GLOVEBOX -> MAIN source=%s plate=%s from=%s to=%s amount=%s'):format(
    targetSource,
    plate,
    fromGloveboxSlot,
    toMainSlot,
    tostring(amount or 'all')
  ))
end, true)

RegisterCommand('minv_drop_create', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local x = tonumber(args[1])
  local y = tonumber(args[2])
  local z = tonumber(args[3])
  local label = tostring(args[4] or 'Drop')

  if not x or not y or not z then
    return reply('Uso: minv_drop_create [x] [y] [z] [label opcional]')
  end

  local ok, drop = exports['mz_core']:CreateWorldDrop({ x = x, y = y, z = z }, label, {})
  if not ok then
    return reply(('Erro: %s'):format(drop or 'unknown'))
  end

  reply(('Drop criado: uid=%s label=%s coords=(%s, %s, %s)'):format(
    tostring(drop.drop_uid),
    tostring(drop.label),
    tostring(drop.x),
    tostring(drop.y),
    tostring(drop.z)
  ))
end, true)

RegisterCommand('minv_drop_list', function(source)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local ok, drops = exports['mz_core']:ListWorldDrops()
  if not ok then
    return reply(('Erro: %s'):format(drops or 'unknown'))
  end

  reply('World drops:')

  if type(drops) ~= 'table' or #drops == 0 then
    return reply('(vazio)')
  end

  for _, drop in ipairs(drops) do
    reply(('- uid=%s | label=%s | coords=(%s, %s, %s)'):format(
      tostring(drop.drop_uid),
      tostring(drop.label),
      tostring(drop.x),
      tostring(drop.y),
      tostring(drop.z)
    ))
  end
end, true)

RegisterCommand('minv_drop_show', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local dropUid = tostring(args[1] or '')
  if dropUid == '' then
    return reply('Uso: minv_drop_show [dropUid]')
  end

  local ok, inventory, drop = exports['mz_core']:GetWorldDrop(dropUid)
  if not ok then
    return reply(('Erro: %s'):format(inventory or 'unknown'))
  end

  reply(('Drop uid=%s label=%s:'):format(
    tostring(drop.drop_uid),
    tostring(drop.label)
  ))

  if type(inventory) ~= 'table' or #inventory == 0 then
    return reply('(vazio)')
  end

  table.sort(inventory, function(a, b)
    return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0)
  end)

  for _, row in ipairs(inventory) do
    local metadataText = '{}'
    if type(row.metadata) == 'table' then
      metadataText = json.encode(row.metadata) or '{}'
    end

    reply(('- slot %s | %s x%s | uid=%s | metadata=%s'):format(
      tostring(row.slot),
      tostring(row.item),
      tostring(row.amount),
      tostring(row.instance_uid),
      metadataText
    ))
  end
end, true)

RegisterCommand('minv_drop_weight', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local dropUid = tostring(args[1] or '')
  if dropUid == '' then
    return reply('Uso: minv_drop_weight [dropUid]')
  end

  local ok, current, maxWeight, drop = exports['mz_core']:GetWorldDropWeight(dropUid)
  if not ok then
    return reply(('Erro: %s'):format(current or 'unknown'))
  end

  reply(('Peso drop uid=%s label=%s -> %s / %s'):format(
    tostring(drop.drop_uid),
    tostring(drop.label),
    tostring(current),
    tostring(maxWeight)
  ))
end, true)

RegisterCommand('minv_drop_put', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local dropUid = tostring(args[2] or '')
  local fromMainSlot = tonumber(args[3])
  local toDropSlot = tonumber(args[4])
  local amount = tonumber(args[5])

  if not targetSource or dropUid == '' or not fromMainSlot or not toDropSlot then
    return reply('Uso: minv_drop_put [source] [dropUid] [fromMainSlot] [toDropSlot] [amount opcional]')
  end

  local ok, err = exports['mz_core']:MovePlayerItemToWorldDrop(targetSource, dropUid, fromMainSlot, toDropSlot, amount)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Movido MAIN -> DROP source=%s drop=%s from=%s to=%s amount=%s'):format(
    targetSource,
    dropUid,
    fromMainSlot,
    toDropSlot,
    tostring(amount or 'all')
  ))
end, true)

RegisterCommand('minv_drop_take', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local targetSource = tonumber(args[1])
  local dropUid = tostring(args[2] or '')
  local fromDropSlot = tonumber(args[3])
  local toMainSlot = tonumber(args[4])
  local amount = tonumber(args[5])

  if not targetSource or dropUid == '' or not fromDropSlot or not toMainSlot then
    return reply('Uso: minv_drop_take [source] [dropUid] [fromDropSlot] [toMainSlot] [amount opcional]')
  end

  local ok, err = exports['mz_core']:MoveWorldDropItemToPlayer(targetSource, dropUid, fromDropSlot, toMainSlot, amount)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Movido DROP -> MAIN source=%s drop=%s from=%s to=%s amount=%s'):format(
    targetSource,
    dropUid,
    fromDropSlot,
    toMainSlot,
    tostring(amount or 'all')
  ))
end, true)

RegisterCommand('minv_drop_delete', function(source, args)
  if not canUseInventoryCommand(source) then
    return reply('Sem permissão.')
  end

  local dropUid = tostring(args[1] or '')
  if dropUid == '' then
    return reply('Uso: minv_drop_delete [dropUid]')
  end

  local ok, err = exports['mz_core']:DeleteWorldDrop(dropUid)
  if not ok then
    return reply(('Erro: %s'):format(err or 'unknown'))
  end

  reply(('Drop removido: %s'):format(dropUid))
end, true)
