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
    defaultAmmo = 12,
    maxAmmo = 250,
    weight = 2500,
    stack = false,
    unique = true,
    usable = true,
    closeOnUse = true,
    bindOnReceive = true,
    generateSerial = true,
    hasDurability = true
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
