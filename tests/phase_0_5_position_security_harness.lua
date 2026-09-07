local function expect(condition, message)
  if not condition then error(message, 2) end
end

local serviceFile = assert(io.open('server/player/service.lua', 'r'))
local serviceSource = serviceFile:read('*a')
serviceFile:close()
expect(serviceSource:find('return value == true or tonumber(value) == 1', 1, true),
  'normalizacao de boolean do banco nao aceita true, 1 e "1"')
expect(serviceSource:find('databaseBoolean(sessionRow.is_active)', 1, true),
  'sessao nao normaliza is_active numerico/string/boolean do banco')

local now = 1000
local events = {}
local saved = {}
local logs = {}
local pedAvailable = true
local observed = { x = 100.0, y = 200.0, z = 30.0 }
local heading = 725.0
local players = {
  [1] = { citizenid = 'player_1', state = { loaded = true } },
  [2] = { citizenid = 'player_2', state = { loaded = true } },
  [3] = { citizenid = 'player_3', state = { loaded = true } }
}
local sessions = {
  [1] = { source = 1, citizenid = 'player_1', isActive = true },
  [2] = { source = 2, citizenid = 'player_2', isActive = false },
  [3] = { source = 3, citizenid = 'player_3', isActive = true }
}

function RegisterNetEvent(name, handler) events[name] = handler end
function AddEventHandler(name, handler) events[name] = handler end
function CreateThread() end
function Wait() end
function GetGameTimer() return now end
function GetPlayerPed(sourceId) return pedAvailable and (100 + sourceId) or 0 end
function DoesEntityExist(entity) return pedAvailable and entity ~= 0 end
function GetEntityCoords() return observed end
function GetEntityHeading() return heading end
function GetPlayerName(sourceId) return players[tonumber(sourceId)] and ('Player%s'):format(sourceId) or nil end
function GetPlayers() return {} end
function GetCurrentResourceName() return 'mz_core' end
function TriggerClientEvent() end

MZCoreState = { ready = true }
MZCache = { playersBySource = {} }
Config = { VehicleWorld = {} }
MZPlayerService = {
  isPlayerLoaded = function(sourceId)
    local player = players[tonumber(sourceId)]
    return player ~= nil and player.state.loaded == true
  end,
  getPlayer = function(sourceId) return players[tonumber(sourceId)] end,
  getPlayerSession = function(sourceId) return sessions[tonumber(sourceId)] end,
  savePosition = function(sourceId, coords)
    saved[#saved + 1] = { source = sourceId, coords = coords }
    return true
  end,
  unloadPlayer = function() return true end
}
MZPlayerStateService = {
  beginUnload = function() return true, {} end,
  finalizeUnload = function() end,
  clearRuntime = function() end
}
MZOrgService = { loadPlayerOrgs = function() end }
MZLogService = {
  createDetailed = function(scope, action, payload)
    logs[#logs + 1] = { scope = scope, action = action, payload = payload }
    return #logs
  end
}

dofile('server/player/events.lua')

source = 1
events['mz_core:server:savePosition']({ x = 101.0, y = 201.0, z = 30.5, heading = 5.0 })
expect(#saved == 1, 'legitimate periodic position was not saved')
expect(saved[1].coords.x == 100.0 and saved[1].coords.y == 200.0 and saved[1].coords.z == 30.0,
  'client coordinates, not server coordinates, were persisted')
expect(saved[1].coords.heading == 5.0, 'server heading was not normalized')

events['mz_core:server:savePosition']({ x = 100.0, y = 200.0, z = 30.0 })
expect(#saved == 1, 'duplicate request bypassed the rate limit')

now = now + 11000
events['mz_core:server:savePosition']({ x = 100.0, y = 200.0, z = 30.0, owner = 'forged' })
expect(#saved == 1, 'payload with unknown fields was persisted')

now = now + 11000
events['mz_core:server:savePosition']({ x = 9000.0, y = 9000.0, z = 900.0 })
expect(#saved == 1, 'client/server position mismatch was persisted')

now = now + 11000
source = 2
events['mz_core:server:savePosition']({ x = 100.0, y = 200.0, z = 30.0 })
expect(#saved == 1, 'inactive session persisted position')

now = now + 11000
source = 3
pedAvailable = false
events['mz_core:server:savePosition']({ x = 100.0, y = 200.0, z = 30.0 })
expect(#saved == 1, 'missing server entity fell back to client coordinates')

source = 1
pedAvailable = true
observed = { x = 120.0, y = 220.0, z = 35.0 }
heading = 180.0
events.playerDropped('quit')
expect(#saved == 2 and saved[2].coords.x == 120.0, 'disconnect did not flush server-observed position')
expect(#logs >= 4, 'position rejections were not audited')

print('[phase_0_5_position_security_harness] PASS canonical=2 rate=1 invalid=3 disconnect=1')
