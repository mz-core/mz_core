MZCoreState = MZCoreState or {}
MZCoreState.prepareDone = false
MZCoreState.prepareOk = false
MZCoreState.seedDone = false
MZCoreState.seedOk = false
MZCoreState.ready = false
MZCoreState.prepareStage = 'file_loaded'
MZCoreState.prepareError = nil

print('[mz_core][prepare] file loaded')

local PREPARE_WATCHDOG_TIMEOUT_MS = 120000
local OXMYSQL_READY_TIMEOUT_MS = 15000

local function setPrepareMarker(marker)
  MZCoreState.prepareMarker = marker
  print(('[mz_core][prepare] marker=%s'):format(tostring(marker)))
end

local function prepareTraceback(err)
  local message = tostring(err)

  if type(debug) == 'table' and type(debug.traceback) == 'function' then
    return debug.traceback(message, 2)
  end

  return message
end

local function getOxmysqlResourceState()
  if type(GetResourceState) ~= 'function' then
    return 'unknown_get_resource_state_missing'
  end

  local ok, state = pcall(GetResourceState, 'oxmysql')
  if not ok then
    return ('error:%s'):format(tostring(state))
  end

  return tostring(state)
end

local function getMySQLDiagnostics()
  local queryType = MySQL and type(MySQL.query) or 'nil'
  local singleType = MySQL and type(MySQL.single) or 'nil'
  local insertType = MySQL and type(MySQL.insert) or 'nil'
  local queryAwaitType = queryType == 'table' and type(MySQL.query.await) or 'nil'
  local singleAwaitType = singleType == 'table' and type(MySQL.single.await) or 'nil'
  local insertAwaitType = insertType == 'table' and type(MySQL.insert.await) or 'nil'

  return ('mysqlType=%s query=%s queryAwait=%s single=%s singleAwait=%s insert=%s insertAwait=%s'):format(
    type(MySQL),
    tostring(queryType),
    tostring(queryAwaitType),
    tostring(singleType),
    tostring(singleAwaitType),
    tostring(insertType),
    tostring(insertAwaitType)
  )
end

local function isMySQLReady()
  return MySQL
    and type(MySQL.query) == 'table'
    and type(MySQL.query.await) == 'function'
    and type(MySQL.single) == 'table'
    and type(MySQL.single.await) == 'function'
    and type(MySQL.insert) == 'table'
    and type(MySQL.insert.await) == 'function'
end

local function waitForMySQLReady()
  MZCoreState.prepareStage = 'waiting_oxmysql_resource'
  print(('[mz_core][prepare] waiting oxmysql resource state=%s'):format(getOxmysqlResourceState()))

  local started = GetGameTimer()
  local lastStatusAt = 0

  while getOxmysqlResourceState() ~= 'started' do
    local elapsed = GetGameTimer() - started
    if elapsed - lastStatusAt >= 1000 then
      lastStatusAt = elapsed
      print(('[mz_core][prepare] oxmysql resource not started state=%s elapsedMs=%s'):format(
        getOxmysqlResourceState(),
        tostring(elapsed)
      ))
    end

    if elapsed >= OXMYSQL_READY_TIMEOUT_MS then
      return false, ('oxmysql_resource_not_started state=%s'):format(getOxmysqlResourceState())
    end

    Wait(250)
  end

  MZCoreState.prepareStage = 'waiting_mysql_global'
  print(('[mz_core][prepare] oxmysql resource started; waiting MySQL global %s'):format(getMySQLDiagnostics()))

  while not isMySQLReady() do
    local elapsed = GetGameTimer() - started
    if elapsed - lastStatusAt >= 1000 then
      lastStatusAt = elapsed
      print(('[mz_core][prepare] MySQL global not ready elapsedMs=%s %s'):format(
        tostring(elapsed),
        getMySQLDiagnostics()
      ))
    end

    if elapsed >= OXMYSQL_READY_TIMEOUT_MS then
      if not MySQL or type(MySQL) ~= 'table' then
        return false, ('mysql_global_missing %s'):format(getMySQLDiagnostics())
      end

      if type(MySQL.query) ~= 'table' or type(MySQL.query.await) ~= 'function' then
        return false, ('mysql_await_missing %s'):format(getMySQLDiagnostics())
      end

      return false, ('mysql_not_ready %s'):format(getMySQLDiagnostics())
    end

    Wait(250)
  end

  print(('[mz_core][prepare] MySQL ready %s'):format(getMySQLDiagnostics()))
  return true
end

local statements = {
  [[CREATE TABLE IF NOT EXISTS mz_players (
    id INT AUTO_INCREMENT PRIMARY KEY,
    license VARCHAR(80) NOT NULL,
    citizenid VARCHAR(32) NOT NULL,
    firstname VARCHAR(64) NOT NULL DEFAULT '',
    lastname VARCHAR(64) NOT NULL DEFAULT '',
    birthdate VARCHAR(32) NOT NULL DEFAULT '',
    gender VARCHAR(16) NOT NULL DEFAULT '',
    nationality VARCHAR(64) NOT NULL DEFAULT '',
    phone VARCHAR(32) NOT NULL DEFAULT '',
    metadata LONGTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_players_license (license),
    UNIQUE KEY uq_mz_players_citizenid (citizenid)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_player_accounts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    citizenid VARCHAR(32) NOT NULL,
    wallet BIGINT NOT NULL DEFAULT 0,
    bank BIGINT NOT NULL DEFAULT 0,
    dirty BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_player_accounts_citizenid (citizenid)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_player_sessions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    citizenid VARCHAR(32) NOT NULL,
    license VARCHAR(80) NOT NULL,
    source INT NOT NULL DEFAULT 0,
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    dropped_at TIMESTAMP NULL DEFAULT NULL,
    disconnect_reason VARCHAR(255) NOT NULL DEFAULT '',
    session_seconds INT NOT NULL DEFAULT 0,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    KEY idx_mz_player_sessions_citizenid (citizenid),
    KEY idx_mz_player_sessions_is_active (is_active)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_org_types (
    id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(32) NOT NULL,
    name VARCHAR(64) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_org_types_code (code)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_orgs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    type_id INT NOT NULL,
    code VARCHAR(64) NOT NULL,
    name VARCHAR(128) NOT NULL,
    is_public TINYINT(1) NOT NULL DEFAULT 0,
    requires_whitelist TINYINT(1) NOT NULL DEFAULT 1,
    has_salary TINYINT(1) NOT NULL DEFAULT 1,
    has_shared_account TINYINT(1) NOT NULL DEFAULT 0,
    has_storage TINYINT(1) NOT NULL DEFAULT 0,
    active TINYINT(1) NOT NULL DEFAULT 1,
    config_json LONGTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_orgs_code (code),
    KEY idx_mz_orgs_type_id (type_id)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_org_grades (
    id INT AUTO_INCREMENT PRIMARY KEY,
    org_id INT NOT NULL,
    level INT NOT NULL,
    code VARCHAR(64) NOT NULL,
    name VARCHAR(128) NOT NULL,
    salary BIGINT NOT NULL DEFAULT 0,
    inherits_grade_id INT NULL,
    priority INT NOT NULL DEFAULT 0,
    config_json LONGTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_org_grade_level (org_id, level),
    UNIQUE KEY uq_mz_org_grade_code (org_id, code),
    KEY idx_mz_org_grades_org_id (org_id)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_org_permissions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    org_id INT NOT NULL,
    grade_id INT NULL,
    permission VARCHAR(128) NOT NULL,
    allow TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_org_permissions_unique (org_id, grade_id, permission),
    KEY idx_mz_org_permissions_org_id (org_id),
    KEY idx_mz_org_permissions_grade_id (grade_id)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_player_orgs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    citizenid VARCHAR(32) NOT NULL,
    org_id INT NOT NULL,
    grade_id INT NOT NULL,
    is_primary TINYINT(1) NOT NULL DEFAULT 0,
    active TINYINT(1) NOT NULL DEFAULT 1,
    duty TINYINT(1) NOT NULL DEFAULT 0,
    expires_at TIMESTAMP NULL,
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_player_org_unique (citizenid, org_id),
    KEY idx_mz_player_orgs_citizenid (citizenid),
    KEY idx_mz_player_orgs_org_id (org_id)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_player_permissions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    citizenid VARCHAR(32) NOT NULL,
    permission VARCHAR(128) NOT NULL,
    allow TINYINT(1) NOT NULL DEFAULT 1,
    expires_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_player_permission_unique (citizenid, permission)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_player_vehicles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    owner_type VARCHAR(16) NOT NULL DEFAULT 'player',
    owner_id VARCHAR(64) NOT NULL,
    plate VARCHAR(16) NOT NULL,
    model VARCHAR(64) NOT NULL,
    category VARCHAR(32) NOT NULL DEFAULT 'car',
    garage VARCHAR(64) NOT NULL DEFAULT 'default',
    state VARCHAR(16) NOT NULL DEFAULT 'stored',
    fuel FLOAT NOT NULL DEFAULT 100,
    engine FLOAT NOT NULL DEFAULT 1000,
    body FLOAT NOT NULL DEFAULT 1000,
    props_json LONGTEXT NULL,
    impound_data LONGTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_player_vehicles_plate (plate),
    KEY idx_mz_player_vehicles_owner (owner_type, owner_id)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_vehicle_world_state (
    plate VARCHAR(16) NOT NULL PRIMARY KEY,
    vehicle_id INT NULL,
    state VARCHAR(16) NOT NULL DEFAULT 'out',
    model VARCHAR(64) NOT NULL,
    garage VARCHAR(64) NOT NULL DEFAULT 'default',
    x DOUBLE NOT NULL DEFAULT 0,
    y DOUBLE NOT NULL DEFAULT 0,
    z DOUBLE NOT NULL DEFAULT 0,
    heading FLOAT NOT NULL DEFAULT 0,
    fuel FLOAT NOT NULL DEFAULT 100,
    engine_health FLOAT NOT NULL DEFAULT 1000,
    body_health FLOAT NOT NULL DEFAULT 1000,
    locked TINYINT(1) NOT NULL DEFAULT 0,
    destroyed TINYINT(1) NOT NULL DEFAULT 0,
    props_json LONGTEXT NULL,
    extra_json LONGTEXT NULL,
    net_id INT NOT NULL DEFAULT 0,
    entity_handle INT NOT NULL DEFAULT 0,
    last_seen_at TIMESTAMP NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_mz_vehicle_world_vehicle_id (vehicle_id),
    KEY idx_mz_vehicle_world_state (state),
    KEY idx_mz_vehicle_world_last_seen (last_seen_at)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_inventory_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    owner_type VARCHAR(16) NOT NULL DEFAULT 'player',
    owner_id VARCHAR(64) NOT NULL,
    inventory_type VARCHAR(32) NOT NULL DEFAULT 'main',
    slot INT NOT NULL,
    item VARCHAR(64) NOT NULL,
    amount INT NOT NULL DEFAULT 1,
    metadata LONGTEXT NULL,
    instance_uid VARCHAR(64) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_inventory_slot (owner_type, owner_id, inventory_type, slot),
    UNIQUE KEY uq_mz_inventory_instance_uid (instance_uid),
    KEY idx_mz_inventory_owner (owner_type, owner_id, inventory_type),
    KEY idx_mz_inventory_item (item)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_player_hotbar (
    id INT AUTO_INCREMENT PRIMARY KEY,
    citizenid VARCHAR(32) NOT NULL,
    hotbar_slot INT NOT NULL,
    instance_uid VARCHAR(64) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_player_hotbar_slot (citizenid, hotbar_slot),
    UNIQUE KEY uq_mz_player_hotbar_instance (citizenid, instance_uid),
    KEY idx_mz_player_hotbar_instance_uid (instance_uid)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_org_accounts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    org_id INT NOT NULL,
    balance BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_org_accounts_org_id (org_id)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_org_account_transactions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    org_id BIGINT UNSIGNED NULL,
    org_code VARCHAR(64) NOT NULL,
    type VARCHAR(32) NOT NULL,
    amount BIGINT NOT NULL,
    balance_before BIGINT NOT NULL DEFAULT 0,
    balance_after BIGINT NOT NULL DEFAULT 0,
    actor_citizenid VARCHAR(64) NULL,
    actor_name VARCHAR(120) NULL,
    reason VARCHAR(255) NULL,
    metadata_json LONGTEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_mz_org_acc_tx_org_code (org_code),
    KEY idx_mz_org_acc_tx_type (type),
    KEY idx_mz_org_acc_tx_created_at (created_at)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_org_goals (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    org_code VARCHAR(64) NOT NULL,
    title VARCHAR(120) NOT NULL,
    description TEXT NULL,
    type VARCHAR(32) NOT NULL DEFAULT 'manual',
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    target INT NOT NULL DEFAULT 1,
    progress INT NOT NULL DEFAULT 0,
    starts_at DATETIME NULL,
    ends_at DATETIME NULL,
    created_by_citizenid VARCHAR(64) NULL,
    created_by_name VARCHAR(120) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_mz_org_goals_org_code (org_code),
    KEY idx_mz_org_goals_status (status)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    scope VARCHAR(32) NOT NULL,
    action VARCHAR(64) NOT NULL,
    actor VARCHAR(64) NULL,
    target VARCHAR(64) NULL,
    data_json LONGTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY idx_mz_logs_scope (scope),
    KEY idx_mz_logs_action (action)
  )]]
}

local function runPrepareQuery(label, statement, params)
  MZCoreState.prepareStage = tostring(label or 'unknown')
  print(('[mz_core][prepare] running %s'):format(MZCoreState.prepareStage))

  local ok, result = xpcall(function()
    return MySQL.query.await(statement, params)
  end, prepareTraceback)

  if not ok then
    error(('[%s] %s'):format(tostring(label), tostring(result)), 0)
  end

  return result
end

local function hasColumn(tableName, columnName)
  local label = ('check_column_%s_%s'):format(tostring(tableName), tostring(columnName))
  MZCoreState.prepareStage = label
  print(('[mz_core][prepare] running %s'):format(label))

  local ok, row = xpcall(function()
    return MySQL.single.await([[
      SELECT COUNT(1) AS total
      FROM information_schema.columns
      WHERE table_schema = DATABASE()
        AND table_name = ?
        AND column_name = ?
    ]], { tableName, columnName })
  end, prepareTraceback)

  if not ok then
    error(('[%s] %s'):format(label, tostring(row)), 0)
  end

  return row and tonumber(row.total) and tonumber(row.total) > 0
end

local function ensureColumn(tableName, columnName, definition)
  if hasColumn(tableName, columnName) then
    return
  end

  runPrepareQuery(
    ('add_column_%s_%s'):format(tableName, columnName),
    ('ALTER TABLE `%s` ADD COLUMN %s'):format(tableName, definition)
  )
end

local function runPrepare()
  MZCoreState.prepareStage = 'enter'
  MZCoreState.prepareEnteredXpcall = false
  setPrepareMarker('run_prepare_enter')
  print('[mz_core][prepare] enter runPrepare')

  MZCoreState.prepareStage = 'enter:before_xpcall'
  setPrepareMarker('before_xpcall_marker_1')
  print('[mz_core][prepare] before xpcall marker 1')

  MZCoreState.prepareStage = 'enter:before_xpcall:check_globals'
  setPrepareMarker('before_xpcall_marker_2_check_globals')
  print(('[mz_core][prepare] before xpcall marker 2 xpcallType=%s debugType=%s tracebackType=%s'):format(
    type(xpcall),
    type(debug),
    type(debug) == 'table' and type(debug.traceback) or 'nil'
  ))

  if type(xpcall) ~= 'function' then
    MZCoreState.prepareDone = true
    MZCoreState.prepareOk = false
    MZCoreState.ready = false
    MZCoreState.prepareError = 'xpcall_missing'
    print('[mz_core][prepare] failed before xpcall: xpcall_missing')
    return
  end

  MZCoreState.prepareStage = 'enter:before_xpcall:call'
  setPrepareMarker('before_xpcall_marker_3_call')
  print('[mz_core][prepare] before xpcall marker 3 call')

  local ok, err = xpcall(function()
    MZCoreState.prepareEnteredXpcall = true
    MZCoreState.prepareStage = 'enter:inside_xpcall'
    setPrepareMarker('inside_xpcall_marker_1')
    print('[mz_core][prepare] inside xpcall marker 1')

    MZCoreState.prepareStage = 'enter:wait_mysql_ready'
    print('[mz_core][prepare] enter before waitForMySQLReady')

    local mysqlReady, mysqlErr = waitForMySQLReady()
    MZCoreState.prepareStage = 'enter:mysql_ready_returned'
    print(('[mz_core][prepare] waitForMySQLReady returned ok=%s err=%s'):format(
      tostring(mysqlReady),
      tostring(mysqlErr)
    ))

    if not mysqlReady then
      error(mysqlErr, 0)
    end

    MZCoreState.prepareStage = 'before_first_query'
    print('[mz_core][prepare] before first query')

    for index, statement in ipairs(statements) do
      runPrepareQuery(('statement_%03d'):format(index), statement)
    end

    ensureColumn('mz_players', 'pos_x', 'pos_x DOUBLE NOT NULL DEFAULT 0')
    ensureColumn('mz_players', 'pos_y', 'pos_y DOUBLE NOT NULL DEFAULT 0')
    ensureColumn('mz_players', 'pos_z', 'pos_z DOUBLE NOT NULL DEFAULT 0')
    ensureColumn('mz_players', 'heading', 'heading FLOAT NOT NULL DEFAULT 0')

    -- migração defensiva para bancos antigos
    ensureColumn('mz_inventory_items', 'instance_uid', 'instance_uid VARCHAR(64) NULL')
    ensureColumn('mz_player_vehicles', 'metadata_json', 'metadata_json LONGTEXT NULL')

    runPrepareQuery('ensure_mz_vehicle_world_state', [[
      CREATE TABLE IF NOT EXISTS mz_vehicle_world_state (
        plate VARCHAR(16) NOT NULL PRIMARY KEY,
        vehicle_id INT NULL,
        state VARCHAR(16) NOT NULL DEFAULT 'out',
        model VARCHAR(64) NOT NULL,
        garage VARCHAR(64) NOT NULL DEFAULT 'default',
        x DOUBLE NOT NULL DEFAULT 0,
        y DOUBLE NOT NULL DEFAULT 0,
        z DOUBLE NOT NULL DEFAULT 0,
        heading FLOAT NOT NULL DEFAULT 0,
        fuel FLOAT NOT NULL DEFAULT 100,
        engine_health FLOAT NOT NULL DEFAULT 1000,
        body_health FLOAT NOT NULL DEFAULT 1000,
        locked TINYINT(1) NOT NULL DEFAULT 0,
        destroyed TINYINT(1) NOT NULL DEFAULT 0,
        props_json LONGTEXT NULL,
        extra_json LONGTEXT NULL,
        net_id INT NOT NULL DEFAULT 0,
        entity_handle INT NOT NULL DEFAULT 0,
        last_seen_at TIMESTAMP NULL,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        KEY idx_mz_vehicle_world_vehicle_id (vehicle_id),
        KEY idx_mz_vehicle_world_state (state),
        KEY idx_mz_vehicle_world_last_seen (last_seen_at)
      )
    ]])
    
    runPrepareQuery('ensure_mz_world_drops', [[
      CREATE TABLE IF NOT EXISTS mz_world_drops (
        id INT AUTO_INCREMENT PRIMARY KEY,
        drop_uid VARCHAR(64) NOT NULL,
        x DOUBLE NOT NULL DEFAULT 0,
        y DOUBLE NOT NULL DEFAULT 0,
        z DOUBLE NOT NULL DEFAULT 0,
        label VARCHAR(100) NULL,
        metadata_json LONGTEXT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_mz_world_drops_uid (drop_uid)
      )
    ]])

    MZCoreState.prepareStage = 'check_index_mz_inventory_instance_uid'
    print('[mz_core][prepare] running check_index_mz_inventory_instance_uid')

    local okIndex, hasIndex = xpcall(function()
      return MySQL.single.await([[
      SELECT COUNT(1) AS total
      FROM information_schema.statistics
      WHERE table_schema = DATABASE()
        AND table_name = 'mz_inventory_items'
        AND index_name = 'uq_mz_inventory_instance_uid'
      ]])
    end, prepareTraceback)

    if not okIndex then
      error(('[check_index_mz_inventory_instance_uid] %s'):format(tostring(hasIndex)), 0)
    end

    if not hasIndex or tonumber(hasIndex.total) == 0 then
      runPrepareQuery('add_unique_mz_inventory_instance_uid', [[
        ALTER TABLE mz_inventory_items
        ADD UNIQUE KEY uq_mz_inventory_instance_uid (instance_uid)
      ]])
    end

    for _, orgType in ipairs(Config.SeedOrgTypes or {}) do
      MZCoreState.prepareStage = ('seed_org_type_%s'):format(tostring(orgType.code or 'unknown'))
      print(('[mz_core][prepare] upserting org type %s'):format(tostring(orgType.code or 'unknown')))

      local okOrgType, orgTypeErr = xpcall(function()
        MySQL.insert.await([[
          INSERT INTO mz_org_types (code, name)
          VALUES (?, ?)
          ON DUPLICATE KEY UPDATE name = VALUES(name)
        ]], { orgType.code, orgType.name })
      end, prepareTraceback)

      if not okOrgType then
        error(('[seed_org_type_%s] %s'):format(tostring(orgType.code or 'unknown'), tostring(orgTypeErr)), 0)
      end
    end
  end, prepareTraceback)

  if not ok then
    if MZCoreState.prepareTimedOut == true then
      return
    end

    MZCoreState.prepareDone = true
    MZCoreState.prepareOk = false
    MZCoreState.ready = false
    MZCoreState.prepareError = tostring(err)
    print(('[mz_core] prepare failed: %s'):format(err))
    return
  end

  if MZCoreState.prepareTimedOut == true then
    return
  end

  MZCoreState.prepareDone = true
  MZCoreState.prepareOk = true
  MZCoreState.prepareStage = 'done'
  print(('[mz_core][prepare] completed prepareDone=%s prepareOk=%s seedDone=%s seedOk=%s ready=%s'):format(
    tostring(MZCoreState.prepareDone),
    tostring(MZCoreState.prepareOk),
    tostring(MZCoreState.seedDone),
    tostring(MZCoreState.seedOk),
    tostring(MZCoreState.ready)
  ))
end

MZCoreState.prepareStage = 'threads_registered'
print('[mz_core][prepare] threads registered')

CreateThread(runPrepare)

CreateThread(function()
  local started = GetGameTimer()

  while MZCoreState and MZCoreState.prepareDone ~= true do
    Wait(10000)

    if MZCoreState and MZCoreState.prepareDone ~= true then
      local elapsed = GetGameTimer() - started
      local hint = ''

      if MZCoreState.prepareStage == 'file_loaded' or MZCoreState.prepareStage == 'threads_registered' then
        hint = ' hint=runPrepare_not_entered'
      elseif tostring(MZCoreState.prepareStage or ''):find('enter:', 1, true) then
        hint = ' hint=runPrepare_enter_substage'
      elseif MZCoreState.prepareStage == 'waiting_oxmysql_resource' then
        hint = (' hint=oxmysql_resource_state_%s'):format(getOxmysqlResourceState())
      elseif MZCoreState.prepareStage == 'waiting_mysql_global' then
        hint = (' hint=%s'):format(getMySQLDiagnostics())
      elseif MZCoreState.prepareStage == 'before_first_query' then
        hint = ' hint=first_query_not_started'
      elseif tostring(MZCoreState.prepareStage or ''):find('statement_', 1, true) then
        hint = ' hint=query_pending_or_oxmysql_waiting'
      end

      print(('[mz_core][prepare] still running stage=%s marker=%s enteredXpcall=%s elapsedMs=%s prepareDone=%s prepareOk=%s ready=%s error=%s%s'):format(
        tostring(MZCoreState.prepareStage),
        tostring(MZCoreState.prepareMarker),
        tostring(MZCoreState.prepareEnteredXpcall),
        tostring(elapsed),
        tostring(MZCoreState.prepareDone),
        tostring(MZCoreState.prepareOk),
        tostring(MZCoreState.ready),
        tostring(MZCoreState.prepareError),
        hint
      ))

      if elapsed >= PREPARE_WATCHDOG_TIMEOUT_MS then
        MZCoreState.prepareTimedOut = true
        MZCoreState.prepareDone = true
        MZCoreState.prepareOk = false
        MZCoreState.ready = false
        MZCoreState.prepareError = ('prepare_timeout_stage=%s'):format(tostring(MZCoreState.prepareStage))

        print(('[mz_core][prepare] failed: %s stage=%s marker=%s enteredXpcall=%s elapsedMs=%s'):format(
          tostring(MZCoreState.prepareError),
          tostring(MZCoreState.prepareStage),
          tostring(MZCoreState.prepareMarker),
          tostring(MZCoreState.prepareEnteredXpcall),
          tostring(elapsed)
        ))
        return
      end
    end
  end
end)
