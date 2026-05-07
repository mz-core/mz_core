MZItems = {
  water = {
    image = 'water.png',
    label = 'Água',
    weight = 500,
    stack = true,
    unique = false,
    usable = true,
    closeOnUse = true,
    bindOnReceive = false,
    generateSerial = false
  },

  bread = {
    image = 'bread.png',
    label = 'Pão',
    weight = 300,
    stack = true,
    unique = false,
    usable = true,
    closeOnUse = true,
    bindOnReceive = false,
    generateSerial = false
  },

  bandage = {
    image = 'bandage.png',
    label = 'Bandagem',
    weight = 250,
    stack = true,
    unique = false,
    usable = true,
    closeOnUse = true,
    bindOnReceive = false,
    generateSerial = false
  },

  cellphone = {
    image = 'cellphone.png',
    label = 'Celular',
    weight = 800,
    stack = false,
    unique = true,
    usable = true,
    closeOnUse = false,
    bindOnReceive = true,
    generateSerial = true
  },

  id_card = {
    image = 'id_card.png',
    label = 'Documento',
    weight = 100,
    stack = false,
    unique = true,
    usable = true,
    closeOnUse = false,
    bindOnReceive = true,
    generateSerial = true
  },

  weapon_pistol = {
    image = 'weapon_pistol.png',
    label = 'Pistola',
    type = 'weapon',
    weapon = 'WEAPON_PISTOL',
    ammoType = 'ammo_pistol',
    clipSize = 12,
    defaultAmmo = 12,
    maxAmmo = 120,
    weight = 2500,
    stack = false,
    unique = true,
    usable = true,
    closeOnUse = true,
    bindOnReceive = true,
    generateSerial = true,
    hasDurability = true
  },

  weapon_smg = {
    image = 'weapon_smg.png',
    label = 'SMG',
    type = 'weapon',
    weapon = 'WEAPON_SMG',
    ammoType = 'ammo_smg',
    clipSize = 30,
    defaultAmmo = 0,
    maxAmmo = 180,
    weight = 3200,
    stack = false,
    unique = true,
    usable = true,
    closeOnUse = true,
    bindOnReceive = true,
    generateSerial = true,
    hasDurability = true
  },

  weapon_pumpshotgun = {
    image = 'weapon_pumpshotgun.png',
    label = 'Escopeta',
    type = 'weapon',
    weapon = 'WEAPON_PUMPSHOTGUN',
    ammoType = 'ammo_shotgun',
    clipSize = 8,
    defaultAmmo = 0,
    maxAmmo = 48,
    weight = 4200,
    stack = false,
    unique = true,
    usable = true,
    closeOnUse = true,
    bindOnReceive = true,
    generateSerial = true,
    hasDurability = true
  },

  weapon_carbinerifle = {
    image = 'weapon_carbinerifle.png',
    label = 'Fuzil',
    type = 'weapon',
    weapon = 'WEAPON_CARBINERIFLE',
    ammoType = 'ammo_rifle',
    clipSize = 30,
    defaultAmmo = 0,
    maxAmmo = 210,
    weight = 4800,
    stack = false,
    unique = true,
    usable = true,
    closeOnUse = true,
    bindOnReceive = true,
    generateSerial = true,
    hasDurability = true
  },

  weapon_sniperrifle = {
    image = 'weapon_sniperrifle.png',
    label = 'Sniper',
    type = 'weapon',
    weapon = 'WEAPON_SNIPERRIFLE',
    ammoType = 'ammo_sniper',
    clipSize = 5,
    defaultAmmo = 0,
    maxAmmo = 40,
    weight = 6200,
    stack = false,
    unique = true,
    usable = true,
    closeOnUse = true,
    bindOnReceive = true,
    generateSerial = true,
    hasDurability = true
  },

  weapon_mg = {
    image = 'weapon_mg.png',
    label = 'Metralhadora',
    type = 'weapon',
    weapon = 'WEAPON_MG',
    ammoType = 'ammo_heavy',
    clipSize = 54,
    defaultAmmo = 0,
    maxAmmo = 100,
    weight = 7500,
    stack = false,
    unique = true,
    usable = true,
    closeOnUse = true,
    bindOnReceive = true,
    generateSerial = true,
    hasDurability = true
  },

  weapon_rpg = {
    image = 'weapon_rpg.png',
    label = 'RPG',
    type = 'weapon',
    weapon = 'WEAPON_RPG',
    ammoType = 'ammo_rpg',
    clipSize = 1,
    defaultAmmo = 0,
    maxAmmo = 5,
    weight = 9000,
    stack = false,
    unique = true,
    usable = true,
    closeOnUse = true,
    bindOnReceive = true,
    generateSerial = true,
    hasDurability = true
  },

  ammo_pistol = {
    image = 'ammo_pistol.png',
    label = 'Munição de Pistola',
    type = 'ammo',
    ammoType = 'ammo_pistol',
    reloadAmount = 12,
    weight = 80,
    stack = true,
    unique = false,
    usable = true,
    closeOnUse = true,
    bindOnReceive = false,
    generateSerial = false
  },

  ammo_smg = {
    image = 'ammo_smg.png',
    label = 'Munição de SMG',
    type = 'ammo',
    ammoType = 'ammo_smg',
    reloadAmount = 30,
    weight = 90,
    stack = true,
    unique = false,
    usable = true,
    closeOnUse = true,
    bindOnReceive = false,
    generateSerial = false
  },

  ammo_shotgun = {
    image = 'ammo_shotgun.png',
    label = 'Cartucho Calibre 12',
    type = 'ammo',
    ammoType = 'ammo_shotgun',
    reloadAmount = 8,
    weight = 120,
    stack = true,
    unique = false,
    usable = true,
    closeOnUse = true,
    bindOnReceive = false,
    generateSerial = false
  },

  ammo_rifle = {
    image = 'ammo_rifle.png',
    label = 'Munição de Fuzil',
    type = 'ammo',
    ammoType = 'ammo_rifle',
    reloadAmount = 30,
    weight = 110,
    stack = true,
    unique = false,
    usable = true,
    closeOnUse = true,
    bindOnReceive = false,
    generateSerial = false
  },

  ammo_sniper = {
    image = 'ammo_sniper.png',
    label = 'Munição de Sniper',
    type = 'ammo',
    ammoType = 'ammo_sniper',
    reloadAmount = 5,
    weight = 160,
    stack = true,
    unique = false,
    usable = true,
    closeOnUse = true,
    bindOnReceive = false,
    generateSerial = false
  },

  ammo_heavy = {
    image = 'ammo_heavy.png',
    label = 'Munição Pesada',
    type = 'ammo',
    ammoType = 'ammo_heavy',
    reloadAmount = 20,
    weight = 250,
    stack = true,
    unique = false,
    usable = true,
    closeOnUse = true,
    bindOnReceive = false,
    generateSerial = false
  },

  ammo_rpg = {
    image = 'ammo_rpg.png',
    label = 'Foguete RPG',
    type = 'ammo',
    ammoType = 'ammo_rpg',
    reloadAmount = 1,
    weight = 1500,
    stack = true,
    unique = false,
    usable = true,
    closeOnUse = true,
    bindOnReceive = false,
    generateSerial = false
  },

  radio = {
    image = 'radio.png',
    label = 'Rádio',
    weight = 700,
    stack = false,
    unique = true,
    usable = true,
    closeOnUse = false,
    bindOnReceive = true,
    generateSerial = true
  }
}
