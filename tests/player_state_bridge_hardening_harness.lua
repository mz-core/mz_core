local function read(path)
  local file = assert(io.open(path, 'rb'))
  local content = file:read('*a')
  file:close()
  return content
end

local function expect(condition, message)
  if not condition then error('[player_state_bridge_hardening_harness] ' .. message, 2) end
end

local adapter = read('mz_core/server/bridges/adapter.lua')
local qb = read('mz_core/server/bridges/qb.lua')
local state = read('mz_core/server/player/state_service.lua')
local exportsFile = read('mz_core/server/player/exports.lua')

expect(qb:find('MZBridgeAdapter.getPlayerSnapshot', 1, true), 'alias QB nao usa snapshot')
expect(adapter:find('invokingResource = GetInvokingResource()', 1, true), 'bridge nao preserva invoking resource')
expect(state:find('PROTECTED_METADATA[key]', 1, true), 'metadata sensivel nao e fechada')
expect(state:find('applyBridgeMetadataPatch', 1, true) and state:find('statusAuthorization(key)', 1, true),
  'patch bridge ignora allowlist de status')
expect(not qb:find('RegisterNetEvent', 1, true), 'bridge criou evento client arbitrario')
expect(not qb:find('MarkPlayerDead', 1, true) and not qb:find('RevivePlayer', 1, true),
  'bridge aceita boolean/transicao de morte')
expect(adapter:find('warnBridgeDeprecation', 1, true), 'wrapper legado nao emite warning controlado')
expect(exportsFile:find('LegacyPlayerReadWarnings', 1, true), 'GetPlayer mutavel nao emite warning controlado')

print('[player_state_bridge_hardening_harness] PASS aliases=1 sensitive=3 events=2 warnings=2')
