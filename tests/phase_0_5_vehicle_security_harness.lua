local function expect(condition, message)
  if not condition then error(message, 2) end
end

local now = 1000
local eventHandlers = {}
local clientEvents = {}
local logs = {}
local updates = 0
local worldClears = 0
local players = {
  [1] = { citizenid = 'owner_1', state = { loaded = true } },
  [2] = { citizenid = 'other_2', state = { loaded = true } },
  [3] = { citizenid = 'manager_3', state = { loaded = true } },
  [4] = { citizenid = 'inactive_4', state = { loaded = true } }
}
local sessions = {
  [1] = { source = 1, citizenid = 'owner_1', isActive = true },
  [2] = { source = 2, citizenid = 'other_2', isActive = true },
  [3] = { source = 3, citizenid = 'manager_3', isActive = true },
  [4] = { source = 4, citizenid = 'inactive_4', isActive = false }
}
local vehicle = {
  id = 10,
  plate = 'MZ1000',
  owner_type = 'player',
  owner_id = 'owner_1',
  model = 'sultan',
  garage = 'central',
  state = 'stored',
  fuel = 80,
  engine = 900,
  body = 900,
  props_json = {},
  impound_data = {},
  metadata_json = {}
}

function GetGameTimer() return now end
function IsPlayerAceAllowed() return false end
function AddEventHandler(name, handler) eventHandlers[name] = handler end
function RegisterNetEvent(name, handler) eventHandlers[name] = handler end
function TriggerClientEvent(name, target, ok, result)
  clientEvents[#clientEvents + 1] = { name = name, target = target, ok = ok, result = result }
end
function GetInvokingResource() return 'mz_garagem' end
function GetResourceState() return 'missing' end

Config = { VehicleWorld = {} }
MZConstants = { VehicleStates = { STORED = 'stored', OUT = 'out', IMPOUNDED = 'impounded' } }
MZUtils = {
  jsonEncode = function() return '{}' end,
  jsonDecode = function() return {} end
}
MZPlayerService = {
  getPlayer = function(sourceId) return players[tonumber(sourceId)] end,
  getPlayerSession = function(sourceId) return sessions[tonumber(sourceId)] end,
  isPlayerLoaded = function(sourceId)
    local player = players[tonumber(sourceId)]
    return player ~= nil and player.state.loaded == true
  end
}
MZOrgService = {
  hasGlobalPermission = function(sourceId, permission)
    return tonumber(sourceId) == 3 and permission == 'staff.garages.manage'
  end
}
MySQL = {
  single = { await = function() return nil end },
  query = { await = function() return {} end }
}
MZVehicleRepository = {
  getByPlate = function(plate) return plate == vehicle.plate and vehicle or nil end,
  getById = function(id) return id == vehicle.id and vehicle or nil end,
  updateVehicleFlowById = function(id, data)
    expect(id == vehicle.id, 'update targeted another vehicle')
    updates = updates + 1
    for key, value in pairs(data) do vehicle[key] = value end
    return 1
  end
}
MZVehicleWorldService = {
  clearWorldState = function(plate)
    expect(plate == vehicle.plate, 'world clear targeted another vehicle')
    worldClears = worldClears + 1
    return true
  end
}
MZLogService = {
  createDetailed = function(scope, action, payload)
    logs[#logs + 1] = { scope = scope, action = action, payload = payload }
    return #logs
  end
}

dofile('server/vehicles/service.lua')

local ok, err = MZVehicleService.impoundVehicle(vehicle.plate, 'test', 1, {})
expect(ok == false and err == 'not_authorized', 'owner could impound without management permission')
expect(updates == 0, 'denied impound mutated persistence')

now = now + 2000
ok, err = MZVehicleService.impoundVehicle(vehicle.plate, 'test', 4, {})
expect(ok == false and err == 'invalid_session', 'inactive session could impound')

now = now + 2000
ok, err = MZVehicleService.impoundVehicle(vehicle.plate, 'test', 3, { injected = true })
expect(ok == false and err == 'invalid_impound_data', 'unknown impound metadata was accepted')

now = now + 2000
ok, err = MZVehicleService.impoundVehicle(vehicle.plate, 'policy_violation', 3, {
  fee = 250,
  reference = 'case-1'
})
expect(ok == true, ('authorized impound failed: %s'):format(tostring(err)))
expect(vehicle.state == 'impounded' and updates == 1, 'authorized impound did not persist canonical state')
expect(vehicle.impound_data.by.id == 'manager_3', 'impound actor was not resolved from server session')
expect(worldClears == 1, 'impound did not clear the world state')

now = now + 2000
ok, err = MZVehicleService.impoundVehicle(vehicle.plate, 'duplicate', 3, {})
expect(ok == false and err == 'vehicle_already_impounded', 'duplicate impound was not rejected')
expect(updates == 1, 'duplicate impound mutated persistence')

now = now + 2000
ok, err = MZVehicleService.releaseImpound(vehicle.plate, 'central', 2)
expect(ok == false and err == 'vehicle_access_denied', 'non-owner could release impound')

now = now + 2000
ok, err = MZVehicleService.releaseImpound(vehicle.plate, 'central', 1)
expect(ok == true, ('legitimate owner release failed: %s'):format(tostring(err)))
expect(vehicle.state == 'stored' and updates == 2, 'legitimate release did not persist stored state')

now = now + 2000
ok, err = MZVehicleService.releaseImpound(vehicle.plate, 'central', 1)
expect(ok == false and err == 'vehicle_not_impounded', 'duplicate release was not rejected')
expect(updates == 2, 'duplicate release mutated persistence')

local serviceImpound = MZVehicleService.impoundVehicle
local serviceRelease = MZVehicleService.releaseImpound
local impoundCalls, releaseCalls = 0, 0
MZVehicleService.impoundVehicle = function(...) impoundCalls = impoundCalls + 1; return serviceImpound(...) end
MZVehicleService.releaseImpound = function(...) releaseCalls = releaseCalls + 1; return serviceRelease(...) end
dofile('server/vehicles/events.lua')

source = 1
eventHandlers['mz_core:server:vehicle:impound']({ plate = vehicle.plate, owner = 'forged' })
eventHandlers['mz_core:server:vehicle:releaseImpound'](vehicle.plate, 'central')
expect(impoundCalls == 0 and releaseCalls == 0, 'public NetEvents reached privileged mutations')
expect(#clientEvents >= 2 and clientEvents[#clientEvents].ok == false, 'rejected NetEvent did not return denial')
expect(#logs >= 7, 'security decisions were not audited')

local exportsSource = assert(io.open('server/vehicles/exports.lua', 'rb')):read('*a')
expect(exportsSource:find('console_actor_forbidden', 1, true), 'external resources can still impersonate console')
local ownedConsumer = assert(io.open('../mz_garagem/server/services/owned.lua', 'rb')):read('*a')
local orgConsumer = assert(io.open('../mz_garagem/server/services/org.lua', 'rb')):read('*a')
expect(ownedConsumer:find("ReleaseImpoundVehicle(plate, access.garage.id, source)", 1, true),
  'owned garage no longer uses canonical release export')
expect(orgConsumer:find("ReleaseImpoundVehicle(plate, access.garage.id, source)", 1, true),
  'org garage no longer uses canonical release export')

print('[phase_0_5_vehicle_security_harness] PASS auth=4 invalid=2 duplicate=2 events=2 consumers=2')
