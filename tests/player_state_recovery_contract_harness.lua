local function read(path)
  local file = assert(io.open(path, 'rb'))
  local content = file:read('*a')
  file:close()
  return content
end

local function expect(condition, message)
  if not condition then error('[player_state_recovery_contract_harness] ' .. message, 2) end
end

local inventory = read('mz_core/server/inventory/service.lua')
local inventoryExports = read('mz_core/server/inventory/exports.lua')
local medical = read('mz_medical/server/service.lua')
local medicalMain = read('mz_medical/server/main.lua')
local staging = read('mz_core/server/player/state_staging.lua')
local playerExports = read('mz_core/server/player/exports.lua')
local stateExports = read('mz_core/server/player/state_exports.lua')
local statusService = read('mz_status/server/service.lua')

expect(inventory:find('MedicalItemReservationTerminals', 1, true), 'cache terminal idempotente ausente')
expect(inventory:find("return false, 'reservation_terminal'", 1, true), 'operationId terminal pode ser reutilizado')
expect(inventoryExports:find("exports('GetMedicalItemReservations'", 1, true), 'consulta read-only de reservas ausente')
expect(medical:find('backoffBaseSeconds', 1, true) and medical:find('maximumAttempts', 1, true),
  'retry medico sem backoff/limite')
expect(medical:find("'commit_exhausted'", 1, true) and medical:find("'rollback_exhausted'", 1, true),
  'exaustao de recovery nao e observavel')
expect(medicalMain:find("exports('GetMedicalOperations'", 1, true)
  and medicalMain:find("exports('RecoverMedicalOperation'", 1, true), 'API administrativa de recovery ausente')
expect(staging:find("RegisterCommand('mz_medical_recover'", 1, true), 'comando staging de recovery ausente')
expect(staging:find("RegisterCommand('mz_state_runtime'", 1, true), 'diagnostico de identidade runtime ausente')
expect(staging:find('if state then value = state[key] end', 1, true),
  'diagnostico de bags ainda converte false em missing')
expect(playerExports:find("exports('GetPlayerSnapshot'", 1, true)
  and playerExports:find("exports('GetPlayerByCitizenIdSnapshot'", 1, true), 'snapshot read-only de player ausente')
expect(stateExports:find("exports('GetPlayerStateRuntimeIdentity'", 1, true)
  and stateExports:find('runtimeStateReaderAllowed', 1, true), 'identidade runtime nao possui export/allowlist')
expect(statusService:find('GetPlayerStateRuntimeIdentity', 1, true), 'scheduler ainda depende da sessao legada')

print('[player_state_recovery_contract_harness] PASS idempotency=3 retry=2 admin=2 snapshots=2 runtime_identity=5')
