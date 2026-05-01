Config = {}

Config.Framework = 'mz_core'
Config.Debug = false

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

Config.Player = {
  defaultMetadata = {
    hunger = 100,
    thirst = 100,
    stress = 0,
    health = 200,
    armor = 0,
    isdead = false,
    inlaststand = false
  }
}

Config.Inventory = {
  defaultSlots = 40,
  defaultWeight = 50000,

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
  enableProximityRespawn = false,
  proximityRadius = 200.0,
  checkIntervalMs = 15000,
  maxRespawnsPerTick = 3,
  respawnDestroyed = true,
  debug = false,
  snapshotRateLimitMs = 5000,
  snapshotMaxDistance = 250.0,
  restoreDebounceMs = 5000
}
