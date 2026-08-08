MZ_PLAYER_STATE_OBSERVABILITY_TESTING = true

local timer, invoking = 1000, 'mz_admin'
local registered, persisted = {}, {}

Config = { PlayerStates = { observability = {
  enabled = true,
  metricsEnabled = true,
  recentEventLimit = 20,
  readers = { 'mz_admin' },
  reporters = { 'mz_status', 'mz_medical' },
  alerts = { threshold = 3, windowMs = 60000, cooldownMs = 30000, recentLimit = 10 }
} } }

function GetGameTimer() return timer end
function GetInvokingResource() return invoking end
function exports(name, callback) registered[name] = callback end
MZLogService = { createDetailed = function(_, eventName, payload)
  persisted[#persisted + 1] = { event = eventName, payload = payload }
  return true
end }

dofile('server/player/state_observability.lua')

local function expect(condition, message)
  if not condition then error('[player_state_observability_harness] ' .. message, 2) end
end

local ok = MZPlayerStateObservability.record('status_consumable_completed', {
  source = 4, operationId = 'op-1', sessionToken = 'secret', evidence = { observationToken = 'hidden', item = 'water' }
}, 'mz_status')
expect(ok == true, 'reporter autorizado foi rejeitado')
expect(MZPlayerStateObservability._test.counters.consumables_total == 1, 'contador de consumivel nao incrementou')

local snapshot = MZPlayerStateObservability.snapshot()
expect(snapshot.recentEvents[1].evidence.observationToken == '<redacted>', 'token apareceu na telemetria')
expect(MZPlayerStateObservability.record('medical_treatment_started', {}, 'mz_status') == false,
  'prefixo de outro dominio foi aceito')

for _ = 1, 3 do
  expect(MZPlayerStateObservability.reportSuspicion('player_state_stale_session', 4, {
    reason = 'revision_mismatch', evidence = { sessionToken = 'secret', count = 1 }
  }, 'mz_core') == true, 'sinal suspeito foi rejeitado')
end
snapshot = MZPlayerStateObservability.snapshot()
expect(#snapshot.alerts == 1 and snapshot.alerts[1].count == 3, 'agregacao de alerta incorreta')
expect(snapshot.alerts[1].evidence.sessionToken == '<redacted>', 'alerta nao removeu token')

local suspiciousLogs = 0
for _, row in ipairs(persisted) do
  if row.event == 'player_state_suspicious_activity' then suspiciousLogs = suspiciousLogs + 1 end
end
expect(suspiciousLogs == 1, 'cooldown nao suprimiu log repetido')
expect(MZPlayerStateObservability.reportSuspicion('dynamic_' .. string.rep('x', 80), 4, {}, 'mz_core') == false,
  'categoria de alta cardinalidade foi aceita')

invoking = 'mz_phone'
expect(registered.GetPlayerStateObservability() == false, 'leitor nao autorizado acessou metricas')
invoking = 'mz_admin'
local readOk, readSnapshot = registered.GetPlayerStateObservability()
expect(readOk == true and type(readSnapshot.metrics) == 'table', 'leitor autorizado nao recebeu snapshot')

print('[player_state_observability_harness] PASS metrics=1 redaction=2 aggregation=2 allowlist=3')
