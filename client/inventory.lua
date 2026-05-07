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

local function getInventoryConfig()
  return type(Config.Inventory) == 'table' and Config.Inventory or {}
end

local function logWeaponClientReject(reason, payload)
  if getWeaponConfig().debugClient ~= true then
    return
  end

  local encoded = '{}'
  if json and type(json.encode) == 'function' then
    local ok, result = pcall(function()
      return json.encode(type(payload) == 'table' and payload or {})
    end)
    if ok and result then
      encoded = tostring(result)
    end
  end

  print(('[mz_core][inventory][apply_ammo_rejected] reason=%s | payload=%s'):format(
    tostring(reason or 'unknown'),
    encoded
  ))
end

local function getAuthorizedMaxAmmo(authorized, payload)
  authorized = type(authorized) == 'table' and authorized or {}
  payload = type(payload) == 'table' and payload or {}

  local maxAmmo = tonumber(authorized.maxAmmo or authorized.max_ammo or payload.maxAmmo or payload.max_ammo)
  if maxAmmo == nil then
    local itemDef = MZItems and MZItems[tostring(authorized.item or '')] or nil
    if type(itemDef) == 'table' then
      maxAmmo = tonumber(itemDef.maxAmmo)
      if maxAmmo == nil then
        local ammoTypes = getWeaponConfig().ammoTypes
        local ammoTypeConfig = type(ammoTypes) == 'table' and ammoTypes[tostring(itemDef.ammoType or '')] or nil
        if type(ammoTypeConfig) == 'table' then
          maxAmmo = tonumber(ammoTypeConfig.maxAmmo)
        end
      end
    end
  end

  if maxAmmo == nil then
    return nil
  end

  maxAmmo = math.floor(maxAmmo)
  if maxAmmo < 0 then
    return 0
  end

  return maxAmmo
end

local function getHotbarSlotCount()
  local count = tonumber(getInventoryConfig().hotbarSlots) or 5
  count = math.floor(count)
  if count < 1 then
    count = 1
  end

  return count
end

local function useHotbarSlot(hotbarSlot)
  hotbarSlot = tonumber(hotbarSlot)
  if not hotbarSlot then
    return
  end

  TriggerServerEvent('mz_core:server:inventory:useHotbarSlot', {
    hotbar_slot = math.floor(hotbarSlot)
  })
end

local function notifyInventoryWeapon(message, notifyType)
  message = tostring(message or '')
  if message == '' then
    return
  end

  local payload = {
    type = tostring(notifyType or 'info'),
    title = 'Inventario',
    message = message,
    duration = 3500
  }

  if GetResourceState('mz_notify') == 'started' then
    exports['mz_notify']:Notify(payload)
    return
  end

  if lib and type(lib.notify) == 'function' then
    lib.notify({
      title = payload.title,
      description = payload.message,
      type = payload.type == 'info' and 'inform' or payload.type
    })
    return
  end

  print(('[mz_core][inventory][%s] %s'):format(payload.type, payload.message))
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

local function getWeaponClipAmmoNative(ped, weaponHash)
  if not ped or not weaponHash then
    return nil
  end

  local ok, clip = GetAmmoInClip(ped, weaponHash)
  if ok == true and type(clip) == 'number' then
    return math.max(math.floor(clip), 0)
  end

  if type(ok) == 'number' then
    return math.max(math.floor(ok), 0)
  end

  return nil
end

local function calculateWeaponAmmoParts(totalAmmo, clipSize, preferredClip)
  totalAmmo = math.max(0, math.floor(tonumber(totalAmmo) or 0))
  clipSize = math.max(0, math.floor(tonumber(clipSize) or 0))

  if totalAmmo <= 0 then
    return 0, 0
  end

  local clipAmmo = tonumber(preferredClip)
  if clipAmmo ~= nil then
    clipAmmo = math.max(0, math.floor(clipAmmo))
    clipAmmo = math.min(clipAmmo, totalAmmo)
  elseif clipSize > 0 then
    clipAmmo = math.min(totalAmmo, clipSize)
  else
    clipAmmo = math.min(totalAmmo, 30)
  end

  return clipAmmo, math.max(totalAmmo - clipAmmo, 0)
end

local function setAuthorizedAmmoDisplay(authorized, totalAmmo, clipAmmo, reserveAmmo)
  if type(authorized) ~= 'table' then
    return
  end

  totalAmmo = math.max(0, math.floor(tonumber(totalAmmo) or 0))
  clipAmmo, reserveAmmo = calculateWeaponAmmoParts(totalAmmo, authorized.clipSize, clipAmmo)

  authorized.ammo = totalAmmo
  authorized.clipAmmo = clipAmmo
  authorized.reserveAmmo = reserveAmmo
  authorized.ammoText = ('%d / %d'):format(clipAmmo, reserveAmmo)
end

local function lockAuthorizedClip(authorized, durationMs)
  if type(authorized) ~= 'table' then
    return
  end

  authorized.clipLockedUntil = GetGameTimer() + (tonumber(durationMs) or 1500)
end

local function applyWeaponAmmoToPed(ped, weaponHash, totalAmmo, clipSize)
  totalAmmo = math.max(0, math.floor(tonumber(totalAmmo) or 0))
  local desiredClip, reserveAmmo = calculateWeaponAmmoParts(totalAmmo, clipSize)

  SetPedAmmo(ped, weaponHash, totalAmmo)
  SetCurrentPedWeapon(ped, weaponHash, true)
  SetAmmoInClip(ped, weaponHash, desiredClip)

  Wait(0)
  if GetSelectedPedWeapon(ped) == weaponHash then
    SetAmmoInClip(ped, weaponHash, desiredClip)
  end

  return desiredClip, reserveAmmo
end

local function applyAuthorizedAmmoDisplayToPed(ped, weaponHash, authorized)
  if type(authorized) ~= 'table' then
    return 0, 0
  end

  local totalAmmo = math.max(0, math.floor(tonumber(authorized.ammo) or 0))
  local clipAmmo, reserveAmmo = calculateWeaponAmmoParts(totalAmmo, authorized.clipSize, authorized.clipAmmo)

  SetPedAmmo(ped, weaponHash, totalAmmo)
  SetCurrentPedWeapon(ped, weaponHash, true)
  SetAmmoInClip(ped, weaponHash, clipAmmo)

  Wait(0)
  if GetSelectedPedWeapon(ped) == weaponHash then
    SetAmmoInClip(ped, weaponHash, clipAmmo)
  end

  setAuthorizedAmmoDisplay(authorized, totalAmmo, clipAmmo)
  return clipAmmo, reserveAmmo
end

local function isNativeClipReliable(authorized, nativeClip, nativeTotal, weaponHash)
  if type(authorized) ~= 'table' then
    return false, 'missing_authorized'
  end

  nativeClip = tonumber(nativeClip)
  nativeTotal = tonumber(nativeTotal)
  if nativeClip == nil or nativeTotal == nil then
    return false, 'missing_native_values'
  end

  nativeClip = math.floor(nativeClip)
  nativeTotal = math.floor(nativeTotal)
  if nativeClip < 0 then
    return false, 'negative_clip'
  end

  local clipSize = math.floor(tonumber(authorized.clipSize) or 0)
  if clipSize > 0 and nativeClip > clipSize then
    return false, 'clip_above_clip_size'
  end

  if nativeClip > nativeTotal then
    return false, 'clip_above_total'
  end

  if GetGameTimer() < (tonumber(authorized.clipLockedUntil) or 0) then
    return false, 'clip_locked'
  end

  local ped = PlayerPedId()
  if not ped or ped == 0 or not weaponHash or GetSelectedPedWeapon(ped) ~= weaponHash then
    return false, 'weapon_not_selected'
  end

  local knownTotal = tonumber(authorized.ammo)
  local knownClip = tonumber(authorized.clipAmmo)
  if knownTotal == nil or knownClip == nil then
    return true, 'no_known_clip'
  end

  if nativeTotal >= knownTotal and nativeClip < knownClip then
    return false, 'clip_dropped_without_total_drop'
  end

  if nativeTotal < knownTotal and nativeClip < knownClip then
    local totalDrop = knownTotal - nativeTotal
    local clipDrop = knownClip - nativeClip
    if clipDrop > totalDrop then
      return false, 'clip_drop_exceeds_total_drop'
    end
  end

  return true, 'ok'
end

local function publishWeaponHudState(reason)
  local authorized = MZClient.InventoryWeapons.authorized
  if type(authorized) ~= 'table' then
    MZClient.InventoryWeapons.lastPublishedAmmo = nil
    MZClient.InventoryWeapons.lastPublishedClipAmmo = nil
    MZClient.InventoryWeapons.lastPublishedReserveAmmo = nil
    MZClient.InventoryWeapons.lastPublishedAmmoText = nil

    TriggerEvent('mz_core:client:weaponHudState', {
      equipped = false,
      reason = tostring(reason or 'unequip')
    })
    return
  end

  local itemName = tostring(authorized.item or '')
  local itemDef = MZItems and MZItems[itemName] or nil
  local weaponName = tostring(authorized.weapon or '')
  local weaponHash = tonumber(authorized.weapon_hash) or getWeaponHash(weaponName)
  local totalAmmo = math.max(0, math.floor(tonumber(authorized.ammo) or 0))
  local clipSize = tonumber(authorized.clipSize) or (type(itemDef) == 'table' and tonumber(itemDef.clipSize) or nil)
  local clipAmmo, reserveAmmo = calculateWeaponAmmoParts(totalAmmo, clipSize, authorized.clipAmmo)
  local ammoText = authorized.ammoText or ('%d / %d'):format(clipAmmo, reserveAmmo)

  MZClient.InventoryWeapons.lastPublishedAmmo = totalAmmo
  MZClient.InventoryWeapons.lastPublishedClipAmmo = clipAmmo
  MZClient.InventoryWeapons.lastPublishedReserveAmmo = reserveAmmo
  MZClient.InventoryWeapons.lastPublishedAmmoText = ammoText

  TriggerEvent('mz_core:client:weaponHudState', {
    equipped = true,
    reason = tostring(reason or 'update'),
    item = itemName,
    label = type(itemDef) == 'table' and tostring(itemDef.label or itemName) or itemName,
    weapon = weaponName,
    weaponHash = weaponHash,
    ammo = totalAmmo,
    maxAmmo = tonumber(authorized.maxAmmo) or (type(itemDef) == 'table' and tonumber(itemDef.maxAmmo) or nil),
    clipSize = clipSize,
    clipAmmo = clipAmmo,
    reserveAmmo = reserveAmmo,
    ammoText = ammoText,
    ammoType = tostring(authorized.ammoType or (type(itemDef) == 'table' and itemDef.ammoType or '') or ''),
    serial = authorized.serial,
    durability = authorized.durability,
    ammo_revision = math.max(0, math.floor(tonumber(authorized.ammo_revision) or 0))
  })
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

local function hasPublishedWeaponHudDisplayChanged(authorized)
  if type(authorized) ~= 'table' then
    return false
  end

  return tonumber(MZClient.InventoryWeapons.lastPublishedAmmo) ~= tonumber(authorized.ammo)
    or tonumber(MZClient.InventoryWeapons.lastPublishedClipAmmo) ~= tonumber(authorized.clipAmmo)
    or tonumber(MZClient.InventoryWeapons.lastPublishedReserveAmmo) ~= tonumber(authorized.reserveAmmo)
    or tostring(MZClient.InventoryWeapons.lastPublishedAmmoText or '') ~= tostring(authorized.ammoText or '')
end

local function updateAuthorizedVisualAmmoFromPed(reason)
  local authorized = MZClient.InventoryWeapons.authorized
  if type(authorized) ~= 'table' or tostring(authorized.instance_uid or '') == '' then
    return false
  end

  local ped = getPed()
  if not ped then
    return false
  end

  local weaponHash = tonumber(authorized.weapon_hash) or getWeaponHash(authorized.weapon)
  if not weaponHash then
    return false
  end

  local nativeTotal = math.max(0, math.floor(tonumber(GetAmmoInPedWeapon(ped, weaponHash)) or 0))
  local nativeClip = getWeaponClipAmmoNative(ped, weaponHash)
  local knownAmmo = tonumber(authorized.ammo)
  if knownAmmo == nil or nativeTotal >= knownAmmo then
    return false
  end

  local totalDrop = knownAmmo - nativeTotal
  local reliableClip = isNativeClipReliable(authorized, nativeClip, nativeTotal, weaponHash)
  local nextClip = reliableClip and nativeClip or nil

  if not nextClip then
    local currentClip = tonumber(authorized.clipAmmo)
    if currentClip ~= nil then
      nextClip = math.max(0, math.floor(currentClip) - totalDrop)
    end
  end

  setAuthorizedAmmoDisplay(authorized, nativeTotal, nextClip)

  if hasPublishedWeaponHudDisplayChanged(authorized) then
    publishWeaponHudState(reason or 'ammo_visual_update')
    return true
  end

  return false
end

local function sendWeaponAmmoUpdate(reason, force)
  local authorized = MZClient.InventoryWeapons.authorized
  if type(authorized) ~= 'table' or tostring(authorized.instance_uid or '') == '' then
    return false
  end

  local ped = getPed()
  if not ped then
    return false
  end

  local weaponHash = tonumber(authorized.weapon_hash) or getWeaponHash(authorized.weapon)
  if not weaponHash then
    return false
  end

  local nativeTotal = math.max(0, math.floor(tonumber(GetAmmoInPedWeapon(ped, weaponHash)) or 0))
  local nativeClip = getWeaponClipAmmoNative(ped, weaponHash)
  local knownAmmo = tonumber(authorized.ammo)
  local previousAmmo = knownAmmo
  local previousClipAmmo = tonumber(authorized.clipAmmo)
  local ammoForServer = nativeTotal

  if knownAmmo == nil then
    local reliableClip = isNativeClipReliable(authorized, nativeClip, nativeTotal, weaponHash)
    setAuthorizedAmmoDisplay(authorized, nativeTotal, reliableClip and nativeClip or nil)
  elseif nativeTotal < knownAmmo then
    local totalDrop = knownAmmo - nativeTotal
    local reliableClip = isNativeClipReliable(authorized, nativeClip, nativeTotal, weaponHash)
    local nextClip = reliableClip and nativeClip or nil

    if not nextClip then
      local currentClip = tonumber(authorized.clipAmmo)
      if currentClip ~= nil then
        nextClip = math.max(0, math.floor(currentClip) - totalDrop)
      end
    end

    setAuthorizedAmmoDisplay(authorized, nativeTotal, nextClip)
  elseif nativeTotal > knownAmmo then
    ammoForServer = knownAmmo
    if getWeaponConfig().debugClient == true then
      logWeaponClientReject('native_total_above_authorized', {
        native_total = nativeTotal,
        authorized_total = knownAmmo,
        native_clip = nativeClip,
        weapon = authorized.weapon
      })
    end
  end

  if tonumber(authorized.ammo) ~= previousAmmo or tonumber(authorized.clipAmmo) ~= previousClipAmmo then
    publishWeaponHudState(nativeTotal < (previousAmmo or nativeTotal) and 'ammo_update_shot' or tostring(reason or 'ammo_update'))
  end

  if ammoForServer == nil then
    return false
  end

  if force ~= true and MZClient.InventoryWeapons.lastAmmoSent == ammoForServer then
    return false
  end

  MZClient.InventoryWeapons.lastAmmoSent = ammoForServer
  TriggerServerEvent('mz_core:server:inventory:updateWeaponAmmo', {
    instance_uid = authorized.instance_uid,
    equip_nonce = authorized.equip_nonce,
    ammo_revision = math.max(0, math.floor(tonumber(authorized.ammo_revision) or 0)),
    slot = authorized.slot,
    ammo = ammoForServer,
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
  local itemName = tostring(payload.item or '')
  local itemDef = MZItems and MZItems[itemName] or nil
  local clipSize = tonumber(payload.clipSize) or (type(itemDef) == 'table' and tonumber(itemDef.clipSize) or nil)
  removeInventoryWeapons(ped)
  GiveWeaponToPed(ped, weaponHash, ammo, false, true)
  local clipAmmo, reserveAmmo = applyWeaponAmmoToPed(ped, weaponHash, ammo, clipSize)

  MZClient.InventoryWeapons.authorized = {
    item = itemName,
    slot = tonumber(payload.slot) or payload.slot,
    instance_uid = tostring(payload.instance_uid or ''),
    equip_nonce = tostring(payload.equip_nonce or ''),
    weapon = weaponName,
    weapon_hash = weaponHash,
    ammo = ammo,
    ammo_revision = math.max(0, math.floor(tonumber(payload.ammo_revision) or 0)),
    maxAmmo = getAuthorizedMaxAmmo({ item = itemName }, payload),
    clipSize = clipSize,
    clipAmmo = clipAmmo,
    reserveAmmo = reserveAmmo,
    ammoText = ('%d / %d'):format(clipAmmo, reserveAmmo),
    ammoType = type(itemDef) == 'table' and tostring(itemDef.ammoType or '') or '',
    serial = payload.serial,
    durability = payload.durability
  }
  lockAuthorizedClip(MZClient.InventoryWeapons.authorized, 1500)
  MZClient.InventoryWeapons.lastAmmoSent = ammo
  publishWeaponHudState('equip')
end

local function applyAuthorizedAmmo(payload)
  payload = type(payload) == 'table' and payload or {}
  local authorized = MZClient.InventoryWeapons.authorized
  if type(authorized) ~= 'table' then
    logWeaponClientReject('missing_authorized_weapon', payload)
    return
  end

  local instanceUid = tostring(payload.instance_uid or '')
  local equipNonce = tostring(payload.equip_nonce or '')
  if instanceUid == '' or instanceUid ~= tostring(authorized.instance_uid or '') then
    logWeaponClientReject('instance_uid_mismatch', payload)
    return
  end

  if equipNonce == '' or equipNonce ~= tostring(authorized.equip_nonce or '') then
    logWeaponClientReject('equip_nonce_mismatch', payload)
    return
  end

  local weaponName = tostring(payload.weapon or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
  if weaponName ~= '' and weaponName ~= tostring(authorized.weapon or '') then
    logWeaponClientReject('weapon_mismatch', payload)
    return
  end

  local ammo = tonumber(payload.ammo)
  if ammo == nil then
    logWeaponClientReject('invalid_ammo', payload)
    return
  end

  local payloadRevision = tonumber(payload.ammo_revision)
  if payloadRevision == nil then
    logWeaponClientReject('missing_ammo_revision', payload)
    return
  end

  payloadRevision = math.max(0, math.floor(payloadRevision))
  local currentRevision = math.max(0, math.floor(tonumber(authorized.ammo_revision) or 0))
  if payloadRevision ~= currentRevision + 1 then
    logWeaponClientReject('stale_or_unexpected_ammo_revision', payload)
    return
  end

  ammo = math.max(0, math.floor(ammo))
  local maxAmmo = getAuthorizedMaxAmmo(authorized, payload)
  if maxAmmo and ammo > maxAmmo then
    logWeaponClientReject('ammo_above_max', payload)
    return
  end

  local ped = getPed()
  if not ped then
    logWeaponClientReject('missing_ped', payload)
    return
  end

  local weaponHash = tonumber(authorized.weapon_hash) or getWeaponHash(authorized.weapon)
  if not weaponHash or not HasPedGotWeapon(ped, weaponHash, false) then
    logWeaponClientReject('authorized_weapon_missing_from_ped', payload)
    return
  end

  local itemDef = MZItems and MZItems[tostring(authorized.item or '')] or nil
  local clipSize = tonumber(authorized.clipSize) or tonumber(payload.clipSize) or (type(itemDef) == 'table' and tonumber(itemDef.clipSize) or nil)
  authorized.clipSize = clipSize
  local clipAmmo = applyWeaponAmmoToPed(ped, weaponHash, ammo, clipSize)

  setAuthorizedAmmoDisplay(authorized, ammo, clipAmmo)
  authorized.ammo_revision = payloadRevision
  lockAuthorizedClip(authorized, 1500)
  MZClient.InventoryWeapons.lastAmmoSent = ammo

  publishWeaponHudState('ammo_apply')

  local reloadAmount = tonumber(payload.reload_amount)
  if reloadAmount and reloadAmount > 0 then
    notifyInventoryWeapon(('Recarregado: +%s municoes.'):format(math.floor(reloadAmount)), 'success')
  end
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
  publishWeaponHudState(tostring(payload.reason or 'unequip'))
end

RegisterNetEvent('mz_core:client:inventory:equipWeapon', function(payload)
  applyAuthorizedWeapon(payload)
end)

RegisterNetEvent('mz_core:client:inventory:applyWeaponAmmo', function(payload)
  applyAuthorizedAmmo(payload)
end)

RegisterNetEvent('mz_core:client:inventory:unequipWeapon', function(payload)
  unequipAuthorizedWeapon(payload)
end)

for slot = 1, getHotbarSlotCount() do
  local hotbarSlot = slot
  local commandName = ('mz_hotbar_%s'):format(hotbarSlot)
  RegisterCommand(commandName, function()
    useHotbarSlot(hotbarSlot)
  end, false)

  local hotbarKeys = getInventoryConfig().hotbarKeys
  local defaultKey = type(hotbarKeys) == 'table' and hotbarKeys[hotbarSlot] or tostring(hotbarSlot)
  RegisterKeyMapping(
    commandName,
    ('Usar hotbar %s'):format(hotbarSlot),
    'keyboard',
    tostring(defaultKey or hotbarSlot)
  )
end

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
              applyAuthorizedAmmoDisplayToPed(ped, authorizedHash, authorized)
            else
              GiveWeaponToPed(ped, authorizedHash, tonumber(authorized.ammo) or 0, false, true)
              applyAuthorizedAmmoDisplayToPed(ped, authorizedHash, authorized)
            end

            lockAuthorizedClip(authorized, 750)
            publishWeaponHudState('enforce_reapply')
          end
        end
      end
    end

    Wait(1500)
  end
end)

CreateThread(function()
  while true do
    if type(MZClient.InventoryWeapons.authorized) == 'table' then
      updateAuthorizedVisualAmmoFromPed('ammo_visual_update')
      Wait(150)
    else
      Wait(500)
    end
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

AddEventHandler('onClientResourceStart', function(resourceName)
  if resourceName == 'mz_hud' or resourceName == GetCurrentResourceName() then
    publishWeaponHudState('hud_start')
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
