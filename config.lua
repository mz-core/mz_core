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

Config.StarterMoney = {
  wallet = 500,
  bank = 5000,
  dirty = 0
}

-- Fase 3 / P3-D: escrita e dispatcher permanecem desligados por padrão.
-- O dispatcher processa somente a outbox; nunca altera saldo.
Config.FinancialOutbox = {
  enabled = false,
  writesEnabled = false,
  schemaVersion = 1,
  dispatcher = {
    enabled = false,
    pollMs = 1000,
    batchSize = 25,
    leaseSeconds = 30,
    maxAttempts = 10,
    backoffBaseSeconds = 5,
    backoffMaxSeconds = 900,
    jitterPercent = 20
  },
  administration = {
    enabled = false,
    ace = 'mz_core.financial_outbox.manage',
    command = 'mz_core_outbox',
    allowApply = false,
    applyEnableConvar = 'mz_core_p3e_reprocess_apply',
    previewTtlSeconds = 120,
    confirmationPhrase = 'REPROCESS_DEAD_LETTER',
    pendingSlaSeconds = 300,
    processedRetentionDays = 90,
    reportLimit = 50
  }
}

Config.Player = {}

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
    'property.use',
    'emote.use',
    'command.use',
    'shop.use',
    'craft.use',
    'trade.use'
  }
}

-- Contrato legado preservado, derivado da configuracao canonica acima.
Config.Player.defaultMetadata = {
  hunger = Config.PlayerStates.status.hunger.default,
  thirst = Config.PlayerStates.status.thirst.default,
  stress = Config.PlayerStates.status.stress.default,
  health = Config.PlayerStates.status.health.default,
  armor = Config.PlayerStates.status.armor.default,
  deathState = Config.PlayerStates.death.default,
  isdead = false,
  inlaststand = false
}

Config.Inventory = {
  defaultSlots = 40,
  defaultWeight = 50000,
  hotbarSlots = 5,
  hotbarKeys = {
    [1] = '1',
    [2] = '2',
    [3] = '3',
    [4] = '4',
    [5] = '5'
  },

  medicalReservation = {
    writers = { 'mz_medical' },
    readers = { 'mz_medical', 'mz_admin' },
    terminalRetentionSeconds = 900,
    maximumTtlSeconds = 60
  },

  personalStash = {
    slots = 40,
    weight = 75000
  },

  orgStash = {
    slots = 80,
    weight = 200000
  },

    trunk = {
    slots = 30,
    weight = 120000
  },
  
    glovebox = {
    slots = 8,
    weight = 15000
  }


}

Config.Weapons = {
  blockWeaponWheel = true,
  enforceInventoryWeapons = true,
  ammoSaveIntervalMs = 5000,
  ammoUpdateMinIntervalMs = 750,
  unauthorizedLogIntervalMs = 5000,
  ammoTypes = {
    ammo_pistol = {
      label = 'Munição de Pistola',
      reloadAmount = 12,
      maxAmmo = 120
    },
    ammo_smg = {
      label = 'Munição de SMG',
      reloadAmount = 30,
      maxAmmo = 180
    },
    ammo_shotgun = {
      label = 'Cartucho Calibre 12',
      reloadAmount = 8,
      maxAmmo = 48
    },
    ammo_rifle = {
      label = 'Munição de Fuzil',
      reloadAmount = 30,
      maxAmmo = 210
    },
    ammo_sniper = {
      label = 'Munição de Sniper',
      reloadAmount = 5,
      maxAmmo = 40
    },
    ammo_heavy = {
      label = 'Munição Pesada',
      reloadAmount = 20,
      maxAmmo = 100
    },
    ammo_rpg = {
      label = 'Foguete RPG',
      reloadAmount = 1,
      maxAmmo = 5
    }
  }
}

Config.SeedOrgTypes = {
  { code = 'job', name = 'Job' },
  { code = 'gang', name = 'Gang' },
  { code = 'staff', name = 'Staff' },
  { code = 'vip', name = 'VIP' },
  { code = 'business', name = 'Business' },
  { code = 'government', name = 'Government' },
  { code = 'event', name = 'Event' }
}

Config.Payroll = {
  enabled = true,
  intervalMinutes = 30,
  requireDuty = true
}

Config.VehicleWorld = {
  restoreOnPlayerJoin = false,
  enableProximityRespawn = false,
  autoReturnMissingOutsideVehicle = false,
  blockDuplicateOutsideSpawn = true,
  proximityRadius = 200.0,
  checkIntervalMs = 15000,
  maxRespawnsPerTick = 3,
  respawnDestroyed = true,
  debug = false,
  snapshotRateLimitMs = 5000,
  snapshotMaxDistance = 250.0,
  restoreDebounceMs = 5000
}
