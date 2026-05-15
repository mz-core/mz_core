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
  hotbarSlots = 5,
  hotbarKeys = {
    [1] = '1',
    [2] = '2',
    [3] = '3',
    [4] = '4',
    [5] = '5'
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
