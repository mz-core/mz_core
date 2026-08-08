MZ_PLAYER_STATE_CLIENT_TESTING = true

local function expect(condition, message)
  if not condition then error(message, 2) end
end

local events = {}
local handlers = {}
local exported = {}
local serverEvents = {}
local timer = 10000
local ped = 10
local pedExists = true
local health = 200
local maxHealth = 200
local armor = 0
local dead = false
local resurrectCount = 0
local healthWrites = {}
local armorWrites = {}

function GetGameTimer() timer = timer + 250; return timer end
function RegisterNetEvent(name, handler) events[name] = handler end
function AddEventHandler(name, handler) handlers[name] = handler end
function exports(name, handler) exported[name] = handler end
function TriggerServerEvent(name, payload) serverEvents[#serverEvents + 1] = { name = name, payload = payload } end
function PlayerId() return 1 end
function PlayerPedId() return ped end
function NetworkIsPlayerActive() return true end
function DoesEntityExist(entity) return pedExists and entity == ped end
function IsEntityAPed() return true end
function GetEntityHealth() return health end
function SetEntityHealth(_, value) health = value; dead = value <= 100; healthWrites[#healthWrites + 1] = value end
function GetEntityMaxHealth() return maxHealth end
function SetEntityMaxHealth(_, value) maxHealth = value end
function GetPedArmour() return armor end
function SetPedArmour(_, value) armor = value; armorWrites[#armorWrites + 1] = value end
function IsEntityDead() return dead end
function IsPedDeadOrDying() return dead end
function GetEntityCoords() return { x = 1.0, y = 2.0, z = 3.0 } end
function GetEntityHeading() return 90.0 end
function NetworkResurrectLocalPlayer() resurrectCount = resurrectCount + 1; dead = false; health = 101 end
function ClearPedTasksImmediately() end
function ClearPedBloodDamage() end
function ResetPedVisibleDamage() end

dofile('config.lua')
dofile('client/player_state.lua')

local function payload(revision, deathState, canonicalHealth, canonicalArmor, force, session)
  local isdead = deathState == 'dead' or deathState == 'respawning'
  return {
    revision = revision,
    sessionToken = session or 'session-a',
    observationToken = 'observation-a',
    status = {
      hunger = 90, thirst = 80, stress = 10,
      health = canonicalHealth, armor = canonicalArmor
    },
    death = {
      state = deathState,
      isdead = isdead,
      inlaststand = deathState == 'downed'
    },
    permissions = {
      inventoryBlocked = deathState ~= 'alive',
      weaponBlocked = deathState ~= 'alive',
      interactionBlocked = deathState ~= 'alive'
    },
    reason = { code = 'test', serverTime = 1 },
    forcePhysicalApply = force == true,
    sessionReset = revision == 1
  }
end

local first = payload(1, 'alive', 180, 40, false)
first.metadata = { privateSecret = true }
local ok, code = MZPlayerStateClient.receivePayload(first)
expect(ok and code == 'applied', 'new revision was not accepted')
expect(MZPlayerStateClient.getSnapshot().metadata == nil, 'unknown/full metadata leaked into local mirror')
expect(MZPlayerStateClient.receivePayload(payload(0, 'alive', 180, 40)) == false,
  'old revision was accepted')
ok, code = MZPlayerStateClient.receivePayload(payload(1, 'alive', 180, 40))
expect(ok and code == 'idempotent', 'same revision was not idempotent')
ok, code = MZPlayerStateClient.receivePayload(payload(1, 'alive', 180, 40, true))
expect(ok and code == 'physical_reapply', 'same revision force was not accepted')
expect(MZPlayerStateClient.receivePayload(payload(2, 'alive', 180, 40, false, 'old-session')) == false,
  'different session was accepted')
local invalid = payload(2, 'alive', 180, 40)
invalid.status.armor = 101
expect(MZPlayerStateClient.receivePayload(invalid) == false, 'invalid status range was accepted')

local test = MZPlayerStateClient._test
test.mirror.physicalReady = true
local snapshot = MZPlayerStateClient.getSnapshot()
snapshot = test.mirror.snapshot
health, armor, dead = 100, 0, false
local applied = test.applyPhysicalNow(snapshot, nil, test.mirror.generation, ped)
expect(applied and health == 180 and armor == 40, 'alive physical health/armor were not applied')

local oldSnapshot = snapshot
MZPlayerStateClient.receivePayload(payload(2, 'dead', 0, 0))
expect(test.applyPhysicalNow(oldSnapshot, 'alive', test.mirror.generation - 1, ped) == false,
  'superseded snapshot was allowed to finish')
health, armor, dead = 200, 50, false
snapshot = test.mirror.snapshot
applied = test.applyPhysicalNow(snapshot, 'alive', test.mirror.generation, ped)
expect(applied and health == 0 and armor == 0 and dead, 'dead snapshot restored positive vitals')

MZPlayerStateClient.receivePayload(payload(3, 'alive', 175, 25))
snapshot = test.mirror.snapshot
health, armor, dead = 0, 0, true
applied = test.applyPhysicalNow(snapshot, 'dead', test.mirror.generation, ped)
expect(applied and resurrectCount == 1 and health == 175 and armor == 25 and not dead,
  'canonical revive did not execute physical transition')
test.applyPhysicalNow(snapshot, 'dead', test.mirror.generation, ped)
expect(resurrectCount == 1, 'same revision revived twice')

MZPlayerStateClient.receivePayload(payload(4, 'respawning', 0, 0))
snapshot = test.mirror.snapshot
health, armor, dead = 150, 30, false
test.applyPhysicalNow(snapshot, 'dead', test.mirror.generation, ped)
expect(health == 0 and armor == 0, 'respawning applied alive vitals early')

MZPlayerStateClient.receivePayload(payload(5, 'alive', 160, 60))
snapshot = test.mirror.snapshot
health, armor, dead = 200, 0, false
test.applyPhysicalNow(snapshot, 'alive', test.mirror.generation, ped)
expect(health == 160 and armor == 60, 'model/spawn reapply did not restore canonical vitals')

MZPlayerStateClient.receivePayload(payload(6, 'downed', 1, 0))
snapshot = test.mirror.snapshot
health, armor, dead = 0, 30, true
test.applyPhysicalNow(snapshot, 'alive', test.mirror.generation, ped)
expect(health == 101 and armor == 0 and not dead, 'temporary downed physical state is incoherent')
expect(exported.CanLocalPlayerPerformAction('inventory.open') == false,
  'downed action contract allowed inventory')

MZPlayerStateClient.receivePayload(payload(7, 'alive', 160, 60))
snapshot = test.mirror.snapshot
health, armor, dead = 160, 60, false
test.applyPhysicalNow(snapshot, 'downed', test.mirror.generation, ped)

test.mirror.physicalReady = false
local timeoutOk, timeoutErr = test.applyPhysicalNow(snapshot, 'alive', test.mirror.generation)
expect(timeoutOk == false and timeoutErr == 'ped_ready_timeout', 'missing ped did not produce controlled timeout')
test.mirror.physicalReady = true

timer = timer + 1000
serverEvents = {}
health, armor, dead = 140, 50, false
test.mirror.lastAppliedPed = ped
expect(test.reconcile('health_damage') == true, 'vital divergence above tolerance was not reported')
expect(serverEvents[1] and serverEvents[1].name == 'mz_core:server:reportVitalCandidate'
  and serverEvents[1].payload.observedHealth == 140
  and serverEvents[1].payload.observedArmor == 50, 'observation payload was not minimal/correct')

timer = timer + 2000
serverEvents = {}
health, armor = 159, 59
expect(test.reconcile('within_tolerance') == false and #serverEvents == 0,
  'difference inside tolerance generated a report')

MZPlayerStateClient.receivePayload(payload(8, 'dead', 0, 0))
test.mirror.physicalReady = true
test.mirror.lastAppliedPed = ped
timer = timer + 1000
health, armor, dead = 150, 0, false
expect(test.reconcile('dead_ped_alive') == true, 'canonical dead/ped alive was not scheduled for correction')

MZPlayerStateClient.receivePayload(payload(9, 'alive', 180, 20))
test.mirror.physicalReady = true
test.mirror.lastAppliedPed = ped
timer = timer + 2000
serverEvents = {}
health, armor, dead = 0, 0, true
expect(test.reconcile('fatal') == true, 'canonical alive/ped dead was not reported')
expect(serverEvents[1] and serverEvents[1].payload.observedDead == true
  and serverEvents[1].payload.observedHealth == 0, 'fatal report schema is incorrect')

test.mirror.applying = true
expect(test.reconcile('applying') == false, 'reconciliation ran during canonical application')
test.mirror.applying = false
pedExists = false
expect(test.reconcile('missing_ped') == false, 'temporary missing ped generated a correction')
pedExists = true

expect(exported.GetLocalPlayerState() ~= test.mirror.snapshot, 'client export returned mutable mirror reference')
expect(exported.CanLocalPlayerPerformAction('inventory.open') == true, 'alive action contract rejected')

print('player_state_client_harness: ok')
