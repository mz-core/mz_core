local function read(path)
  local file = assert(io.open(path, 'rb'))
  local content = file:read('*a')
  file:close()
  return content
end

local function expect(condition, message)
  if not condition then error('[player_state_bridge_hardening_harness] ' .. message, 2) end
end

local function exists(path)
  local file = io.open(path, 'rb')
  if not file then return false end
  file:close()
  return true
end

local state = read('mz_core/server/player/state_service.lua')
local exportsFile = read('mz_core/server/player/exports.lua')

expect(not exists('mz_core/server/bridges/adapter.lua')
  and not exists('mz_core/server/bridges/qb.lua')
  and not exists('mz_core/server/bridges/qb_probe.lua'),
  'compatibilidade QB externa permanece no core')
expect(state:find('PROTECTED_METADATA[key]', 1, true), 'metadata sensivel nao e fechada')
expect(not state:find('applyBridgeMetadataPatch', 1, true),
  'patch de metadata da compatibility QB permanece no core')
expect(not exportsFile:find("exports('GetPlayer',", 1, true)
  and not exportsFile:find("exports('GetPlayerByCitizenId',", 1, true)
  and exportsFile:find("exports('GetPlayerSnapshot',", 1, true)
  and exportsFile:find("exports('GetPlayerByCitizenIdSnapshot',", 1, true),
  'deprecated player reads permanecem ou replacements foram removidos')

print('[player_state_bridge_hardening_harness] PASS qb_compat=removed sensitive=3 legacy_reads=removed')
