local function read(path)
  local file = assert(io.open(path, 'rb'))
  local content = file:read('*a')
  file:close()
  return content
end

local function expect(condition, message)
  if not condition then error('[player_state_consumer_hardening_harness] ' .. message, 2) end
end

local inventory = read('mz_core/server/inventory/service.lua')
local phone = read('mz_phone/server/callbacks.lua')
local garage = read('mz_garagem/server/callbacks.lua')
local houses = read('mz_houses/server/main.lua')
local housesClient = read('mz_houses/client/main.lua')
local housesInteractions = read('mz_houses/client/interactions.lua')
local progress = read('mz_progress/client/main.lua')
local animations = read('mz_animations/client/main.lua')
local playerState = read('mz_core/client/player_state.lua')
local vehicles = read('mz_vehicles/server/access.lua')
local vehiclesClient = read('mz_vehicles/client/main.lua')
local vehiclesManifest = read('mz_vehicles/fxmanifest.lua')
local targetClient = read('mz_target/client/main.lua')
local clothing = read('mz_clothing/server/main.lua')
local tattoo = read('mz_tatto/server/service.lua')

for _, action in ipairs({ 'inventory.open', 'inventory.move', 'inventory.drop', 'inventory.pickup', 'storage.use' }) do
  expect(inventory:find("playerActionAllowed(source, '" .. action .. "')", 1, true), 'inventario sem guard ' .. action)
end
expect(inventory:find("canPerformAction(source, 'inventory.use')", 1, true), 'inventario sem guard inventory.use')
expect(phone:find('STATE_GUARD_BYPASS', 1, true) and phone:find('phoneActionAllowed(source)', 1, true),
  'telefone nao possui guard central com bypass de cleanup')
expect(garage:find("CanPlayerPerformAction(source, 'garage.use')", 1, true), 'garagem sem guard')
expect(houses:find("lib.callback.register('mz_houses:server:setDoorState'", 1, true)
  and houses:find("if not propertyActionAllowed(source) then return { ok = false, error = 'player_state_blocked' } end", 1, true),
  'mutacao normal da porta sem guard server-side')
expect(housesClient:find("CanLocalPlayerPerformAction('property.use')", 1, true)
  and housesClient:find("if not MZHouses.CanPerformPropertyAction() then", 1, true)
  and housesClient:find("return false, 'player_state_blocked'", 1, true),
  'porta da propriedade sem guard local fail-closed')
expect(housesInteractions:find("not MZHouses.CanPerformPropertyAction()", 1, true),
  'interacao exibe acao de porta para player bloqueado')
expect(progress:find("cancelProgress('player_state_blocked')", 1, true), 'progresso nao cancela ao bloquear')
expect(animations:find("Stop('player_state_blocked'", 1, true), 'emote nao cancela ao bloquear')
expect(playerState:find('GetPedInVehicleSeat(vehicle, -1) == ped', 1, true), 'motorista bloqueado nao sai do veiculo')
expect(vehicles:find("CanPlayerPerformAction(source, action or 'vehicle.enter')", 1, true), 'acesso veicular sem guard')
expect(vehiclesClient:find("CanLocalPlayerPerformAction(action or 'vehicle.enter')", 1, true)
  and vehiclesClient:find("return false, 'player_state_blocked'", 1, true),
  'entrada fisica no porta-malas sem guard local')
expect(vehiclesClient:find("elseif not localVehicleActionAllowed('vehicle.enter') then", 1, true)
  and vehiclesClient:find('MZVehiclesClient.exitVehicleTrunk()', 1, true),
  'player bloqueado dentro do porta-malas nao recebe cleanup')
expect(targetClient:find("CanLocalPlayerPerformAction('vehicle.enter')", 1, true)
  and targetClient:find("not isMzVehiclesStarted() or not localVehicleActionAllowed()", 1, true),
  'target permite acionar entrada bloqueada no porta-malas')
expect(vehiclesManifest:find("'mz_core'", 1, true), 'mz_vehicles usa guard do core sem declarar dependencia')
expect(clothing:find("CanPlayerPerformAction(source, 'shop.use')", 1, true), 'loja de roupa sem guard')
expect(tattoo:find("CanPlayerPerformAction(source, 'shop.use')", 1, true), 'loja de tatuagem sem guard')

print('[player_state_consumer_hardening_harness] PASS inventory=6 phone=1 domains=8')
