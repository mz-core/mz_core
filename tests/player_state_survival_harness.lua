local function expect(condition, message)
  if not condition then error(message, 2) end
end

MZ_PLAYER_STATE_TESTING = true
dofile('config.lua')

local clock, writes, syncs = 1000, 0, 0
local failPersistence = false
local players = {}
local vitalEvents = {}

function GetGameTimer() return clock end
function Wait() clock = clock + 1 end
function GetCurrentResourceName() return 'mz_core' end
function TriggerEvent(name, source, payload)
  vitalEvents[#vitalEvents + 1] = { name = name, source = source, payload = payload }
end

MZPlayerRepository = {
  updateMetadata = function()
    writes = writes + 1
    return not failPersistence
  end
}
MZPlayerService = { getPlayer = function(source) return players[tonumber(source)] end }
MZPlayerStateSyncService = {
  sync = function()
    syncs = syncs + 1
    return { ok = true }
  end
}

dofile('server/player/state_normalizer.lua')
dofile('server/player/state_service.lua')

local function fresh(source)
  players[source] = {
    source = source,
    citizenid = ('MZ%06d'):format(source),
    session = { id = source * 10 },
    state = { loaded = true },
    metadata = {
      hunger = 100, thirst = 100, stress = 0, health = 200, armor = 0,
      deathState = 'alive', isdead = false, inlaststand = false
    }
  }
  expect(MZPlayerStateService.initializePlayer(source) == true, 'runtime nao inicializou')
  return players[source]
end

local statusContext = { invokingResource = 'mz_status', reason = 'harness' }
fresh(1)
local ok, result = MZPlayerStateService.applyStatusPatch(1, { hunger = -2, thirst = -3 }, statusContext)
expect(ok and result.changed and result.revision == 1, 'patch agrupado nao criou uma revision')
expect(result.state.status.hunger == 98 and result.state.status.thirst == 97, 'patch agrupado aplicou valor errado')
expect(syncs == 1, 'patch agrupado nao criou exatamente um sync')
local runtime = MZPlayerStateService._test.getRuntime(1)
expect(runtime.dirty.hunger and runtime.dirty.thirst, 'patch agrupado nao marcou dirty fields')
expect(writes == 0, 'patch comum fez flush imediato')

ok, result = MZPlayerStateService.applyStatusPatch(1, { health = -1 }, statusContext)
expect(not ok and result.code == 'invalid_patch', 'patch aceitou health')
ok, result = MZPlayerStateService.applyStatusPatch(1, { hunger = -1 }, { invokingResource = 'forged' })
expect(not ok and result.code == 'not_authorized', 'patch aceitou writer forjado')

ok, result = MZPlayerStateService.applyHealthDamage(1, 25, statusContext)
expect(ok and result.state.health == 175 and result.state.deathState == 'alive', 'dano canonico nao reduziu health')
expect(#vitalEvents == 1 and vitalEvents[1].name == 'mz_core:server:playerVitalChangedInternal', 'evento interno de dano ausente')
expect(vitalEvents[1].payload.healthDelta == 25 and vitalEvents[1].payload.fatal == false, 'payload interno de dano incorreto')
ok, result = MZPlayerStateService.applyHealing(1, 10, statusContext)
expect(ok and result.state.health == 185 and result.state.deathState == 'alive', 'cura basica falhou')
ok, result = MZPlayerStateService.applyHealthDamage(1, -1, statusContext)
expect(not ok and result.code == 'invalid_value', 'API de dano aceitou aumento/valor negativo')
ok, result = MZPlayerStateService.applyHealing(1, -1, statusContext)
expect(not ok and result.code == 'invalid_value', 'API de cura aceitou valor negativo')
ok, result = MZPlayerStateService.applyHealthDamage(1, 5, { invokingResource = 'forged' })
expect(not ok and result.code == 'not_authorized', 'writer de dano forjado foi aceito')

local writesBeforeFatal = writes
ok, result = MZPlayerStateService.applyHealthDamage(1, 500, statusContext)
expect(ok and result.state.deathState == 'downed' and result.state.health == 1, 'dano fatal nao entrou em downed atomicamente')
expect(players[1].metadata.deathState == 'downed' and players[1].metadata.health == 1, 'houve health zero/alive')
expect(writes == writesBeforeFatal + 1, 'dano fatal nao fez persistencia critica')
ok, result = MZPlayerStateService.applyHealing(1, 10, statusContext)
expect(not ok and result.code == 'invalid_state', 'cura reviveu downed')

Config.PlayerStates.death.lastStandEnabled = false
fresh(2)
ok, result = MZPlayerStateService.applyHealthDamage(2, 500, statusContext)
expect(ok and result.state.deathState == 'dead' and result.state.health == 0, 'politica sem last stand nao entrou em dead')
ok, result = MZPlayerStateService.applyHealthDamage(2, 1, statusContext)
expect(not ok and result.code == 'invalid_state', 'morto recebeu dano repetido')

fresh(3)
failPersistence = true
ok, result = MZPlayerStateService.applyHealthDamage(3, 500, statusContext)
expect(not ok and result.code == 'persistence_pending' and result.changed == true, 'fatal pending perdeu semantica funcional')
expect(players[3].metadata.deathState == 'dead', 'fatal pending desfez estado em memoria')

print('player_state_survival_harness: ok')
