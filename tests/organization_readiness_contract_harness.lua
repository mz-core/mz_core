local registered = {}

local function expect(condition, message)
  if not condition then error(message, 2) end
end

function exports(name, handler)
  registered[name] = handler
end

MZOrgService = {}
MZOrgStaffMutationService = {}
MZCoreState = {
  prepareDone = false,
  prepareOk = false,
  seedDone = false,
  seedOk = false,
  ready = false
}

dofile('server/orgs/exports.lua')

local readiness = registered.GetOrganizationReadiness
expect(type(readiness) == 'function', 'GetOrganizationReadiness export was not registered')

local preparing = readiness()
expect(preparing.ready == false, 'preparing owner reported ready')
expect(preparing.terminal == false, 'preparing owner reported terminal failure')
expect(preparing.reason == 'organization_owner_preparing', 'unexpected preparing reason')

MZCoreState.prepareDone = true
MZCoreState.prepareOk = false
local prepareFailed = readiness()
expect(prepareFailed.ready == false and prepareFailed.terminal == true, 'prepare failure did not fail closed')
expect(prepareFailed.reason == 'organization_schema_prepare_failed', 'unexpected prepare failure reason')

MZCoreState.prepareOk = true
local seedPending = readiness()
expect(seedPending.ready == false and seedPending.terminal == false, 'seed pending was not retryable')
expect(seedPending.reason == 'organization_seed_pending', 'unexpected seed pending reason')

MZCoreState.seedDone = true
MZCoreState.seedOk = false
local seedFailed = readiness()
expect(seedFailed.ready == false and seedFailed.terminal == true, 'seed failure did not fail closed')
expect(seedFailed.reason == 'organization_seed_failed', 'unexpected seed failure reason')

MZCoreState.seedOk = true
MZCoreState.ready = true
local ready = readiness()
expect(ready.ready == true and ready.terminal == false, 'ready owner did not report readiness')
expect(ready.reason == 'ready', 'unexpected ready reason')

print('organization_readiness_contract_harness: PASS states=5 fail_closed=2')
