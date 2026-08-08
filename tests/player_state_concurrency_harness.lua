local function expect(condition, message)
  if not condition then error(message, 2) end
end

MZ_PLAYER_STATE_TESTING = true

dofile('config.lua')
Config.PlayerStates.persistence.lockTimeoutMs = 20

local clock = 0
local players = {}
local yieldOnWrite = false
local failWithError = false

function GetGameTimer() return clock end
function GetCurrentResourceName() return 'mz_core' end
function Wait()
  clock = clock + 1
  local _, isMain = coroutine.running()
  if not isMain then coroutine.yield('wait') end
end

MZPlayerService = { getPlayer = function(source) return players[tonumber(source)] end }
MZPlayerRepository = {
  updateMetadata = function()
    if failWithError then error('database unavailable') end
    if yieldOnWrite then
      yieldOnWrite = false
      coroutine.yield('db_wait')
    end
    return true
  end
}

dofile('server/player/state_normalizer.lua')
dofile('server/player/state_service.lua')

local internal = MZPlayerStateService.internalContext('concurrency_harness')

local function fresh(source)
  players[source] = {
    source = source,
    citizenid = ('CONC%s'):format(source),
    session = { id = source },
    state = { loaded = true },
    metadata = {
      hunger = 100, thirst = 100, stress = 0, health = 200, armor = 0,
      deathState = 'alive', isdead = false, inlaststand = false
    }
  }
  expect(MZPlayerStateService.initializePlayer(source) == true, 'runtime nao inicializou')
end

local function resumeExpect(co, expectedYield)
  local ok, value = coroutine.resume(co)
  expect(ok, value)
  if expectedYield then expect(value == expectedYield, ('yield esperado %s, recebido %s'):format(expectedYield, tostring(value))) end
  return value
end

-- Flush e mutacao concorrentes: a mutacao espera o mesmo lock e nao se perde.
fresh(1)
MZPlayerStateService.setStatus(1, 'hunger', 80, internal)
yieldOnWrite = true
local flushResult, mutationResult
local flushCo = coroutine.create(function()
  flushResult = table.pack(MZPlayerStateService.flush(1, 'concurrent_flush', true, internal))
end)
local mutationCo = coroutine.create(function()
  mutationResult = table.pack(MZPlayerStateService.addStatus(1, 'hunger', 5, internal))
end)
resumeExpect(flushCo, 'db_wait')
resumeExpect(mutationCo, 'wait')
resumeExpect(flushCo)
resumeExpect(mutationCo)
expect(flushResult[1] == true and mutationResult[1] == true, 'operacoes concorrentes falharam')
expect(players[1].metadata.hunger == 85, 'atualizacao concorrente foi perdida')
expect(MZPlayerStateService._test.getRuntime(1).revision == 2, 'revision concorrente final incorreta')

-- Status e morte simultaneos sao serializados; ambos permanecem no cache.
fresh(2)
yieldOnWrite = true
local deathResult, statusResult
local deathCo = coroutine.create(function()
  deathResult = table.pack(MZPlayerStateService.markDead(2, internal))
end)
local statusCo = coroutine.create(function()
  statusResult = table.pack(MZPlayerStateService.removeStatus(2, 'thirst', 10, internal))
end)
resumeExpect(deathCo, 'db_wait')
resumeExpect(statusCo, 'wait')
resumeExpect(deathCo)
resumeExpect(statusCo)
expect(deathResult[1] and statusResult[1], 'status/morte simultaneos falharam')
expect(players[2].metadata.deathState == 'dead' and players[2].metadata.thirst == 90, 'status/morte perderam atualizacao')
expect(MZPlayerStateService._test.getRuntime(2).revision == 2, 'revision de status/morte incorreta')

-- Unload marca o runtime antes de esperar o lock e recusa novas mutacoes.
fresh(3)
yieldOnWrite = true
local transitionCo = coroutine.create(function()
  MZPlayerStateService.markDowned(3, internal)
end)
local unloadResult
local unloadCo = coroutine.create(function()
  unloadResult = table.pack(MZPlayerStateService.beginUnload(3, 'concurrent_unload'))
end)
resumeExpect(transitionCo, 'db_wait')
resumeExpect(unloadCo, 'wait')
local mutateOk, mutateErr = MZPlayerStateService.setStatus(3, 'stress', 10, internal)
expect(not mutateOk and mutateErr.code == 'unloading', 'mutacao entrou durante unload')
resumeExpect(transitionCo)
resumeExpect(unloadCo)
expect(unloadResult[1] == true, 'flush de unload concorrente falhou')
MZPlayerStateService.finalizeUnload(3)

-- Erro de repository mantem dirty e o lock e liberado para retry/mutacao.
fresh(4)
MZPlayerStateService.setStatus(4, 'armor', 50, internal)
failWithError = true
local flushOk, flushErr = MZPlayerStateService.flush(4, 'forced_error', true, internal)
expect(not flushOk and flushErr.code == 'persistence_failed', 'erro de persistencia foi ocultado')
failWithError = false
local afterErrorOk = MZPlayerStateService.addStatus(4, 'armor', 10, internal)
expect(afterErrorOk == true and players[4].metadata.armor == 60, 'lock nao foi liberado depois do erro')

-- Lock ocupado expira sem alterar metadata/revision.
fresh(5)
local runtime5 = MZPlayerStateService._test.getRuntime(5)
MZPlayerStateService._test.setLock(5, {})
local timeoutOk, timeoutErr = MZPlayerStateService.setStatus(5, 'hunger', 1, internal)
expect(not timeoutOk and timeoutErr.code == 'lock_timeout', 'lock ocupado nao expirou')
expect(runtime5.revision == 0 and players[5].metadata.hunger == 100, 'timeout alterou estado')
MZPlayerStateService._test.setLock(5, nil)

-- Shutdown bloqueia novas operacoes e a limpeza remove todos os runtimes.
MZPlayerStateService.beginShutdown()
local stoppedOk, stoppedErr = MZPlayerStateService.setStatus(5, 'hunger', 1, internal)
expect(not stoppedOk and stoppedErr.code == 'feature_disabled', 'shutdown aceitou mutacao')
MZPlayerStateService.clearRuntime()
expect(MZPlayerStateService._test.getRuntime(1) == nil and MZPlayerStateService._test.getRuntime(5) == nil, 'resource stop nao limpou runtimes')

print('player_state_concurrency_harness: ok')
