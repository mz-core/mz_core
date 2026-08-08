MZ_PLAYER_STATE_TESTING = true

local function expect(condition, message)
  if not condition then error(message, 2) end
end

local timer = 1000
local events = {}
local clientEvents = {}
local bagWrites = {}
local bags = {}
local players = {}
local serverPed = { exists = false, health = 200, dead = false }

function GetGameTimer() timer = timer + 250; return timer end
function GetCurrentResourceName() return 'mz_core' end
function Wait() end
function RegisterNetEvent(name, handler) events[name] = handler end
function TriggerClientEvent(name, target, payload)
  clientEvents[#clientEvents + 1] = { name = name, target = target, payload = payload }
end
function Player(sourceId)
  bags[sourceId] = bags[sourceId] or {}
  return {
    state = {
      set = function(_, key, value, replicated)
        bags[sourceId][key] = value
        bagWrites[#bagWrites + 1] = { source = sourceId, key = key, value = value, replicated = replicated }
      end
    }
  }
end
function GetPlayerPed() return serverPed.exists and 99 or 0 end
function DoesEntityExist() return serverPed.exists end
function GetEntityHealth() return serverPed.health end
function IsEntityDead() return serverPed.dead end

MZPlayerRepository = {
  updateMetadata = function() return true end
}
MZPlayerService = {
  getPlayer = function(sourceId) return players[tonumber(sourceId)] end
}
MZPlayerHUDService = {
  syncToClient = function() return {} end
}
MZLogService = nil

dofile('config.lua')
dofile('server/player/state_normalizer.lua')
dofile('server/player/state_service.lua')
dofile('server/player/state_sync.lua')

local function addPlayer(sourceId, sessionId)
  players[sourceId] = {
    source = sourceId,
    citizenid = 'CID' .. sourceId,
    session = { id = sessionId },
    state = { loaded = true },
    metadata = {
      hunger = 90,
      thirst = 80,
      stress = 10,
      health = 180,
      armor = 40,
      deathState = 'alive',
      isdead = false,
      inlaststand = false,
      privateSecret = 'must-not-leak'
    }
  }
  local ok = MZPlayerStateService.initializePlayer(sourceId)
  expect(ok == true, 'player state initialization failed')
end

addPlayer(1, 101)
bagWrites = {}
local sync = MZPlayerStateSyncService.sync(1, 'test_load', { forcePhysicalApply = true, sessionReset = true })
expect(sync.ok == true and sync.revision == 0, 'initial sync failed')
expect(sync.payload.status.health == 180 and sync.payload.death.state == 'alive', 'payload lost canonical fields')
expect(sync.payload.privateSecret == nil and sync.payload.citizenid == nil and sync.payload.metadata == nil,
  'payload exposed complete metadata or identity')
expect(sync.payload.reason.code == 'test_load' and sync.payload.forcePhysicalApply == true,
  'structured reason or physical force missing')
expect(bagWrites[#bagWrites].key == 'mz:stateRevision', 'state revision was not the final bag write')
expect(bags[1]['mz:loaded'] == true and bags[1]['mz:inventoryBlocked'] == false,
  'alive load bags are incoherent')

clientEvents = {}
local context = MZPlayerStateService.internalContext('test_damage')
local statusOk, statusResult = MZPlayerStateService.setStatus(1, 'health', 170, context)
expect(statusOk and statusResult.changed and statusResult.revision == 1, 'status mutation failed')
expect(clientEvents[1] and clientEvents[1].name == 'mz_core:client:playerStateSync'
  and clientEvents[1].payload.revision == 1, 'mutation did not use central sync')
local zeroHealthOk = MZPlayerStateService.setStatus(1, 'health', 0, context)
expect(zeroHealthOk == false, 'alive health zero bypassed canonical death transition')

local identityOk, identity = MZPlayerStateService.getSyncIdentity(1)
expect(identityOk and identity.sessionToken and identity.observationToken, 'opaque sync identity missing')
source = 1
clientEvents = {}
events['mz_core:server:requestPlayerStateSync']()
expect(clientEvents[1] and clientEvents[1].name == 'mz_core:client:playerStateSync'
  and clientEvents[1].payload.forcePhysicalApply == true, 'read-only client resync did not return forced snapshot')
local _, rotatedIdentity = MZPlayerStateService.getSyncIdentity(1)
expect(rotatedIdentity.observationToken ~= identity.observationToken, 'resync did not rotate observation token')
local resyncEventCount = #clientEvents
events['mz_core:server:requestPlayerStateSync']()
expect(#clientEvents == resyncEventCount, 'resync cooldown allowed immediate spam response')
identity = rotatedIdentity

events['mz_core:server:reportVitalCandidate']({
  sessionToken = identity.sessionToken,
  observationToken = identity.observationToken,
  sequence = 1,
  localRevision = 1,
  observedHealth = 150,
  observedArmor = 30,
  observedDead = false
})
local stateOk, state = MZPlayerStateService.getState(1)
expect(stateOk and state.state.status.health == 150 and state.state.status.armor == 30
  and state.revision == 2, 'plausible vital reductions were not accepted atomically')

events['mz_core:server:reportVitalCandidate']({
  sessionToken = identity.sessionToken,
  observationToken = identity.observationToken,
  sequence = 2,
  localRevision = 2,
  observedHealth = 175,
  observedDead = false
})
stateOk, state = MZPlayerStateService.getState(1)
expect(state.state.status.health == 150 and state.revision == 2, 'observed increase changed canonical health')
local armorIncreaseOk = MZPlayerStateService.applyObservedVitals(1, nil, 31)
expect(armorIncreaseOk == false, 'observed armor increase was accepted')

events['mz_core:server:reportVitalCandidate']({
  sessionToken = identity.sessionToken,
  observationToken = identity.observationToken,
  sequence = 3,
  localRevision = 1,
  observedHealth = 100,
  observedDead = false
})
stateOk, state = MZPlayerStateService.getState(1)
expect(state.state.status.health == 150 and state.revision == 2, 'stale observation changed canonical state')

events['mz_core:server:reportVitalCandidate']({
  sessionToken = identity.sessionToken,
  observationToken = identity.observationToken,
  sequence = 3,
  localRevision = 2,
  observedHealth = 100,
  target = 2
})
stateOk, state = MZPlayerStateService.getState(1)
expect(state.state.status.health == 150, 'payload with target was accepted')

events['mz_core:server:reportVitalCandidate']({
  sessionToken = identity.sessionToken,
  observationToken = identity.observationToken,
  sequence = 3,
  localRevision = 2,
  observedHealth = 0,
  observedDead = true
})
stateOk, state = MZPlayerStateService.getState(1)
expect(state.state.deathState == 'alive', 'single unconfirmed fatal report changed state')
events['mz_core:server:reportVitalCandidate']({
  sessionToken = identity.sessionToken,
  observationToken = identity.observationToken,
  sequence = 4,
  localRevision = 2,
  observedHealth = 0,
  observedDead = true
})
stateOk, state = MZPlayerStateService.getState(1)
expect(state.state.deathState == 'downed' and state.state.status.health == 1
  and state.state.status.armor == 0, 'coherent fallback fatal reports did not enter downed')
expect(bags[1]['mz:isDowned'] == true and bags[1]['mz:inventoryBlocked'] == true,
  'downed bags are incoherent')
events['mz_core:server:reportVitalCandidate']({
  sessionToken = identity.sessionToken,
  observationToken = identity.observationToken,
  sequence = 5,
  localRevision = 3,
  observedHealth = 0,
  observedDead = true
})
stateOk, state = MZPlayerStateService.getState(1)
expect(state.state.deathState == 'downed' and state.revision == 3,
  'fatal report in non-alive state was not idempotently ignored')

addPlayer(2, 202)
Config.PlayerStates.death.lastStandEnabled = false
serverPed.exists, serverPed.health, serverPed.dead = true, 0, true
local _, identity2 = MZPlayerStateService.getSyncIdentity(2)
source = 2
events['mz_core:server:reportVitalCandidate']({
  sessionToken = identity2.sessionToken,
  observationToken = identity2.observationToken,
  sequence = 1,
  localRevision = 0,
  observedHealth = 0,
  observedDead = true
})
stateOk, state = MZPlayerStateService.getState(2)
expect(state.state.deathState == 'dead', 'server-confirmed fatal report did not enter dead when last stand disabled')

bagWrites = {}
local cleared = MZPlayerStateSyncService.clearStateBags(1)
expect(cleared.ok and bagWrites[#bagWrites].key == 'mz:stateRevision'
  and bags[1]['mz:loaded'] == false, 'unload bag cleanup failed or revision was not final')
local oldSessionToken = identity.sessionToken
MZPlayerStateService.finalizeUnload(1)
players[1] = nil
addPlayer(1, 303)
local _, replacementIdentity = MZPlayerStateService.getSyncIdentity(1)
expect(replacementIdentity.sessionToken ~= oldSessionToken, 'reused source inherited prior session token')
MZPlayerStateSyncService.sync(1, 'replacement_load')
expect(bags[1]['mz:loaded'] == true and bags[1]['mz:stateRevision'] == 0,
  'reused source did not receive fresh state bags')

local payloadOk = MZPlayerStateSyncService._test.validateObservationPayload({
  sessionToken = 's', observationToken = 'o', sequence = 1, localRevision = 0,
  observedHealth = 100, observedDead = false
})
expect(payloadOk == true, 'minimal observation schema rejected')
local forgedOk = MZPlayerStateSyncService._test.validateObservationPayload({
  sessionToken = 's', observationToken = 'o', sequence = 1, localRevision = 0,
  observedHealth = 100, target = 5
})
expect(forgedOk == false, 'closed observation schema accepted target')
local largeOk = MZPlayerStateSyncService._test.validateObservationPayload({
  sessionToken = 's', observationToken = 'o', sequence = 1, localRevision = 0,
  observedHealth = 100, observedArmor = 10, observedDead = false, extra = true
})
expect(largeOk == false, 'oversized observation payload was accepted')

addPlayer(3, 404)
local _, identity3 = MZPlayerStateService.getSyncIdentity(3)
local lastAllowed = true
for sequence = 1, 11 do
  lastAllowed = MZPlayerStateService.consumeClientEventAttempt(3, 'observation', 10, 10000)
end
expect(lastAllowed == false, 'observation window rate limit did not reject excess report')

print('player_state_sync_harness: ok')
