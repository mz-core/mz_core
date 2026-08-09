local function expect(condition, message)
  if not condition then error(message, 2) end
end

local function read(path)
  local file = assert(io.open(path, 'rb'))
  local content = file:read('*a')
  file:close()
  return content
end

local commands = read('server/vehicles/commands.lua')
local vehicleDebug = read('server/vehicles/debug.lua')
local qbProbe = read('server/bridges/qb_probe.lua')
local orgCommands = read('server/orgs/commands.lua')
local staging = read('server/player/state_staging.lua')
local runtimeProbe = read('server/orgs/runtime_probe.lua')
local outboxAdmin = read('server/accounts/outbox_admin.lua')

expect(not commands:find("Config and Config.Debug == true then", 1, true),
  'Config.Debug still grants vehicle command authorization')
expect(vehicleDebug:find("Config.Debug ~= true", 1, true)
  and vehicleDebug:find("isAceAllowed(source, DEBUG_ACE)", 1, true),
  'vehicle debug is not default-off plus ACE')
expect(qbProbe:find("Config.Debug ~= true", 1, true)
  and qbProbe:find("isAceAllowed(source, DEBUG_ACE)", 1, true),
  'QB mutation probe is not default-off plus ACE')
expect(orgCommands:find("isAceAllowed(src, 'mzcore.debug')", 1, true),
  'ACE diagnostic exposes results without a debug ACE')
expect(staging:find("GetConvarInt(name, 0) == 1", 1, true)
  and staging:find("IsPlayerAceAllowed(source, ace)", 1, true),
  'player-state staging surface lost convar or ACE gating')
expect(runtimeProbe:find("GetInvokingResource() ~= 'mz_org'", 1, true)
  and runtimeProbe:find("backupReference ~= ''", 1, true)
  and runtimeProbe:find("startsWith(citizenid, 'mztest_')", 1, true),
  'organization runtime probe is not caller/config/fixture constrained')
expect(outboxAdmin:find("policy.enabled ~= true", 1, true)
  and outboxAdmin:find('hasRequiredAce(source)', 1, true)
  and outboxAdmin:find("REPROCESS_DEAD_LETTER", 1, true),
  'outbox administration is not default-off, ACE gated, and confirmed')

print('[phase_0_5_debug_surface_harness] PASS surfaces=7 fail_closed=7')
