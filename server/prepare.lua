MZCoreState = MZCoreState or {}
MZCoreState.prepareDone = false
MZCoreState.prepareOk = false
MZCoreState.seedDone = false
MZCoreState.seedOk = false
MZCoreState.ready = false
MZCoreState.prepareStage = 'file_loaded'
MZCoreState.prepareError = nil

local PREPARE_WATCHDOG_TIMEOUT_MS = 120000
local OXMYSQL_READY_TIMEOUT_MS = 15000

local function traceback(err)
  if type(debug) == 'table' and type(debug.traceback) == 'function' then
    return debug.traceback(tostring(err), 2)
  end
  return tostring(err)
end

local function resourceState(name)
  if type(GetResourceState) ~= 'function' then return 'unknown' end
  local ok, state = pcall(GetResourceState, name)
  return ok and tostring(state) or 'error'
end

local function mysqlReady()
  return MySQL
    and type(MySQL.query) == 'table' and type(MySQL.query.await) == 'function'
    and type(MySQL.single) == 'table' and type(MySQL.single.await) == 'function'
end

local function waitForMySQL()
  local started = GetGameTimer()
  MZCoreState.prepareStage = 'waiting_mysql'
  while resourceState('oxmysql') ~= 'started' or not mysqlReady() do
    if GetGameTimer() - started >= OXMYSQL_READY_TIMEOUT_MS then
      error(('oxmysql_not_ready state=%s'):format(resourceState('oxmysql')), 0)
    end
    Wait(250)
  end
end

local statements = {
  [[CREATE TABLE IF NOT EXISTS mz_accounts (
    account_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    status VARCHAR(24) NOT NULL DEFAULT 'active',
    character_slots SMALLINT UNSIGNED NOT NULL DEFAULT 3,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_mz_accounts_status (status)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS mz_account_identifiers (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    account_id BIGINT UNSIGNED NOT NULL,
    provider VARCHAR(32) NOT NULL,
    identifier VARCHAR(191) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_account_identifier (provider, identifier),
    KEY idx_mz_account_identifiers_account (account_id)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS mz_players (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    account_id BIGINT UNSIGNED NOT NULL,
    citizenid VARCHAR(32) NOT NULL,
    firstname VARCHAR(64) NOT NULL DEFAULT '',
    lastname VARCHAR(64) NOT NULL DEFAULT '',
    birthdate VARCHAR(32) NOT NULL DEFAULT '',
    gender VARCHAR(16) NOT NULL DEFAULT '',
    nationality VARCHAR(64) NOT NULL DEFAULT '',
    phone VARCHAR(32) NOT NULL DEFAULT '',
    metadata LONGTEXT NULL,
    character_status VARCHAR(24) NOT NULL DEFAULT 'active',
    archived_at TIMESTAMP NULL DEFAULT NULL,
    pos_x DOUBLE NOT NULL DEFAULT 0,
    pos_y DOUBLE NOT NULL DEFAULT 0,
    pos_z DOUBLE NOT NULL DEFAULT 0,
    heading FLOAT NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_mz_players_account_status (account_id, character_status),
    UNIQUE KEY uq_mz_players_citizenid (citizenid)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS mz_player_sessions (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    account_id BIGINT UNSIGNED NOT NULL,
    character_id INT NULL,
    active_character_id INT NULL,
    citizenid VARCHAR(32) NULL,
    source INT NOT NULL DEFAULT 0,
    lifecycle VARCHAR(32) NOT NULL DEFAULT 'CHARACTER_SELECTION',
    revision BIGINT UNSIGNED NOT NULL DEFAULT 1,
    joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    dropped_at TIMESTAMP NULL DEFAULT NULL,
    disconnect_reason VARCHAR(255) NOT NULL DEFAULT '',
    session_seconds INT NOT NULL DEFAULT 0,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    KEY idx_mz_player_sessions_account (account_id, is_active),
    KEY idx_mz_player_sessions_character (character_id),
    KEY idx_mz_player_sessions_citizenid (citizenid),
    KEY idx_mz_player_sessions_is_active (is_active),
    UNIQUE KEY uq_mz_player_sessions_active_character (active_character_id)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS mz_character_requests (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    account_id BIGINT UNSIGNED NOT NULL,
    request_key VARCHAR(96) NOT NULL,
    operation VARCHAR(32) NOT NULL,
    character_id INT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'completed',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_character_request (account_id, request_key, operation),
    KEY idx_mz_character_request_character (character_id)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS mz_staff_roles (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(48) NOT NULL,
    name VARCHAR(80) NOT NULL,
    level INT NOT NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    revision BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_by_citizenid VARCHAR(32) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_staff_roles_code (code),
    UNIQUE KEY uq_mz_staff_roles_level (level),
    KEY idx_mz_staff_roles_active (active)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS mz_staff_role_permissions (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    role_id INT NOT NULL,
    permission VARCHAR(128) NOT NULL,
    allow TINYINT(1) NOT NULL DEFAULT 1,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_staff_role_permission (role_id, permission),
    KEY idx_mz_staff_role_permissions_role (role_id)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS mz_staff_assignments (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    account_id BIGINT UNSIGNED NOT NULL,
    context_character_id INT NULL,
    role_id INT NOT NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    assigned_by_account_id BIGINT UNSIGNED NOT NULL,
    assigned_by_character_id INT NULL,
    reason VARCHAR(255) NOT NULL,
    assigned_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMP NULL DEFAULT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_staff_assignments_account (account_id),
    KEY idx_mz_staff_assignments_role_active (role_id, active)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

  [[CREATE TABLE IF NOT EXISTS mz_logs (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    scope VARCHAR(32) NOT NULL,
    action VARCHAR(64) NOT NULL,
    actor VARCHAR(64) NULL,
    target VARCHAR(64) NULL,
    org_code VARCHAR(64) NULL,
    audit_id VARCHAR(96) NULL,
    data_json LONGTEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_mz_logs_scope (scope),
    KEY idx_mz_logs_action (action),
    KEY idx_mz_logs_org_code (org_code),
    UNIQUE KEY uq_mz_logs_audit_id (audit_id)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
}

local schemas = {
  mz_accounts = { columns = { 'account_id', 'status', 'character_slots' }, indexes = { 'PRIMARY', 'idx_mz_accounts_status' } },
  mz_account_identifiers = { columns = { 'id', 'account_id', 'provider', 'identifier' }, indexes = { 'PRIMARY', 'uq_mz_account_identifier', 'idx_mz_account_identifiers_account' } },
  mz_players = { columns = { 'id', 'account_id', 'citizenid', 'metadata', 'character_status', 'pos_x', 'pos_y', 'pos_z', 'heading' }, indexes = { 'PRIMARY', 'idx_mz_players_account_status', 'uq_mz_players_citizenid' }, notNull = { 'account_id' }, forbidden = { 'license' } },
  mz_player_sessions = { columns = { 'id', 'account_id', 'character_id', 'active_character_id', 'citizenid', 'source', 'lifecycle', 'revision', 'is_active' }, indexes = { 'PRIMARY', 'idx_mz_player_sessions_account', 'uq_mz_player_sessions_active_character' }, notNull = { 'account_id' }, forbidden = { 'license' } },
  mz_character_requests = { columns = { 'id', 'account_id', 'request_key', 'operation', 'status' }, indexes = { 'PRIMARY', 'uq_mz_character_request' } },
  mz_staff_roles = { columns = { 'id', 'code', 'level', 'active', 'revision' }, indexes = { 'PRIMARY', 'uq_mz_staff_roles_code' } },
  mz_staff_role_permissions = { columns = { 'id', 'role_id', 'permission', 'allow' }, indexes = { 'PRIMARY', 'uq_mz_staff_role_permission' } },
  mz_staff_assignments = { columns = { 'id', 'account_id', 'role_id', 'active' }, indexes = { 'PRIMARY', 'uq_mz_staff_assignments_account' } },
  mz_logs = { columns = { 'id', 'scope', 'action', 'org_code', 'audit_id', 'data_json' }, indexes = { 'PRIMARY', 'idx_mz_logs_scope', 'uq_mz_logs_audit_id' } }
}

local function failReset(reason)
  error(('schema_reset_required:%s; use the documented clean staging reset procedure'):format(reason), 0)
end

local function validateForbiddenTables()
  for _, tableName in ipairs({ 'mz_player_permissions', 'mz_schema_migrations' }) do
    local row = MySQL.single.await([[
      SELECT COUNT(1) AS total FROM information_schema.tables
      WHERE table_schema = DATABASE() AND table_name = ?
    ]], { tableName })
    if row and tonumber(row.total) > 0 then failReset(('obsolete_table:%s'):format(tableName)) end
  end
end

local function validateSchema(tableName, expected)
  MZCoreState.prepareStage = ('validate_%s'):format(tableName)
  local tableRow = MySQL.single.await([[
    SELECT ENGINE AS engine, TABLE_COLLATION AS table_collation
    FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = ? LIMIT 1
  ]], { tableName })
  if not tableRow then failReset(('missing_table:%s'):format(tableName)) end
  if tostring(tableRow.engine or ''):lower() ~= 'innodb' then failReset(('invalid_engine:%s'):format(tableName)) end
  if not tostring(tableRow.table_collation or ''):lower():find('^utf8mb4_') then failReset(('invalid_charset:%s'):format(tableName)) end

  local columns = {}
  for _, row in ipairs(MySQL.query.await([[
    SELECT column_name, is_nullable FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = ?
  ]], { tableName }) or {}) do
    columns[tostring(row.column_name or ''):lower()] = tostring(row.is_nullable or ''):upper()
  end
  for _, column in ipairs(expected.columns or {}) do
    if not columns[column:lower()] then failReset(('missing_column:%s.%s'):format(tableName, column)) end
  end
  for _, column in ipairs(expected.notNull or {}) do
    if columns[column:lower()] ~= 'NO' then failReset(('nullable_column:%s.%s'):format(tableName, column)) end
  end
  for _, column in ipairs(expected.forbidden or {}) do
    if columns[column:lower()] then failReset(('obsolete_column:%s.%s'):format(tableName, column)) end
  end

  local indexes = {}
  for _, row in ipairs(MySQL.query.await([[
    SELECT DISTINCT index_name FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = ?
  ]], { tableName }) or {}) do
    indexes[tostring(row.index_name or ''):lower()] = true
  end
  for _, index in ipairs(expected.indexes or {}) do
    if not indexes[index:lower()] then failReset(('missing_index:%s.%s'):format(tableName, index)) end
  end
end

local function runPrepare()
  local ok, err = xpcall(function()
    waitForMySQL()
    for index, statement in ipairs(statements) do
      MZCoreState.prepareStage = ('create_%02d'):format(index)
      MySQL.query.await(statement)
    end
    validateForbiddenTables()
    for tableName, expected in pairs(schemas) do validateSchema(tableName, expected) end
  end, traceback)

  MZCoreState.prepareDone = true
  MZCoreState.prepareOk = ok == true
  MZCoreState.prepareStage = ok and 'done' or 'failed'
  MZCoreState.prepareError = ok and nil or tostring(err)
  if ok then
    print('[mz_core][prepare] clean baseline validated')
  else
    print(('[mz_core][prepare] failed: %s'):format(tostring(err)))
  end
end

CreateThread(runPrepare)

CreateThread(function()
  local started = GetGameTimer()
  while MZCoreState.prepareDone ~= true do
    Wait(10000)
    if GetGameTimer() - started >= PREPARE_WATCHDOG_TIMEOUT_MS and MZCoreState.prepareDone ~= true then
      MZCoreState.prepareDone = true
      MZCoreState.prepareOk = false
      MZCoreState.prepareStage = 'timeout'
      MZCoreState.prepareError = 'prepare_timeout'
      print('[mz_core][prepare] failed: prepare_timeout')
      return
    end
  end
end)
