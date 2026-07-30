MZCoreState = MZCoreState or {}
MZCoreState.prepareDone = false
MZCoreState.prepareOk = false
MZCoreState.seedDone = false
MZCoreState.seedOk = false
MZCoreState.ready = false
MZCoreState.prepareStage = 'file_loaded'
MZCoreState.prepareError = nil
MZCoreState.financialOutbox = {
  schemaVersion = 1,
  schemaReady = false,
  enabled = Config and Config.FinancialOutbox and Config.FinancialOutbox.enabled == true,
  writesEnabled = false,
  dispatcherEnabled = false
}

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

  [[CREATE TABLE IF NOT EXISTS mz_account_idempotency (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    source_resource VARCHAR(100) NOT NULL,
    actor_citizenid VARCHAR(64) NOT NULL,
    idempotency_key VARCHAR(64) NOT NULL,
    operation VARCHAR(32) NOT NULL,
    request_fingerprint VARCHAR(255) NOT NULL,
    correlation_id VARCHAR(128) NOT NULL,
    result_json LONGTEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_account_idempotency_scope (source_resource, actor_citizenid, idempotency_key),
    UNIQUE KEY uq_mz_account_idempotency_correlation (correlation_id),
    KEY idx_mz_account_idempotency_created_at (created_at)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_financial_outbox (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    correlation_id VARCHAR(128) NOT NULL,
    idempotency_key VARCHAR(64) NULL,
    event_type VARCHAR(64) NOT NULL,
    source_citizenid VARCHAR(64) NULL,
    target_citizenid VARCHAR(64) NULL,
    account VARCHAR(32) NOT NULL,
    amount BIGINT UNSIGNED NOT NULL,
    fee BIGINT UNSIGNED NOT NULL DEFAULT 0,
    reason VARCHAR(128) NOT NULL,
    source_resource VARCHAR(100) NOT NULL,
    source_channel VARCHAR(32) NOT NULL,
    payload_version SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    metadata_json LONGTEXT NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'pending',
    attempts SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    next_retry_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    claim_token VARCHAR(64) NULL,
    claimed_at TIMESTAMP NULL DEFAULT NULL,
    lease_expires_at TIMESTAMP NULL DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP NULL DEFAULT NULL,
    last_error VARCHAR(255) NULL,
    UNIQUE KEY uq_mz_financial_outbox_correlation (correlation_id),
    UNIQUE KEY uq_mz_financial_outbox_idempotency_scope (
      source_resource, source_citizenid, idempotency_key
    ),
    KEY idx_mz_financial_outbox_dispatch (status, next_retry_at, id),
    KEY idx_mz_financial_outbox_lease (lease_expires_at, status),
    KEY idx_mz_financial_outbox_created (created_at),
    KEY idx_mz_financial_outbox_source (source_resource, created_at)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

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
    revision BIGINT UNSIGNED NOT NULL DEFAULT 1,
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
    active TINYINT(1) NOT NULL DEFAULT 1,
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
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS mz_player_permissions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    citizenid VARCHAR(32) NOT NULL,
    permission VARCHAR(128) NOT NULL,
    allow TINYINT(1) NOT NULL DEFAULT 1,
    expires_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_player_permission_unique (citizenid, permission)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_staff_roles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(48) NOT NULL,
    name VARCHAR(80) NOT NULL,
    level INT NOT NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    revision BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_by_citizenid VARCHAR(32) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_staff_roles_code (code),
    UNIQUE KEY uq_mz_staff_roles_level (level),
    KEY idx_mz_staff_roles_active (active)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS mz_staff_role_permissions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    role_id INT NOT NULL,
    permission VARCHAR(128) NOT NULL,
    allow TINYINT(1) NOT NULL DEFAULT 1,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_staff_role_permission (role_id, permission),
    KEY idx_mz_staff_role_permissions_role (role_id)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS mz_staff_assignments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    citizenid VARCHAR(32) NOT NULL,
    role_id INT NOT NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    assigned_by_citizenid VARCHAR(32) NOT NULL,
    reason VARCHAR(255) NOT NULL,
    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMP NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_staff_assignments_citizenid (citizenid),
    KEY idx_mz_staff_assignments_role_active (role_id, active)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

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

  [[CREATE TABLE IF NOT EXISTS mz_org_recruitment (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    org_code VARCHAR(64) NOT NULL,
    target_citizenid VARCHAR(64) NOT NULL,
    target_name VARCHAR(120) NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'pending',
    desired_grade_level INT NULL,
    desired_grade_code VARCHAR(64) NULL,
    note TEXT NULL,
    created_by_citizenid VARCHAR(64) NULL,
    created_by_name VARCHAR(120) NULL,
    reviewed_by_citizenid VARCHAR(64) NULL,
    reviewed_by_name VARCHAR(120) NULL,
    reviewed_at DATETIME NULL,
    decision_note TEXT NULL,
    metadata_json LONGTEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_mz_org_recruitment_org_code (org_code),
    KEY idx_mz_org_recruitment_target (target_citizenid),
    KEY idx_mz_org_recruitment_status (status),
    KEY idx_mz_org_recruitment_created_at (created_at)
  )]],

  [[CREATE TABLE IF NOT EXISTS mz_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    scope VARCHAR(32) NOT NULL,
    action VARCHAR(64) NOT NULL,
    actor VARCHAR(64) NULL,
    target VARCHAR(64) NULL,
    org_code VARCHAR(64) NULL,
    audit_id VARCHAR(96) NULL,
    data_json LONGTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY idx_mz_logs_scope (scope),
    KEY idx_mz_logs_action (action),
    KEY idx_mz_logs_org_code (org_code),
    UNIQUE KEY uq_mz_logs_audit_id (audit_id)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
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

local function ensureIndex(tableName, indexName, definition)
  local row = MySQL.single.await([[
    SELECT COUNT(1) AS total
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = ?
      AND index_name = ?
  ]], { tableName, indexName })

  if row and tonumber(row.total) and tonumber(row.total) > 0 then return end

  runPrepareQuery(
    ('add_index_%s_%s'):format(tableName, indexName),
    ('ALTER TABLE `%s` ADD %s'):format(tableName, definition)
  )
end

local function ensureInnoDB(tableName)
  local row = MySQL.single.await([[
    SELECT ENGINE AS engine
    FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = ?
    LIMIT 1
  ]], { tableName })
  if not row then error(('table_missing:%s'):format(tableName), 0) end
  if tostring(row.engine or ''):lower() == 'innodb' then return end
  runPrepareQuery(
    ('convert_%s_to_innodb'):format(tableName),
    ('ALTER TABLE `%s` ENGINE=InnoDB'):format(tableName)
  )
end

local function validateTableStructure(tableName, requiredColumns, requiredIndexes)
  local label = ('validate_schema_%s'):format(tostring(tableName))
  MZCoreState.prepareStage = label
  print(('[mz_core][prepare] running %s'):format(label))

  local tableRow = MySQL.single.await([[
    SELECT ENGINE AS engine, TABLE_COLLATION AS table_collation
    FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = ?
    LIMIT 1
  ]], { tableName })

  if not tableRow then
    error(('[%s] table_missing'):format(label), 0)
  end

  if tostring(tableRow.engine or ''):lower() ~= 'innodb' then
    error(('[%s] engine_invalid:%s'):format(label, tostring(tableRow.engine)), 0)
  end

  if not tostring(tableRow.table_collation or ''):lower():find('^utf8mb4_') then
    error(('[%s] charset_invalid:%s'):format(label, tostring(tableRow.table_collation)), 0)
  end

  local columnRows = MySQL.query.await([[
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = ?
  ]], { tableName }) or {}
  local columns = {}
  for _, row in ipairs(columnRows) do
    columns[tostring(row.column_name or ''):lower()] = true
  end

  for _, columnName in ipairs(requiredColumns or {}) do
    if columns[tostring(columnName):lower()] ~= true then
      error(('[%s] column_missing:%s'):format(label, tostring(columnName)), 0)
    end
  end

  local indexRows = MySQL.query.await([[
    SELECT DISTINCT index_name
    FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = ?
  ]], { tableName }) or {}
  local indexes = {}
  for _, row in ipairs(indexRows) do
    indexes[tostring(row.index_name or ''):lower()] = true
  end

  for _, indexName in ipairs(requiredIndexes or {}) do
    if indexes[tostring(indexName):lower()] ~= true then
      error(('[%s] index_missing:%s'):format(label, tostring(indexName)), 0)
    end
  end

  return true
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

    validateTableStructure('mz_financial_outbox', {
      'id', 'correlation_id', 'idempotency_key', 'event_type',
      'source_citizenid', 'target_citizenid', 'account', 'amount', 'fee',
      'reason', 'source_resource', 'source_channel', 'payload_version',
      'metadata_json', 'status', 'attempts', 'next_retry_at', 'claim_token',
      'claimed_at', 'lease_expires_at', 'created_at', 'processed_at', 'last_error'
    }, {
      'PRIMARY', 'uq_mz_financial_outbox_correlation',
      'uq_mz_financial_outbox_idempotency_scope',
      'idx_mz_financial_outbox_dispatch', 'idx_mz_financial_outbox_lease',
      'idx_mz_financial_outbox_created', 'idx_mz_financial_outbox_source'
    })
    MZCoreState.financialOutbox.schemaReady = true
    MZCoreState.financialOutbox.schemaVersion = tonumber(
      Config and Config.FinancialOutbox and Config.FinancialOutbox.schemaVersion
    ) or 1
    MZCoreState.financialOutbox.enabled = Config
      and Config.FinancialOutbox
      and Config.FinancialOutbox.enabled == true
      or false
    MZCoreState.financialOutbox.writesEnabled = MZCoreState.financialOutbox.enabled == true
      and Config.FinancialOutbox.writesEnabled == true
    MZCoreState.financialOutbox.dispatcherEnabled = MZCoreState.financialOutbox.enabled == true
      and type(Config.FinancialOutbox.dispatcher) == 'table'
      and Config.FinancialOutbox.dispatcher.enabled == true
      or false
    print(('[mz_core][outbox] schema ready version=%s enabled=%s writes=%s dispatcher=%s'):format(
      tostring(MZCoreState.financialOutbox.schemaVersion),
      tostring(MZCoreState.financialOutbox.enabled),
      tostring(MZCoreState.financialOutbox.writesEnabled),
      tostring(MZCoreState.financialOutbox.dispatcherEnabled)
    ))

    ensureColumn('mz_players', 'pos_x', 'pos_x DOUBLE NOT NULL DEFAULT 0')
    ensureColumn('mz_players', 'pos_y', 'pos_y DOUBLE NOT NULL DEFAULT 0')
    ensureColumn('mz_players', 'pos_z', 'pos_z DOUBLE NOT NULL DEFAULT 0')
    ensureColumn('mz_players', 'heading', 'heading FLOAT NOT NULL DEFAULT 0')

    -- migração defensiva para bancos antigos
    ensureColumn('mz_inventory_items', 'instance_uid', 'instance_uid VARCHAR(64) NULL')
    ensureColumn('mz_player_vehicles', 'metadata_json', 'metadata_json LONGTEXT NULL')
    ensureColumn('mz_org_grades', 'active', 'active TINYINT(1) NOT NULL DEFAULT 1')
    ensureColumn('mz_orgs', 'revision', 'revision BIGINT UNSIGNED NOT NULL DEFAULT 1')
    ensureColumn('mz_logs', 'org_code', 'org_code VARCHAR(64) NULL')
    ensureColumn('mz_logs', 'audit_id', 'audit_id VARCHAR(96) NULL')
    ensureIndex('mz_logs', 'idx_mz_logs_org_code', 'KEY idx_mz_logs_org_code (org_code)')
    ensureIndex('mz_logs', 'uq_mz_logs_audit_id', 'UNIQUE KEY uq_mz_logs_audit_id (audit_id)')
    ensureInnoDB('mz_player_orgs')
    ensureInnoDB('mz_orgs')
    ensureInnoDB('mz_org_grades')
    ensureInnoDB('mz_org_permissions')
    ensureInnoDB('mz_org_accounts')
    ensureInnoDB('mz_logs')

    -- Backfill idempotente: somente extrai chaves JSON estruturais conhecidas.
    -- Registros sem org_code confiavel permanecem globais; nao ha fallback textual.
    runPrepareQuery('backfill_mz_logs_org_code', [[
      UPDATE mz_logs
      SET org_code = COALESCE(
        NULLIF(JSON_UNQUOTE(JSON_EXTRACT(data_json, '$.context.org_code')), ''),
        NULLIF(JSON_UNQUOTE(JSON_EXTRACT(data_json, '$.context.orgCode')), ''),
        NULLIF(JSON_UNQUOTE(JSON_EXTRACT(data_json, '$.org_code')), ''),
        NULLIF(JSON_UNQUOTE(JSON_EXTRACT(data_json, '$.orgCode')), '')
      )
      WHERE org_code IS NULL
        AND data_json IS NOT NULL
        AND JSON_VALID(data_json) = 1
    ]])

    local legacyStaffPermissions = MySQL.query.await([[
      SELECT p.org_id, o.code AS org_code, p.grade_id, p.permission, p.allow
      FROM mz_org_permissions p
      LEFT JOIN mz_orgs o ON o.id = p.org_id
      WHERE p.permission LIKE 'staff.%'
      ORDER BY p.org_id, p.grade_id, p.permission
    ]]) or {}
    for _, row in ipairs(legacyStaffPermissions) do
      print(('[mz_core][migration][staff-permission] ignored legacy row orgId=%s orgCode=%s gradeId=%s permission=%s allow=%s'):format(
        tostring(row.org_id), tostring(row.org_code), tostring(row.grade_id),
        tostring(row.permission), tostring(row.allow)
      ))
    end

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
