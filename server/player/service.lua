MZPlayerService = {}

local CORE_READY_WAIT_STEP_MS = 50
local CORE_READY_WAIT_TIMEOUT_MS = 15000
local LOAD_IN_FLIGHT_WAIT_TIMEOUT_MS = 15000
local LoadInFlightBySource = {}

local function getLicense(source)
  for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
    if identifier:find('license:') == 1 then
      return identifier
    end
  end
  return nil
end

local function buildPlayerData(source, row, account)
  return {
    source = source,
    license = row.license,
    citizenid = row.citizenid,
    charinfo = {
      firstname = row.firstname,
      lastname = row.lastname,
      birthdate = row.birthdate,
      gender = row.gender,
      nationality = row.nationality,
      phone = row.phone
    },
    metadata = MZUtils.jsonDecode(row.metadata, Config.Player.defaultMetadata),
    money = {
      wallet = account and account.wallet or 0,
      bank = account and account.bank or 0,
      dirty = account and account.dirty or 0
    },
    orgs = {},
    job = nil,
    gang = nil,
    state = {
      loaded = true,
      loadedAt = os.time(),
      lastSeenAt = os.time()
    },
    session = nil
  }
end

local function buildSessionData(source, player, sessionRow)
  if not sessionRow then return nil end

  return {
    id = sessionRow.id,
    source = source,
    citizenid = player.citizenid,
    license = player.license,
    joinedAt = sessionRow.joined_at,
    lastSeenAt = sessionRow.last_seen_at,
    droppedAt = sessionRow.dropped_at,
    disconnectReason = sessionRow.disconnect_reason,
    sessionSeconds = sessionRow.session_seconds or 0,
    isActive = sessionRow.is_active == 1
  }
end

local function refreshSessionState(player, sessionRow)
  if not player then return end

  player.state = player.state or {}
  player.state.loaded = true
  player.state.loadedAt = player.state.loadedAt or os.time()
  player.state.lastSeenAt = os.time()
  player.session = buildSessionData(player.source, player, sessionRow)
end

local function waitForCoreReady(timeoutMs)
  if not MZCoreState or MZCoreState.ready == true then
    return true
  end

  local waited = 0
  local maxWait = tonumber(timeoutMs) or CORE_READY_WAIT_TIMEOUT_MS

  while true do
    if MZCoreState and MZCoreState.ready == true then
      return true
    end

    if MZCoreState and MZCoreState.prepareDone == true and MZCoreState.prepareOk ~= true then
      return false, 'core_prepare_failed'
    end

    if MZCoreState and MZCoreState.seedDone == true and MZCoreState.seedOk ~= true then
      return false, 'core_seed_failed'
    end

    if waited >= maxWait then
      return false, 'core_not_ready'
    end

    Wait(CORE_READY_WAIT_STEP_MS)
    waited = waited + CORE_READY_WAIT_STEP_MS
  end
end

local function waitForLoadInFlight(source, timeoutMs)
  local waited = 0
  local maxWait = tonumber(timeoutMs) or LOAD_IN_FLIGHT_WAIT_TIMEOUT_MS

  while LoadInFlightBySource[source] == true do
    if waited >= maxWait then
      return false, 'load_player_timeout'
    end

    Wait(CORE_READY_WAIT_STEP_MS)
    waited = waited + CORE_READY_WAIT_STEP_MS
  end

  local cached = MZCache.playersBySource[source]
  if cached then
    MZPlayerService.touchPlayer(source)
    return true, cached
  end

  return false, 'load_player_failed'
end

function MZPlayerService.loadPlayer(source)
  local cached = MZCache.playersBySource[source]
  if cached then
    MZPlayerService.touchPlayer(source)
    return cached
  end

  local readyOk, readyErr = waitForCoreReady(CORE_READY_WAIT_TIMEOUT_MS)
  if not readyOk then
    return nil, readyErr
  end

  cached = MZCache.playersBySource[source]
  if cached then
    MZPlayerService.touchPlayer(source)
    return cached
  end

  if LoadInFlightBySource[source] == true then
    local waitOk, resultOrErr = waitForLoadInFlight(source, LOAD_IN_FLIGHT_WAIT_TIMEOUT_MS)
    if waitOk then
      return resultOrErr
    end

    return nil, resultOrErr
  end

  LoadInFlightBySource[source] = true

  local ok, playerData, err = xpcall(function()
    local license = getLicense(source)
    if not license then
      return nil, 'missing_license'
    end

    local row = MZPlayerRepository.getByLicense(license)
    if not row then
      local citizenid
      repeat
        citizenid = MZUtils.generateCitizenId()
      until not MZPlayerRepository.getByCitizenId(citizenid)

      row = MZPlayerRepository.create({
        license = license,
        citizenid = citizenid,
        metadata = Config.Player.defaultMetadata
      })
    end

    MZPlayerRepository.ensureAccount(row.citizenid)
    local account = MZPlayerRepository.getAccount(row.citizenid)
    local playerData = buildPlayerData(source, row, account)

    MZPlayerRepository.closeActiveSessionsByCitizenId(row.citizenid, 'replaced_by_new_load')

    local sessionRow = MZPlayerRepository.createSession({
      citizenid = row.citizenid,
      license = license,
      source = source
    })

    refreshSessionState(playerData, sessionRow)

    MZCache.playersBySource[source] = playerData
    MZCache.playersByCitizenId[playerData.citizenid] = playerData

    MZLogService.createDetailed('player', 'loaded', {
      actor = MZLogService.makeActor('player', playerData.citizenid, {
        source = source,
        license = playerData.license
      }),
      target = MZLogService.makeTarget('session', sessionRow and sessionRow.id or 'unknown', {
        citizenid = playerData.citizenid
      }),
      context = {
        source = source,
        license = playerData.license
      },
      after = {
        state = playerData.state,
        session = playerData.session
      },
      meta = {
        event = 'load_player'
      }
    })

    return playerData
  end, debug.traceback)

  LoadInFlightBySource[source] = nil

  if not ok then
    print(('[mz_core] loadPlayer failed for source %s: %s'):format(tostring(source), tostring(playerData)))
    return nil, 'load_player_failed'
  end

  return playerData, err
end

function MZPlayerService.touchPlayer(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false end

  player.state = player.state or {}
  player.state.lastSeenAt = os.time()

  if player.session and player.session.id then
    MZPlayerRepository.touchSession(player.session.id, source)
    player.session.lastSeenAt = os.date('!%Y-%m-%d %H:%M:%S')
  end

  return true
end

function MZPlayerService.getPlayer(source)
  return MZCache.playersBySource[source]
end

function MZPlayerService.getPlayerByCitizenId(citizenid)
  return MZCache.playersByCitizenId[citizenid]
end

function MZPlayerService.getSourceByCitizenId(citizenid)
  local player = MZCache.playersByCitizenId[citizenid]
  return player and player.source or nil
end

function MZPlayerService.getPlayerSession(source)
  local player = MZPlayerService.getPlayer(source)
  return player and player.session or nil
end

function MZPlayerService.isPlayerLoaded(source)
  local player = MZPlayerService.getPlayer(source)
  return player ~= nil and player.state ~= nil and player.state.loaded == true
end

function MZPlayerService.setMetadataValue(source, key, value)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, 'player_not_loaded' end
  if type(key) ~= 'string' or key == '' then return false, 'invalid_key' end

  player.metadata = player.metadata or {}
  player.metadata[key] = value
  MZPlayerRepository.updateMetadata(player.citizenid, player.metadata)
  MZPlayerService.touchPlayer(source)
  return true, player.metadata
end

function MZPlayerService.getMetadataValue(source, key)
  local player = MZPlayerService.getPlayer(source)
  if not player then return nil end
  MZPlayerService.touchPlayer(source)
  return player.metadata and player.metadata[key] or nil
end

function MZPlayerService.setCharinfo(source, charinfo)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, 'player_not_loaded' end

  player.charinfo = player.charinfo or {}
  for _, field in ipairs({ 'firstname', 'lastname', 'birthdate', 'gender', 'nationality', 'phone' }) do
    if charinfo[field] ~= nil then
      player.charinfo[field] = charinfo[field]
    end
  end

  MZPlayerRepository.updateCharinfo(player.citizenid, player.charinfo)
  MZPlayerService.touchPlayer(source)
  return true, player.charinfo
end

function MZPlayerService.unloadPlayer(source, reason)
  local player = MZCache.playersBySource[source]
  if not player then return end

  local sessionId = player.session and player.session.id or nil
  local before = {
    state = player.state,
    session = player.session
  }

  if sessionId then
    MZPlayerRepository.closeSession(sessionId, reason or '')
    local closedSession = MZPlayerRepository.getSessionById(sessionId)
    if closedSession then
      player.session = buildSessionData(source, player, closedSession)
    end
  end

  player.state = player.state or {}
  player.state.loaded = false
  player.state.lastSeenAt = os.time()

  MZLogService.createDetailed('player', 'unloaded', {
    actor = MZLogService.makeActor('player', player.citizenid, {
      source = source,
      license = player.license
    }),
    target = MZLogService.makeTarget('session', sessionId or 'unknown', {
      citizenid = player.citizenid
    }),
    context = {
      source = source,
      reason = reason or ''
    },
    before = before,
    after = {
      state = player.state,
      session = player.session
    },
    meta = {
      event = 'unload_player'
    }
  })

  MZCache.playersByCitizenId[player.citizenid] = nil
  MZCache.playersBySource[source] = nil
end


function MZPlayerService.getLastPosition(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then return nil end

  local row = MZPlayerRepository.getByCitizenId(player.citizenid)
  if not row then return nil end

  if not row.pos_x or not row.pos_y or not row.pos_z then
    return nil
  end

  if tonumber(row.pos_x) == 0 and tonumber(row.pos_y) == 0 and tonumber(row.pos_z) == 0 then
    return nil
  end

  return {
    x = tonumber(row.pos_x),
    y = tonumber(row.pos_y),
    z = tonumber(row.pos_z),
    heading = tonumber(row.heading or 0.0)
  }
end

function MZPlayerService.savePosition(source, coords)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, 'player_not_loaded' end
  if type(coords) ~= 'table' then return false, 'invalid_coords' end

  local x = tonumber(coords.x)
  local y = tonumber(coords.y)
  local z = tonumber(coords.z)
  local heading = tonumber(coords.heading or 0.0)

  if not x or not y or not z then
    return false, 'invalid_coords'
  end

  MZPlayerRepository.updatePosition(player.citizenid, {
    x = x,
    y = y,
    z = z,
    heading = heading
  })

  return true
end
