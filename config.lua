Config = {}

Config.Framework = 'mz_core'
Config.Debug = false
Config.OwnerAce = 'group.mz_owner'

Config.DefaultSpawn = {
  x = -1037.71,
  y = -2737.72,
  z = 20.17,
  heading = 329.0
}
Config.Multichar = {
  debugLifecycle = true,
  defaultSlots = 3,
  maximumSlots = 10,
  requestWindowMs = 10000,
  maximumRequestsPerWindow = 12,
  allowHotSwitch = false,
  mutationCallers = {
    mz_multichar = true,
    mz_creator = true
  }
}
-- Autoridade server-side dos estados persistidos do jogador. As listas vazias
-- negam writers externos por padrao; chamadas internas do mz_core usam um
-- contexto privado que nao e exposto por exports.
Config.PlayerStates = {
  enabled = true,
  persistence = {
    flushIntervalMs = 30000,
    debounceMs = 5000,
    lockTimeoutMs = 5000,
    criticalImmediateSave = true
  },
  status = {
    hunger = { default = 100, min = 0, max = 100, sensitive = true, writer = 'status' },
    thirst = { default = 100, min = 0, max = 100, sensitive = true, writer = 'status' },
    stress = { default = 0, min = 0, max = 100, sensitive = true, writer = 'status' },
    health = { default = 200, min = 0, max = 200, sensitive = true, writer = 'medical' },
    armor = { default = 0, min = 0, max = 100, sensitive = true, writer = 'armor' }
  },
  death = {
    default = 'alive',
    allowImmediateDeath = true,
    allowAdministrativeReviveFromDead = true,
    persistCriticalTransitions = true,
    lastStandEnabled = true,
    downedHealth = 1
  },
  sync = {
    enabled = true,
    resyncCooldownMs = 5000,
    resyncMaxRequestsPerWindow = 5,
    resyncWindowMs = 10000,
    pedReadyTimeoutMs = 10000,
    aliveMinHealth = 1
  },
  stateBags = {
    enabled = true,
    prefix = 'mz:'
  },
  reconciliation = {
    enabled = true,
    intervalMs = 3000,
    healthTolerance = 2,
    armorTolerance = 1,
    reportDebounceMs = 1000,
    fatalReportIntervalMs = 1000,
    fatalServerMinimumIntervalMs = 500,
    fatalCandidateWindowMs = 5000,
    requiredFatalReportsWithoutServerConfirmation = 2
  },
  clientObservation = {
    enabled = true,
    maxReportsPerWindow = 10,
    windowMs = 10000,
    extremeHealthReduction = 100,
    extremeArmorReduction = 75
  },
  authorization = {
    stateReaders = { 'mz_status', 'mz_medical', 'mz_admin' },
    statusWriters = { 'mz_status' },
    damageWriters = { 'mz_status' },
    healingWriters = { 'mz_status' },
    medicalWriters = { 'mz_admin', 'mz_medical' },
    armorWriters = { 'mz_admin' },
    administrativeWriters = { 'mz_admin' }
  },
  observability = {
    enabled = true,
    metricsEnabled = true,
    recentEventLimit = 200,
    readers = { 'mz_admin' },
    reporters = { 'mz_status', 'mz_medical' },
    alerts = {
      threshold = 3,
      windowMs = 60000,
      cooldownMs = 30000,
      recentLimit = 100
    }
  },
  staging = {
    convar = 'mz_player_state_staging',
    ace = 'mz.player_state.staging',
    maximumPerWindow = 12,
    windowMs = 10000
  },
  actions = {
    'inventory.open',
    'inventory.use',
    'inventory.move',
    'inventory.drop',
    'inventory.pickup',
    'storage.use',
    'weapon.use',
    'weapon.fire',
    'vehicle.enter',
    'vehicle.drive',
    'bank.use',
    'garage.use',
    'phone.use',
    'radio.use',
    'property.use',
    'emote.use',
    'command.use',
    'shop.use',
    'craft.use',
    'trade.use'
  }
}
