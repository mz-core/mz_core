local function expect(condition, message)
  if not condition then error(message, 2) end
end

local handlers = {}
local calls = {}
local logs = {}

function AddEventHandler(name, handler) handlers[name] = handler end
function RegisterNetEvent() end
function GetCurrentResourceName() return 'mz_core' end
function GetPlayers() return {} end
function GetPlayerName() return nil end
function GetGameTimer() return 0 end
function Wait() end
function CreateThread() end
function TriggerClientEvent() end

MZCache = { playersBySource = { [8] = {}, [3] = {} } }
MZPlayerStateService = {
  beginShutdown = function() calls[#calls + 1] = 'shutdown' end,
  beginUnload = function(source, reason)
    calls[#calls + 1] = ('state:%s:%s'):format(source, reason)
    return source ~= 8, source == 8 and { code = 'persistence_failed' } or { code = 'flushed' }
  end,
  clearRuntime = function() calls[#calls + 1] = 'clear' end
}
MZInventoryService = {
  handlePlayerDropped = function(source, reason)
    calls[#calls + 1] = ('inventory:%s:%s'):format(source, reason)
  end
}
MZPlayerService = {
  unloadPlayer = function(source, reason, prepared, flushOk)
    calls[#calls + 1] = ('player:%s:%s:%s:%s'):format(source, reason, tostring(prepared), tostring(flushOk))
  end
}
MZLogService = {
  createDetailed = function(scope, action, payload)
    logs[#logs + 1] = { scope = scope, action = action, payload = payload }
    return true
  end
}
MZOrgService = {}
MZCoreState = { ready = true }
Config = { VehicleWorld = {} }

dofile('server/player/events.lua')

expect(type(handlers.playerDropped) == 'function', 'handler playerDropped ausente')
expect(type(handlers.onResourceStop) == 'function', 'handler onResourceStop ausente')

source = 3
handlers.playerDropped('network_lost')
expect(calls[1] == 'state:3:network_lost', 'drop nao marcou unloading primeiro')
expect(calls[2] == 'inventory:3:network_lost', 'drop nao limpou inventario depois do estado')
expect(calls[3] == 'player:3:network_lost:true:true', 'drop nao continuou unload com flush preparado')

calls = {}
handlers.onResourceStop('other_resource')
expect(#calls == 0, 'stop de outro resource alterou runtime')

handlers.onResourceStop('mz_core')
expect(calls[1] == 'shutdown', 'resource stop nao interrompeu novas operacoes primeiro')
expect(calls[2] == 'state:3:resource_stop' and calls[5] == 'state:8:resource_stop', 'resource stop nao percorreu sources ordenados')
expect(calls[#calls] == 'clear', 'resource stop nao limpou runtime ao final')
expect(#logs == 1 and logs[1].action == 'resource_stop_flush', 'resultado agregado do stop nao foi logado')
expect(logs[1].payload.after.total == 2 and logs[1].payload.after.succeeded == 1 and logs[1].payload.after.failed == 1,
  'agregado de flush do stop incorreto')

print('player_state_lifecycle_harness: ok')
