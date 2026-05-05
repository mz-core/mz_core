MZClient = MZClient or {}
MZClient.InventoryWeapons = MZClient.InventoryWeapons or {
  authorized = nil,
  lastAmmoSent = nil,
  lastUnauthorizedReportAt = 0
}

local WEAPON_UNARMED = `WEAPON_UNARMED`

local function getWeaponConfig()
  return type(Config.Weapons) == 'table' and Config.Weapons or {}
end

local function getWeaponHash(weaponName)
  weaponName = tostring(weaponName or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
  if weaponName == '' then
    return nil
  end

  local ok, result = pcall(function()
    return joaat(weaponName)
  end)

  if ok and result then
    return result
  end

  return nil
end

local function getPed()
  local ped = PlayerPedId()
  if not ped or ped == 0 then
    return nil
  end

  return ped
end

local function getAuthorizedAmmo()
  local authorized = MZClient.InventoryWeapons.authorized
  if type(authorized) ~= 'table' then
    return nil
  end

  local ped = getPed()
  if not ped then
    return nil
  end

  local weaponHash = tonumber(authorized.weapon_hash) or getWeaponHash(authorized.weapon)
  if not weaponHash then
    return nil
  end

  return math.max(0, math.floor(tonumber(GetAmmoInPedWeapon(ped, weaponHash)) or 0))
end

local function sendWeaponAmmoUpdate(reason, force)
  local authorized = MZClient.InventoryWeapons.authorized
  if type(authorized) ~= 'table' or tostring(authorized.instance_uid or '') == '' then
    return false
  end

  local ammo = getAuthorizedAmmo()
  if ammo == nil then
    return false
  end

  local knownAmmo = tonumber(authorized.ammo)
  if knownAmmo == nil or ammo <= knownAmmo then
    authorized.ammo = ammo
  end

  if force ~= true and MZClient.InventoryWeapons.lastAmmoSent == ammo then
    return false
  end

  MZClient.InventoryWeapons.lastAmmoSent = ammo
  TriggerServerEvent('mz_core:server:inventory:updateWeaponAmmo', {
    instance_uid = authorized.instance_uid,
    equip_nonce = authorized.equip_nonce,
    slot = authorized.slot,
    ammo = ammo,
    reason = tostring(reason or 'periodic')
  })

  return true
end

local function setUnarmed(ped)
  ped = ped or getPed()
  if not ped then
    return
  end

  SetCurrentPedWeapon(ped, WEAPON_UNARMED, true)
end

local function removeInventoryWeapons(ped)
  ped = ped or getPed()
  if not ped then
    return
  end

  RemoveAllPedWeapons(ped, true)
  setUnarmed(ped)
end

local function reportUnauthorizedWeapon(weaponHash, reason)
  local now = GetGameTimer()
  if now - (MZClient.InventoryWeapons.lastUnauthorizedReportAt or 0) < 5000 then
    return
  end

  MZClient.InventoryWeapons.lastUnauthorizedReportAt = now
  local authorized = MZClient.InventoryWeapons.authorized

  TriggerServerEvent('mz_core:server:inventory:unauthorizedWeaponDetected', {
    weapon_hash = tostring(weaponHash or ''),
    authorized_instance_uid = type(authorized) == 'table' and tostring(authorized.instance_uid or '') or '',
    reason = tostring(reason or 'unauthorized_weapon')
  })
end

local function applyAuthorizedWeapon(payload)
  payload = type(payload) == 'table' and payload or {}
  local ped = getPed()
  if not ped then
    return
  end

  sendWeaponAmmoUpdate('before_switch', true)

  local weaponName = tostring(payload.weapon or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
  local weaponHash = tonumber(payload.weapon_hash) or getWeaponHash(weaponName)
  if not weaponHash then
    removeInventoryWeapons(ped)
    MZClient.InventoryWeapons.authorized = nil
    return
  end

  local ammo = math.max(0, math.floor(tonumber(payload.ammo) or 0))
  removeInventoryWeapons(ped)
  GiveWeaponToPed(ped, weaponHash, ammo, false, true)
  SetPedAmmo(ped, weaponHash, ammo)
  SetCurrentPedWeapon(ped, weaponHash, true)

  MZClient.InventoryWeapons.authorized = {
    item = tostring(payload.item or ''),
    slot = tonumber(payload.slot) or payload.slot,
    instance_uid = tostring(payload.instance_uid or ''),
    equip_nonce = tostring(payload.equip_nonce or ''),
    weapon = weaponName,
    weapon_hash = weaponHash,
    ammo = ammo,
    serial = payload.serial,
    durability = payload.durability
  }
  MZClient.InventoryWeapons.lastAmmoSent = ammo
end

local function unequipAuthorizedWeapon(payload)
  payload = type(payload) == 'table' and payload or {}
  local authorized = MZClient.InventoryWeapons.authorized

  if type(authorized) == 'table' then
    sendWeaponAmmoUpdate(payload.reason or 'before_unequip', true)
  end

  local ped = getPed()
  if ped then
    local weaponHash = type(authorized) == 'table' and (tonumber(authorized.weapon_hash) or getWeaponHash(authorized.weapon)) or nil
    if weaponHash then
      RemoveWeaponFromPed(ped, weaponHash)
    else
      removeInventoryWeapons(ped)
    end

    setUnarmed(ped)
  end

  MZClient.InventoryWeapons.authorized = nil
  MZClient.InventoryWeapons.lastAmmoSent = nil
end

RegisterNetEvent('mz_core:client:inventory:equipWeapon', function(payload)
  applyAuthorizedWeapon(payload)
end)

RegisterNetEvent('mz_core:client:inventory:unequipWeapon', function(payload)
  unequipAuthorizedWeapon(payload)
end)

CreateThread(function()
  while true do
    if getWeaponConfig().blockWeaponWheel ~= false then
      DisableControlAction(0, 14, true)
      DisableControlAction(0, 15, true)
      DisableControlAction(0, 16, true)
      DisableControlAction(0, 17, true)
      DisableControlAction(0, 37, true)
      DisableControlAction(0, 157, true)
      DisableControlAction(0, 158, true)
      DisableControlAction(0, 159, true)
      DisableControlAction(0, 160, true)
      DisableControlAction(0, 161, true)
      DisableControlAction(0, 162, true)
      DisableControlAction(0, 163, true)
      DisableControlAction(0, 164, true)

      if type(BlockWeaponWheelThisFrame) == 'function' then
        BlockWeaponWheelThisFrame()
      end

      HideHudComponentThisFrame(19)
      HideHudComponentThisFrame(20)
    end

    Wait(0)
  end
end)

CreateThread(function()
  while true do
    if getWeaponConfig().enforceInventoryWeapons ~= false then
      local ped = getPed()
      if ped then
        local selectedWeapon = GetSelectedPedWeapon(ped)
        local authorized = MZClient.InventoryWeapons.authorized

        if type(authorized) ~= 'table' then
          if selectedWeapon and selectedWeapon ~= WEAPON_UNARMED then
            reportUnauthorizedWeapon(selectedWeapon, 'no_authorized_weapon')
            removeInventoryWeapons(ped)
          end
        else
          local authorizedHash = tonumber(authorized.weapon_hash) or getWeaponHash(authorized.weapon)
          if authorizedHash and selectedWeapon ~= WEAPON_UNARMED and selectedWeapon ~= authorizedHash then
            reportUnauthorizedWeapon(selectedWeapon, 'different_weapon_selected')
            if HasPedGotWeapon(ped, authorizedHash, false) then
              SetCurrentPedWeapon(ped, authorizedHash, true)
            else
              GiveWeaponToPed(ped, authorizedHash, tonumber(authorized.ammo) or 0, false, true)
              SetCurrentPedWeapon(ped, authorizedHash, true)
            end
          end
        end
      end
    end

    Wait(1500)
  end
end)

CreateThread(function()
  while true do
    local interval = tonumber(getWeaponConfig().ammoSaveIntervalMs) or 5000
    if interval < 1000 then
      interval = 1000
    end

    sendWeaponAmmoUpdate('periodic', false)
    Wait(interval)
  end
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then
    return
  end

  sendWeaponAmmoUpdate('resource_stop', true)

  if getWeaponConfig().enforceInventoryWeapons ~= false then
    removeInventoryWeapons()
  end
end)
