local function expect(condition, message)
  if not condition then error(message, 2) end
end

MZ_PLAYER_STATE_TESTING = true

dofile('config.lua')
Config.PlayerStates.authorization.statusWriters = { 'allowed_status' }
Config.PlayerStates.authorization.medicalWriters = { 'allowed_medical' }
Config.PlayerStates.authorization.armorWriters = { 'allowed_armor' }
Config.PlayerStates.authorization.administrativeWriters = { 'allowed_admin' }

local clock = 1000
local writes = 0
local failPersistence = false
local players = {}

function GetGameTimer() return clock end
function Wait() clock = clock + 1 end
function GetCurrentResourceName() return 'mz_core' end

MZPlayerRepository = {
  updateMetadata = function()
    writes = writes + 1
    if failPersistence then return false end
    return true
  end
}
MZPlayerService = {
  getPlayer = function(source) return players[tonumber(source)] end
}
local registeredExports = {}
function exports(name, handler)
  registeredExports[name] = handler
end
function GetInvokingResource()
  return 'harness'
end
MZLogService = {
  createDetailed = function(domain, action, payload)
    table.insert(_G.__playerStateHarnessLogs or {}, { domain = domain, action = action, payload = payload })
    return true
  end
}
_G.__playerStateHarnessLogs = {}

dofile('server/player/state_normalizer.lua')
dofile('server/player/state_service.lua')

local function freshPlayer(source, deathState)
  local legacy = MZPlayerStateNormalizer.getLegacyFlags(deathState or 'alive')
  players[source] = {
    source = source,
    citizenid = ('MZ%06d'):format(source),
    session = { id = source * 10 },
    state = { loaded = true },
    metadata = {
      hunger = 100, thirst = 100, stress = 0, health = 200, armor = 0,
      deathState = deathState or 'alive', isdead = legacy.isdead, inlaststand = legacy.inlaststand,
      otherDomain = { preserved = true }
    }
  }
  local ok = MZPlayerStateService.initializePlayer(source)
  expect(ok == true, 'runtime nao inicializou')
  return players[source]
end

local internal = MZPlayerStateService.internalContext('harness')
freshPlayer(1)

local ok, result = MZPlayerStateService.setStatus(1, 'hunger', 80, internal)
expect(ok and result.changed and result.revision == 1 and result.state.hunger == 80, 'SetStatus falhou')
expect(MZPlayerStateService._test.getRuntime(1).dirty.hunger == true, 'dirty de status nao foi marcado')

ok, result = MZPlayerStateService.addStatus(1, 'hunger', 50, internal)
expect(ok and result.state.hunger == 100 and result.revision == 2, 'AddStatus/clamp superior falhou')
ok, result = MZPlayerStateService.removeStatus(1, 'hunger', 500, internal)
expect(ok and result.state.hunger == 0 and result.revision == 3, 'RemoveStatus/clamp inferior falhou')

local beforeRejected = result.revision
ok, result = MZPlayerStateService.setStatus(1, 'unknown', 1, internal)
expect(not ok and result.code == 'invalid_status', 'status arbitrario foi aceito')
ok, result = MZPlayerStateService.setStatus(1, 'hunger', 0 / 0, internal)
expect(not ok and result.code == 'invalid_value', 'NaN foi aceito')
ok, result = MZPlayerStateService.addStatus(1, 'hunger', -1, internal)
expect(not ok and result.code == 'invalid_value', 'amount negativo foi aceito')
ok, result = MZPlayerStateService.setStatus(999, 'hunger', 10, internal)
expect(not ok and result.code == 'player_not_found', 'player inexistente foi aceito')
expect(MZPlayerStateService._test.getRuntime(1).revision == beforeRejected, 'rejeicao incrementou revision')

ok = MZPlayerStateService.setStatus(1, 'thirst', 75, {
  invokingResource = 'allowed_status', reason = 'authorized_test'
})
expect(ok == true, 'resource autorizado foi negado')
local revisionAfterAuthorized = MZPlayerStateService._test.getRuntime(1).revision
ok, result = MZPlayerStateService.setStatus(1, 'thirst', 50, {
  invokingResource = 'forged_resource', reason = 'unauthorized_test'
})
expect(not ok and result.code == 'not_authorized', 'resource nao autorizado foi aceito')
expect(MZPlayerStateService._test.getRuntime(1).revision == revisionAfterAuthorized, 'negacao de autorizacao incrementou revision')

freshPlayer(8)
ok = MZPlayerStateService.setStatus(8, 'health', 150, { invokingResource = 'allowed_medical' })
expect(ok == true, 'writer medical autorizado foi negado')
ok = MZPlayerStateService.setStatus(8, 'armor', 75, { invokingResource = 'allowed_armor' })
expect(ok == true, 'writer armor autorizado foi negado')
ok, result = MZPlayerStateService.setStatus(8, 'armor', 10, { invokingResource = 'allowed_status' })
expect(not ok and result.code == 'not_authorized', 'writer de status contornou categoria armor')
ok, result = MZPlayerStateService.getStatus(8, 'armor')
expect(ok and result.value == 75, 'GetStatus nao retornou valor registrado')

ok, result = MZPlayerStateService.getState(1)
expect(ok and result.state.otherDomain == nil, 'snapshot expos metadata completa')
result.state.status.hunger = 999
local _, freshSnapshot = MZPlayerStateService.getState(1)
expect(freshSnapshot.state.status.hunger == 0, 'snapshot compartilha referencia mutavel')

local writesBeforeDebounce = writes
ok, result = MZPlayerStateService.flush(1, 'debounce_test', false, internal)
expect(ok and result.code == 'debounced' and writes == writesBeforeDebounce, 'dirty salvou antes do debounce')
clock = clock + Config.PlayerStates.persistence.debounceMs + 1
ok, result = MZPlayerStateService.flush(1, 'debounce_test', false, internal)
expect(ok and result.code == 'flushed' and writes == writesBeforeDebounce + 1, 'dirty nao salvou depois do debounce')
expect(next(MZPlayerStateService._test.getRuntime(1).dirty) == nil, 'sucesso nao limpou dirty')

ok, result = MZPlayerStateService.setGenericMetadata(1, 'appearance', { model = 'test' }, internal)
expect(ok and players[1].metadata.appearance.model == 'test', 'metadata nao sensivel falhou')
ok, result = MZPlayerStateService.setGenericMetadata(1, 'isdead', true, internal)
expect(not ok and result.code == 'protected_metadata' and players[1].metadata.isdead == false, 'setter generico alterou chave protegida')
local suspiciousLogs = _G.__playerStateHarnessLogs
expect(#suspiciousLogs >= 1, 'nenhuma atividade suspeita foi registrada')
local latestLog = suspiciousLogs[#suspiciousLogs]
expect(latestLog.action == 'suspicious_activity', 'atividade suspeita nao foi registrada no canal central')

freshPlayer(2)
local writesBeforeDeath = writes
ok, result = MZPlayerStateService.markDowned(2, { invokingResource = 'allowed_medical', reason = 'test' })
expect(ok and result.state.deathState == 'downed' and result.state.inlaststand == true, 'alive -> downed falhou')
expect(players[2].metadata.downedAt ~= nil and writes == writesBeforeDeath + 1, 'downed nao pediu persistencia critica')
local downedRevision = result.revision
ok, result = MZPlayerStateService.markDowned(2, { invokingResource = 'allowed_medical' })
expect(ok and result.code == 'already_in_state' and result.revision == downedRevision, 'downed idempotente falhou')
ok, result = MZPlayerStateService.markDead(2, { invokingResource = 'allowed_medical' })
expect(ok and result.state.deathState == 'dead' and result.state.isdead and not result.state.inlaststand, 'downed -> dead falhou')
ok, result = MZPlayerStateService.beginRespawn(2, { invokingResource = 'allowed_medical' })
expect(ok and result.state.deathState == 'respawning' and result.state.isdead, 'dead -> respawning falhou')
ok, result = MZPlayerStateService.completeRespawn(2, { invokingResource = 'allowed_medical' })
expect(ok and result.state.deathState == 'alive' and not result.state.isdead, 'respawning -> alive falhou')

freshPlayer(3)
ok, result = MZPlayerStateService.markDead(3, { invokingResource = 'allowed_medical' })
expect(ok and result.state.deathState == 'dead' and result.state.health == 0, 'alive -> dead imediato falhou')
local revisionBeforeInvalid = result.revision
ok, result = MZPlayerStateService.setStatus(3, 'health', 200, { invokingResource = 'allowed_medical' })
expect(not ok and result.code == 'invalid_transition', 'SetStatus health reviveu estado dead')
ok, result = MZPlayerStateService.markDowned(3, { invokingResource = 'allowed_medical' })
expect(not ok and result.code == 'invalid_transition', 'dead -> downed foi aceito')
expect(MZPlayerStateService._test.getRuntime(3).revision == revisionBeforeInvalid, 'transicao invalida incrementou revision')
ok, result = MZPlayerStateService.revive(3, { invokingResource = 'allowed_medical' })
expect(not ok and result.code == 'invalid_transition', 'revive direto comum de dead foi aceito')
ok, result = MZPlayerStateService.revive(3, { invokingResource = 'allowed_admin', administrative = true, actorSource = 7 })
expect(ok and result.state.deathState == 'alive', 'revive administrativo auditavel falhou')

freshPlayer(4)
ok = MZPlayerStateService.markDowned(4, { invokingResource = 'allowed_medical' })
expect(ok, 'precondicao de revive downed falhou')
ok, result = MZPlayerStateService.revive(4, { invokingResource = 'allowed_medical' })
expect(ok and result.state.deathState == 'alive' and players[4].metadata.reviveAt ~= nil, 'downed -> alive falhou')

freshPlayer(9)
ok, result = MZPlayerStateService.markDowned(9, { invokingResource = 'allowed_medical' })
expect(ok, 'precondicao de deadline medico falhou')
local revisionBeforeDeadline = result.revision
local downedDeadline = os.time() + 300
ok, result = MZPlayerStateService.setDeathDeadline(9, 'downed', downedDeadline, {
  invokingResource = 'allowed_medical'
})
expect(ok and result.changed and result.state.deathTimestamps.downedExpiresAt == downedDeadline,
  'deadline downed nao foi persistido no snapshot')
expect(result.revision == revisionBeforeDeadline + 1, 'deadline nao incrementou uma revision')
local revisionWithDeadline = result.revision
ok, result = MZPlayerStateService.setDeathDeadline(9, 'downed', downedDeadline + 30, {
  invokingResource = 'allowed_medical'
})
expect(not ok and result.code == 'invalid_deadline', 'deadline existente foi renovado')
ok, result = MZPlayerStateService.revive(9, {
  invokingResource = 'allowed_medical', expectedRevision = revisionWithDeadline - 1,
  reviveHealth = 100, reviveArmor = 5
})
expect(not ok and result.code == 'revision_mismatch', 'revive aceitou revision obsoleta')
ok, result = MZPlayerStateService.revive(9, {
  invokingResource = 'allowed_medical', expectedRevision = revisionWithDeadline,
  reviveHealth = 100, reviveArmor = 5
})
expect(ok and result.state.deathState == 'alive' and result.state.health == 100 and result.state.armor == 5,
  'revive revisionado nao aplicou vitais server-owned')
expect(players[9].metadata.downedExpiresAt == nil, 'revive nao limpou deadline downed')

freshPlayer(5)
failPersistence = true
ok, result = MZPlayerStateService.markDead(5, { invokingResource = 'allowed_medical' })
expect(not ok and result.code == 'persistence_pending' and result.changed == true, 'falha critica nao retornou persistence_pending')
expect(players[5].metadata.deathState == 'dead' and next(MZPlayerStateService._test.getRuntime(5).dirty) ~= nil, 'falha critica perdeu cache ou dirty')
failPersistence = false
ok = MZPlayerStateService.flush(5, 'retry', true, internal)
expect(ok and next(MZPlayerStateService._test.getRuntime(5).dirty) == nil, 'retry nao limpou dirty')

freshPlayer(6)
ok, result = MZPlayerStateService.applyBridgeMetadataPatch(6, {
  hunger = 10,
  appearance_updated_at = 123,
  otherDomain = { preserved = 'changed' }
}, { invokingResource = 'allowed_status' })
expect(ok and result.revision == 1 and players[6].metadata.hunger == 10, 'patch atomico da bridge falhou')
expect(players[6].metadata.otherDomain.preserved == 'changed', 'patch removeu metadata de outro dominio')
ok, result = MZPlayerStateService.applyBridgeMetadataPatch(6, { isdead = true }, { invokingResource = 'allowed_medical' })
expect(not ok and result.code == 'protected_metadata' and players[6].metadata.deathState == 'alive', 'bridge contornou maquina de morte')
local bridgeProtectedLogs = {}
for _, entry in ipairs(_G.__playerStateHarnessLogs) do
  if entry.action == 'protected_metadata_blocked' and entry.payload and entry.payload.context and entry.payload.context.operation == 'bridge_metadata_patch' then
    bridgeProtectedLogs[#bridgeProtectedLogs + 1] = entry
  end
end
expect(#bridgeProtectedLogs >= 1, 'bridge patch protegido nao foi registrado no canal central')

ok, result = MZPlayerStateService.canPerformAction(6, 'inventory.open')
expect(ok and result.allowed == true, 'acao de alive foi bloqueada')
MZPlayerStateService.markDowned(6, { invokingResource = 'allowed_medical' })
ok, result = MZPlayerStateService.canPerformAction(6, 'inventory.open')
expect(ok and result.allowed == false, 'acao de downed foi permitida')
ok, result = MZPlayerStateService.canPerformAction(6, 'arbitrary.action')
expect(not ok and result.code == 'invalid_action', 'acao arbitraria foi aceita')

freshPlayer(7)
MZPlayerStateService.setStatus(7, 'stress', 10, internal)
failPersistence = true
ok, result = MZPlayerStateService.beginUnload(7, 'test_unload')
expect(not ok and next(MZPlayerStateService._test.getRuntime(7).dirty) ~= nil, 'falha no unload apagou dirty')
failPersistence = false
ok, result = MZPlayerStateService.setStatus(7, 'stress', 20, internal)
expect(not ok and result.code == 'unloading', 'mutacao durante unload foi aceita')
MZPlayerStateService.finalizeUnload(7)
expect(MZPlayerStateService._test.getRuntime(7) == nil, 'runtime nao foi limpo no unload')

print('player_state_service_harness: ok')
