local function expect(condition, message)
  if not condition then error(message, 2) end
end

local function read(path)
  local file = assert(io.open(path, 'rb'))
  local content = file:read('*a')
  file:close()
  return content
end

local manifest = read('fxmanifest.lua')
local serverStateService = assert(manifest:find("'server/player/state_service.lua'", 1, true))
local serverHud = assert(manifest:find("'server/player/hud.lua'", 1, true))
local serverSync = assert(manifest:find("'server/player/state_sync.lua'", 1, true))
local serverEvents = assert(manifest:find("'server/player/events.lua'", 1, true))
expect(serverStateService < serverHud and serverHud < serverSync and serverSync < serverEvents,
  'server script order does not load canonical sync before player events')
local clientPlayer = assert(manifest:find("'client/player.lua'", 1, true))
local clientState = assert(manifest:find("'client/player_state.lua'", 1, true))
local clientHud = assert(manifest:find("'client/hud.lua'", 1, true))
local clientSpawn = assert(manifest:find("'client/spawn.lua'", 1, true))
expect(clientPlayer < clientState and clientState < clientHud and clientHud < clientSpawn,
  'client state mirror is not loaded before HUD/spawn')
local clientStateSource = read('client/player_state.lua')
expect(not clientStateSource:find('LocalPlayer.state', 1, true)
  and not clientStateSource:find(':set(', 1, true), 'client state module writes a sensitive state bag')

local spawn = read('client/spawn.lua')
expect(not spawn:find('SetPlayerModel%s*%('), 'core spawn still performs redundant model replacement')
expect(not spawn:find('NetworkResurrectLocalPlayer%s*%('), 'core spawn still performs parallel resurrection')
expect(not spawn:find("TriggerEvent('playerSpawned'", 1, true), 'core spawn still duplicates spawnmanager playerSpawned')
expect(spawn:find("mz_core:client:pedModelReady", 1, true), 'core spawn does not signal final ped readiness')

local creator = read('../mz_creator/client/appearance.lua')
expect(creator:find("mz_core:client:pedModelReady", 1, true), 'creator model replacement does not signal core')
expect(not creator:find('SetEntityHealth', 1, true) and not creator:find('SetPedArmour', 1, true),
  'creator applies player-state vitals directly')

local adminClient = read('../mz_admin/client/commands.lua')
expect(not adminClient:find("mz_admin:client:heal", 1, true)
  and not adminClient:find("mz_admin:client:revive", 1, true), 'parallel admin physical events still exist')
expect(not adminClient:find('SetEntityHealth', 1, true)
  and not adminClient:find('SetPedArmour', 1, true)
  and not adminClient:find('NetworkResurrectLocalPlayer', 1, true), 'admin client still owns physical vitals')
expect(adminClient:find("mz_admin:server:setArmor", 1, true), 'admin armor was not migrated server-side')

local syncServer = read('server/player/state_sync.lua')
expect(syncServer:find("local SYNC_EVENT = 'mz_core:client:playerStateSync'", 1, true),
  'canonical server-to-client event is missing')
expect(not syncServer:find("RegisterNetEvent(SYNC_EVENT", 1, true),
  'server registered a client-only sync event handler')
expect(syncServer:find("sourceId = source", 1, true) and not syncServer:find('payload.target', 1, true),
  'candidate observation does not keep target implicit')

local hud = read('server/player/hud.lua')
expect(hud:find("mz_core:client:hudStateUpdated", 1, true), 'legacy HUD adapter was removed early')
local hudClient = read('../mz_hud/client/main.lua')
expect(hudClient:find("getPlayerMetadataValue('health'", 1, true)
  and hudClient:find("getPlayerMetadataValue('armor'", 1, true), 'HUD does not prefer canonical vitals')
local inventory = read('../mz_inventory/client/main.lua')
expect(inventory:find('CanLocalPlayerPerformAction', 1, true), 'inventory key path ignores local state block')
local phoneClient = read('../mz_phone/client/phone.lua')
local phoneServer = read('../mz_phone/server/callbacks.lua')
expect(phoneClient:find('CanLocalPlayerPerformAction', 1, true), 'phone open path ignores local state block')
expect(phoneServer:find('CanPlayerPerformAction', 1, true), 'phone server path ignores canonical action guard')

print('player_state_integration_contract_harness: ok')
