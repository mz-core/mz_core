MZPlayerStateClient = MZPlayerStateClient or {}

local SYNC_EVENT = 'mz_core:client:playerStateSync'
local RESYNC_EVENT = 'mz_core:server:requestPlayerStateSync'
local OBSERVATION_EVENT = 'mz_core:server:reportVitalCandidate'
local DEATH_STATES = { alive = true, downed = true, dead = true, respawning = true }

local mirror = {
  loaded = false,
  revision = -1,
  sessionToken = nil,
  expectedSessionToken = nil,
  observationToken = nil,
  snapshot = nil,
  applying = false,
  generation = 0,
  physicalReady = false,
  acceptNextSession = true,
  lastAppliedPed = nil,
  lastAppliedRevision = -1,
  lastReviveRevision = -1,
  pendingPreviousDeathState = nil,
  sequence = 0,
  lastReportAt = 0,
  lastFatalReportAt = 0,
  ignoreObservationUntil = 0,
  lastLogAt = {}
}

local function config()
  return Config and Config.PlayerStates or {}
end

local function nowMs()
  if type(GetGameTimer) == 'function' then return GetGameTimer() end
  return 0
end

local function clone(value)
  if type(value) ~= 'table' then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = clone(child) end
  return result
end

local function finite(value)
  return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function boundedInteger(value, minimum, maximum)
  return finite(value) and value == math.floor(value) and value >= minimum and value <= maximum
end

local function logLimited(code, message, cooldown)
  local current = nowMs()
  cooldown = tonumber(cooldown) or 3000
  if mirror.lastLogAt[code] and current - mirror.lastLogAt[code] < cooldown then return end
  mirror.lastLogAt[code] = current
  print(('[mz_core][player_state][client][%s] %s'):format(tostring(code), tostring(message)))
end

local function validatePayload(payload)
  if type(payload) ~= 'table' then return nil, 'payload_not_table' end
  if not boundedInteger(payload.revision, 0, 2147483647) then return nil, 'invalid_revision' end
  if type(payload.sessionToken) ~= 'string' or payload.sessionToken == '' or #payload.sessionToken > 96 then
    return nil, 'invalid_session'
  end
  if type(payload.observationToken) ~= 'string' or payload.observationToken == '' or #payload.observationToken > 96 then
    return nil, 'invalid_observation_token'
  end
  if type(payload.status) ~= 'table' then return nil, 'invalid_status' end
  local definitions = config().status or {}
  local status = {}
  for _, name in ipairs({ 'hunger', 'thirst', 'stress', 'health', 'armor' }) do
    local definition = definitions[name]
    local value = payload.status[name]
    if type(definition) ~= 'table' or not boundedInteger(value, definition.min, definition.max) then
      return nil, 'invalid_status_' .. name
    end
    status[name] = value
  end
  if type(payload.death) ~= 'table' or DEATH_STATES[payload.death.state] ~= true then
    return nil, 'invalid_death_state'
  end
  local legacyDead = payload.death.state == 'dead' or payload.death.state == 'respawning'
  local legacyDowned = payload.death.state == 'downed'
  if payload.death.isdead ~= legacyDead or payload.death.inlaststand ~= legacyDowned then
    return nil, 'incoherent_death_flags'
  end
  for _, field in ipairs({ 'downedAt', 'downedExpiresAt', 'deadAt', 'respawnAvailableAt' }) do
    local value = payload.death[field]
    if value ~= nil and not boundedInteger(value, 0, 2147483647) then
      return nil, 'invalid_death_timestamp_' .. field
    end
  end
  if type(payload.permissions) ~= 'table'
    or type(payload.permissions.inventoryBlocked) ~= 'boolean'
    or type(payload.permissions.weaponBlocked) ~= 'boolean'
    or type(payload.permissions.interactionBlocked) ~= 'boolean' then
    return nil, 'invalid_permissions'
  end
  local shouldBlock = payload.death.state ~= 'alive'
  if payload.permissions.inventoryBlocked ~= shouldBlock
    or payload.permissions.weaponBlocked ~= shouldBlock
    or payload.permissions.interactionBlocked ~= shouldBlock then
    return nil, 'incoherent_permissions'
  end
  if type(payload.reason) ~= 'table' or type(payload.reason.code) ~= 'string'
    or payload.reason.code == '' or #payload.reason.code > 64 then
    return nil, 'invalid_reason'
  end
  if payload.forcePhysicalApply ~= nil and type(payload.forcePhysicalApply) ~= 'boolean' then
    return nil, 'invalid_force_flag'
  end
  if payload.sessionReset ~= nil and type(payload.sessionReset) ~= 'boolean' then
    return nil, 'invalid_session_reset_flag'
  end
  return {
    revision = payload.revision,
    sessionToken = payload.sessionToken,
    observationToken = payload.observationToken,
    status = status,
    death = {
      state = payload.death.state,
      isdead = payload.death.isdead,
      inlaststand = payload.death.inlaststand,
      downedAt = payload.death.downedAt,
      downedExpiresAt = payload.death.downedExpiresAt,
      deadAt = payload.death.deadAt,
      respawnAvailableAt = payload.death.respawnAvailableAt
    },
    permissions = {
      inventoryBlocked = payload.permissions.inventoryBlocked,
      weaponBlocked = payload.permissions.weaponBlocked,
      interactionBlocked = payload.permissions.interactionBlocked
    },
    reason = { code = payload.reason.code, serverTime = payload.reason.serverTime },
    forcePhysicalApply = payload.forcePhysicalApply == true,
    sessionReset = payload.sessionReset == true
  }
end

local function isCurrent(generation, snapshot)
  return mirror.generation == generation
    and mirror.snapshot == snapshot
    and mirror.revision == snapshot.revision
    and mirror.sessionToken == snapshot.sessionToken
end

local function validPed(ped)
  return ped and ped ~= 0
    and type(DoesEntityExist) == 'function' and DoesEntityExist(ped)
    and (type(IsEntityAPed) ~= 'function' or IsEntityAPed(ped))
end

local function waitForPed(generation, snapshot)
  local timeout = tonumber(config().sync and config().sync.pedReadyTimeoutMs) or 10000
  local waited = 0
  while waited <= timeout do
    if not isCurrent(generation, snapshot) then return nil, 'superseded' end
    local active = type(NetworkIsPlayerActive) ~= 'function'
      or type(PlayerId) ~= 'function'
      or NetworkIsPlayerActive(PlayerId())
    local ped = type(PlayerPedId) == 'function' and PlayerPedId() or nil
    if mirror.physicalReady and active and validPed(ped) then return ped end
    if type(Wait) ~= 'function' then break end
    Wait(50)
    waited = waited + 50
  end
  return nil, 'ped_ready_timeout'
end

local function canonicalToPhysicalHealth(canonical, pedMax)
  local canonicalMax = tonumber(config().status and config().status.health and config().status.health.max) or 200
  pedMax = math.max(1, math.floor(tonumber(pedMax) or canonicalMax))
  return math.floor((canonical / canonicalMax) * pedMax + 0.5)
end

local function downedPhysicalHealth(pedMax)
  pedMax = math.max(1, math.floor(tonumber(pedMax) or 200))
  -- Player peds treat the lower half of the native health range as dead.
  -- Canonical last stand remains 1; its physical projection must stay alive.
  return math.min(pedMax, math.floor(pedMax / 2) + 1)
end

local function physicalToCanonicalHealth(physical, pedMax)
  local canonicalMax = tonumber(config().status and config().status.health and config().status.health.max) or 200
  pedMax = math.max(1, math.floor(tonumber(pedMax) or canonicalMax))
  local value = math.floor((math.max(0, physical) / pedMax) * canonicalMax + 0.5)
  return math.max(0, math.min(canonicalMax, value))
end

local function resurrectAtCurrentPosition(ped)
  if type(NetworkResurrectLocalPlayer) ~= 'function' or type(GetEntityCoords) ~= 'function' then return false end
  local coords = GetEntityCoords(ped)
  local heading = type(GetEntityHeading) == 'function' and GetEntityHeading(ped) or 0.0
  NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
  return true
end

local function physicallyDead(ped)
  return (type(IsEntityDead) == 'function' and IsEntityDead(ped))
    or (type(IsPedDeadOrDying) == 'function' and IsPedDeadOrDying(ped, true))
    or (type(GetEntityHealth) == 'function' and GetEntityHealth(ped) <= 0)
end

local function applyPhysicalNow(snapshot, previousDeathState, generation, suppliedPed)
  local ped = suppliedPed or waitForPed(generation, snapshot)
  if not ped then return false, 'ped_ready_timeout' end
  if not isCurrent(generation, snapshot) then return false, 'superseded' end

  mirror.applying = true
  local deathState = snapshot.death.state
  local officialRevive = deathState == 'alive'
    and previousDeathState ~= nil and previousDeathState ~= 'alive'
    and mirror.lastReviveRevision ~= snapshot.revision

  if officialRevive and physicallyDead(ped) then
    if not resurrectAtCurrentPosition(ped) then
      mirror.applying = false
      return false, 'revive_native_unavailable'
    end
    mirror.lastReviveRevision = snapshot.revision
    ped = type(PlayerPedId) == 'function' and PlayerPedId() or ped
  elseif deathState == 'downed' and physicallyDead(ped) then
    if not resurrectAtCurrentPosition(ped) then
      mirror.applying = false
      return false, 'downed_recovery_failed'
    end
    ped = type(PlayerPedId) == 'function' and PlayerPedId() or ped
  end

  if not validPed(ped) or not isCurrent(generation, snapshot) then
    mirror.applying = false
    return false, 'superseded'
  end

  if deathState == 'dead' or deathState == 'respawning' then
    if type(SetPedArmour) == 'function' then SetPedArmour(ped, 0) end
    if type(SetEntityHealth) == 'function' and GetEntityHealth(ped) > 0 then SetEntityHealth(ped, 0) end
  else
    local canonicalMax = tonumber(config().status and config().status.health and config().status.health.max) or 200
    local pedMax = type(GetEntityMaxHealth) == 'function' and tonumber(GetEntityMaxHealth(ped)) or canonicalMax
    if not pedMax or pedMax < canonicalMax then
      if type(SetEntityMaxHealth) == 'function' then SetEntityMaxHealth(ped, canonicalMax) end
      pedMax = canonicalMax
    end
    local canonicalHealth = snapshot.status.health
    if deathState == 'downed' then
      canonicalHealth = tonumber(config().death and config().death.downedHealth) or 1
    else
      canonicalHealth = math.max(tonumber(config().sync and config().sync.aliveMinHealth) or 1, canonicalHealth)
    end
    local physicalHealth = deathState == 'downed'
      and downedPhysicalHealth(pedMax) or canonicalToPhysicalHealth(canonicalHealth, pedMax)
    if type(SetEntityHealth) == 'function' then SetEntityHealth(ped, math.max(1, physicalHealth)) end
    local armor = deathState == 'alive' and snapshot.status.armor or 0
    if type(SetPedArmour) == 'function' then SetPedArmour(ped, math.max(0, math.min(100, armor))) end
  end

  if officialRevive then
    if type(ClearPedTasksImmediately) == 'function' then ClearPedTasksImmediately(ped) end
    if type(ClearPedBloodDamage) == 'function' then ClearPedBloodDamage(ped) end
    if type(ResetPedVisibleDamage) == 'function' then ResetPedVisibleDamage(ped) end
  end

  if not isCurrent(generation, snapshot) then
    mirror.applying = false
    return false, 'superseded'
  end
  mirror.lastAppliedPed = ped
  mirror.lastAppliedRevision = snapshot.revision
  mirror.pendingPreviousDeathState = nil
  mirror.ignoreObservationUntil = nowMs() + 500
  mirror.applying = false

  if deathState == 'alive' then
    local actualHealth = type(GetEntityHealth) == 'function' and GetEntityHealth(ped) or nil
    local actualArmor = type(GetPedArmour) == 'function' and GetPedArmour(ped) or nil
    local pedMax = type(GetEntityMaxHealth) == 'function' and GetEntityMaxHealth(ped) or 200
    local expectedHealth = canonicalToPhysicalHealth(snapshot.status.health, pedMax)
    local healthTolerance = tonumber(config().reconciliation and config().reconciliation.healthTolerance) or 2
    local armorTolerance = tonumber(config().reconciliation and config().reconciliation.armorTolerance) or 1
    if actualHealth and math.abs(actualHealth - expectedHealth) > healthTolerance then
      logLimited('health_apply_mismatch', ('revision=%s expected=%s actual=%s'):format(snapshot.revision, expectedHealth, actualHealth))
    end
    if actualArmor and math.abs(actualArmor - snapshot.status.armor) > armorTolerance then
      logLimited('armor_apply_mismatch', ('revision=%s expected=%s actual=%s'):format(snapshot.revision, snapshot.status.armor, actualArmor))
    end
  end
  return true
end

local function scheduleApply(snapshot, previousDeathState)
  if not mirror.physicalReady then return end
  local generation = mirror.generation
  if type(CreateThread) ~= 'function' then return end
  CreateThread(function()
    local ok, err = applyPhysicalNow(snapshot, previousDeathState, generation)
    if not ok and err ~= 'superseded' then
      mirror.applying = false
      logLimited(err, ('revision=%s reason=%s'):format(snapshot.revision, snapshot.reason.code))
    end
  end)
end

function MZPlayerStateClient.receivePayload(payload)
  local snapshot, validationErr = validatePayload(payload)
  if not snapshot then
    logLimited('payload_rejected', validationErr)
    return false, validationErr
  end
  if mirror.expectedSessionToken and snapshot.sessionToken ~= mirror.expectedSessionToken then
    logLimited('stale_session', snapshot.sessionToken)
    return false, 'stale_session'
  end
  if mirror.sessionToken and snapshot.sessionToken ~= mirror.sessionToken then
    if not mirror.acceptNextSession then
      logLimited('stale_session', snapshot.sessionToken)
      return false, 'stale_session'
    end
    mirror.revision = -1
    mirror.sequence = 0
    mirror.snapshot = nil
    mirror.pendingPreviousDeathState = nil
  end
  if snapshot.revision < mirror.revision then return false, 'stale_revision' end
  if snapshot.revision == mirror.revision and snapshot.forcePhysicalApply ~= true then
    return true, 'idempotent'
  end

  local logicalRevisionChanged = snapshot.revision > mirror.revision
  local previousDeathState = mirror.snapshot and mirror.snapshot.death.state or nil
  mirror.loaded = true
  mirror.sessionToken = snapshot.sessionToken
  mirror.observationToken = snapshot.observationToken
  mirror.revision = snapshot.revision
  mirror.snapshot = snapshot
  mirror.acceptNextSession = false
  mirror.expectedSessionToken = nil
  mirror.generation = mirror.generation + 1
  if logicalRevisionChanged then
    mirror.pendingPreviousDeathState = previousDeathState
  end
  scheduleApply(snapshot, previousDeathState)
  return true, snapshot.forcePhysicalApply and 'physical_reapply' or 'applied'
end

function MZPlayerStateClient.getSnapshot()
  if not mirror.snapshot then return nil end
  return clone({
    revision = mirror.snapshot.revision,
    status = mirror.snapshot.status,
    death = mirror.snapshot.death,
    permissions = mirror.snapshot.permissions,
    reason = mirror.snapshot.reason
  })
end

function MZPlayerStateClient.getDeathState()
  return mirror.snapshot and mirror.snapshot.death.state or 'alive'
end

function MZPlayerStateClient.canPerformAction(action)
  local snapshot = mirror.snapshot
  if not mirror.loaded or not snapshot then return false end
  action = tostring(action or '')
  if action:find('^inventory%.') then return snapshot.permissions.inventoryBlocked ~= true end
  if action:find('^weapon%.') then return snapshot.permissions.weaponBlocked ~= true end
  return snapshot.permissions.interactionBlocked ~= true
end

function MZPlayerStateClient.requestResync(reason)
  if type(TriggerServerEvent) ~= 'function' then return false end
  logLimited('resync_requested', tostring(reason or 'manual'), 1000)
  TriggerServerEvent(RESYNC_EVENT)
  return true
end

function MZPlayerStateClient.notifyPedReady(reason)
  mirror.physicalReady = true
  local snapshot = mirror.snapshot
  if not snapshot then return false end
  mirror.generation = mirror.generation + 1
  scheduleApply(snapshot, mirror.pendingPreviousDeathState or snapshot.death.state)
  return true
end

local function resetForPlayerLoad(expectedSessionToken)
  mirror.loaded = false
  mirror.revision = -1
  mirror.sessionToken = nil
  mirror.expectedSessionToken = type(expectedSessionToken) == 'string' and expectedSessionToken or nil
  mirror.observationToken = nil
  mirror.snapshot = nil
  mirror.applying = false
  mirror.physicalReady = false
  mirror.acceptNextSession = true
  mirror.lastAppliedPed = nil
  mirror.lastAppliedRevision = -1
  mirror.lastReviveRevision = -1
  mirror.pendingPreviousDeathState = nil
  mirror.sequence = 0
  mirror.generation = mirror.generation + 1
end

local function sendObservation(observedHealth, observedArmor, observedDead)
  local snapshot = mirror.snapshot
  if not mirror.loaded or not snapshot or mirror.applying or nowMs() < mirror.ignoreObservationUntil then return false end
  local current = nowMs()
  local reconciliation = config().reconciliation or {}
  if observedDead == true then
    local interval = tonumber(reconciliation.fatalReportIntervalMs) or 1000
    if current - mirror.lastFatalReportAt < interval then return false end
    mirror.lastFatalReportAt = current
  else
    local debounce = tonumber(reconciliation.reportDebounceMs) or 1000
    if current - mirror.lastReportAt < debounce then return false end
    mirror.lastReportAt = current
  end
  mirror.sequence = mirror.sequence + 1
  local payload = {
    sessionToken = mirror.sessionToken,
    observationToken = mirror.observationToken,
    sequence = mirror.sequence,
    localRevision = mirror.revision,
    observedDead = observedDead == true
  }
  if observedHealth ~= nil then payload.observedHealth = math.floor(observedHealth) end
  if observedArmor ~= nil then payload.observedArmor = math.floor(observedArmor) end
  TriggerServerEvent(OBSERVATION_EVENT, payload)
  return true
end

local function reconcile(reason)
  local snapshot = mirror.snapshot
  if not mirror.loaded or not mirror.physicalReady or not snapshot or mirror.applying
    or nowMs() < mirror.ignoreObservationUntil then return false end
  local ped = type(PlayerPedId) == 'function' and PlayerPedId() or nil
  if not validPed(ped) then return false end
  if mirror.lastAppliedPed and mirror.lastAppliedPed ~= ped then
    logLimited('model_reset_detected', tostring(reason or 'reconcile'))
    return MZPlayerStateClient.notifyPedReady('model_reset_detected')
  end

  local deathState = snapshot.death.state
  local dead = physicallyDead(ped)
  if deathState == 'alive' and dead then
    logLimited('ped_dead_canonical_alive', ('revision=%s'):format(snapshot.revision))
    return sendObservation(0, type(GetPedArmour) == 'function' and GetPedArmour(ped) or nil, true)
  end
  if (deathState == 'dead' or deathState == 'respawning') and not dead then
    logLimited('ped_alive_canonical_' .. deathState, ('revision=%s'):format(snapshot.revision))
    return MZPlayerStateClient.notifyPedReady('canonical_' .. deathState .. '_reapply')
  end
  if deathState == 'downed' then
    local pedMax = type(GetEntityMaxHealth) == 'function' and GetEntityMaxHealth(ped) or 200
    local expected = downedPhysicalHealth(pedMax)
    if dead or (type(GetEntityHealth) == 'function' and GetEntityHealth(ped) > expected + 1) then
      return MZPlayerStateClient.notifyPedReady('downed_reapply')
    end
    return false
  end
  if deathState ~= 'alive' then return false end

  local pedMax = type(GetEntityMaxHealth) == 'function' and GetEntityMaxHealth(ped) or 200
  local physicalHealth = type(GetEntityHealth) == 'function' and GetEntityHealth(ped) or nil
  local physicalArmor = type(GetPedArmour) == 'function' and GetPedArmour(ped) or nil
  local observedHealth = physicalHealth and physicalToCanonicalHealth(physicalHealth, pedMax) or nil
  local healthTolerance = tonumber(config().reconciliation and config().reconciliation.healthTolerance) or 2
  local armorTolerance = tonumber(config().reconciliation and config().reconciliation.armorTolerance) or 1
  local healthDelta = observedHealth and snapshot.status.health - observedHealth or 0
  local armorDelta = physicalArmor and snapshot.status.armor - physicalArmor or 0
  if healthDelta > healthTolerance or armorDelta > armorTolerance then
    return sendObservation(
      healthDelta > healthTolerance and observedHealth or nil,
      armorDelta > armorTolerance and physicalArmor or nil,
      false
    )
  end
  if healthDelta < -healthTolerance or armorDelta < -armorTolerance then
    logLimited('positive_vital_divergence', ('revision=%s reason=%s'):format(snapshot.revision, tostring(reason)))
    return MZPlayerStateClient.notifyPedReady('positive_vital_divergence')
  end
  return false
end

if type(RegisterNetEvent) == 'function' then
  RegisterNetEvent(SYNC_EVENT, function(payload) MZPlayerStateClient.receivePayload(payload) end)
  RegisterNetEvent('mz_core:client:playerLoaded', function(_, expectedSessionToken)
    resetForPlayerLoad(expectedSessionToken)
  end)
end

if type(AddEventHandler) == 'function' then
  AddEventHandler('playerSpawned', function() MZPlayerStateClient.notifyPedReady('player_spawned') end)
  AddEventHandler('mz_core:client:pedModelReady', function(details)
    local reason = type(details) == 'table' and details.reason or 'ped_model_ready'
    MZPlayerStateClient.notifyPedReady(reason)
  end)
  AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or not mirror.loaded or mirror.applying then return end
    local ped = type(PlayerPedId) == 'function' and PlayerPedId() or nil
    if type(args) ~= 'table' or args[1] ~= ped then return end
    if type(CreateThread) == 'function' then
      CreateThread(function()
        if type(Wait) == 'function' then Wait(100) end
        reconcile('damage_event')
      end)
    end
  end)
  AddEventHandler('onClientResourceStart', function(resourceName)
    if type(GetCurrentResourceName) ~= 'function' or resourceName ~= GetCurrentResourceName() then return end
    if type(CreateThread) == 'function' then
      CreateThread(function()
        local waited = 0
        local timeout = tonumber(config().sync and config().sync.pedReadyTimeoutMs) or 10000
        while waited <= timeout do
          local active = type(NetworkIsPlayerActive) ~= 'function' or NetworkIsPlayerActive(PlayerId())
          local ped = type(PlayerPedId) == 'function' and PlayerPedId() or nil
          if active and validPed(ped) then
            mirror.physicalReady = true
            MZPlayerStateClient.requestResync('client_resource_start')
            local retryAfter = tonumber(config().sync and config().sync.resyncCooldownMs) or 5000
            Wait(retryAfter + 250)
            if not mirror.loaded then
              MZPlayerStateClient.requestResync('client_resource_start_retry')
            end
            return
          end
          Wait(100)
          waited = waited + 100
        end
        logLimited('resource_start_ped_timeout', tostring(timeout))
      end)
    end
  end)
end

if type(CreateThread) == 'function' then
  CreateThread(function()
    local lastForcedVehicleExitAt = 0
    while true do
      if mirror.loaded and mirror.snapshot and mirror.snapshot.permissions.interactionBlocked then
        local ped = type(PlayerPedId) == 'function' and PlayerPedId() or nil
        if ped and type(DisablePlayerFiring) == 'function' and type(PlayerId) == 'function' then
          DisablePlayerFiring(PlayerId(), true)
        end
        for _, control in ipairs({ 23, 24, 25, 27, 37, 38, 51, 71, 72, 75, 157, 158, 159, 160, 161, 162, 163, 164 }) do
          DisableControlAction(0, control, true)
        end
        local now = type(GetGameTimer) == 'function' and GetGameTimer() or 0
        if ped and type(IsPedInAnyVehicle) == 'function' and IsPedInAnyVehicle(ped, false)
          and type(GetVehiclePedIsIn) == 'function' and type(GetPedInVehicleSeat) == 'function'
          and type(TaskLeaveVehicle) == 'function' and now - lastForcedVehicleExitAt >= 1500 then
          local vehicle = GetVehiclePedIsIn(ped, false)
          if vehicle and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            lastForcedVehicleExitAt = now
            TaskLeaveVehicle(ped, vehicle, 16)
          end
        end
        Wait(0)
      else
        Wait(500)
      end
    end
  end)

  CreateThread(function()
    while true do
      local interval = tonumber(config().reconciliation and config().reconciliation.intervalMs) or 3000
      Wait(math.max(1000, interval))
      if config().reconciliation == nil or config().reconciliation.enabled ~= false then
        reconcile('periodic')
      end
    end
  end)
end

exports('GetLocalPlayerState', function() return MZPlayerStateClient.getSnapshot() end)
exports('GetLocalPlayerStateEnvelope', function()
  local invokingResource = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil
  if invokingResource ~= 'mz_medical' or not mirror.loaded or not mirror.sessionToken then return nil end
  return { sessionToken = mirror.sessionToken, revision = mirror.revision }
end)
exports('GetLocalDeathState', function() return MZPlayerStateClient.getDeathState() end)
exports('IsLocalPlayerDead', function() return MZPlayerStateClient.getDeathState() == 'dead' end)
exports('IsLocalPlayerDowned', function() return MZPlayerStateClient.getDeathState() == 'downed' end)
exports('CanLocalPlayerPerformAction', function(action) return MZPlayerStateClient.canPerformAction(action) end)
exports('RequestPlayerStateResync', function(reason) return MZPlayerStateClient.requestResync(reason) end)

if rawget(_G, 'MZ_PLAYER_STATE_CLIENT_TESTING') == true then
  MZPlayerStateClient._test = {
    mirror = mirror,
    validatePayload = validatePayload,
    applyPhysicalNow = applyPhysicalNow,
    reconcile = reconcile,
    reset = resetForPlayerLoad,
    physicalToCanonicalHealth = physicalToCanonicalHealth,
    canonicalToPhysicalHealth = canonicalToPhysicalHealth,
    downedPhysicalHealth = downedPhysicalHealth
  }
end
