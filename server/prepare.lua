MZCoreState = MZCoreState or {}
MZCoreState.prepareDone = false
MZCoreState.prepareOk = false
MZCoreState.seedDone = false
MZCoreState.seedOk = false
MZCoreState.ready = false

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

  [[CREATE TABLE IF NOT EXISTS mz_org_accounts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    org_id INT NOT NULL,
    balance BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_org_accounts_org_id (org_id)
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

CreateThread(function()
  local ok, err = pcall(function()
    for _, statement in ipairs(statements) do
      MySQL.query.await(statement)
    end

    MySQL.query.await([[
      ALTER TABLE mz_players
      ADD COLUMN IF NOT EXISTS pos_x DOUBLE NOT NULL DEFAULT 0
    ]])

    MySQL.query.await([[
      ALTER TABLE mz_players
      ADD COLUMN IF NOT EXISTS pos_y DOUBLE NOT NULL DEFAULT 0
    ]])

    MySQL.query.await([[
      ALTER TABLE mz_players
      ADD COLUMN IF NOT EXISTS pos_z DOUBLE NOT NULL DEFAULT 0
    ]])

    MySQL.query.await([[
      ALTER TABLE mz_players
      ADD COLUMN IF NOT EXISTS heading FLOAT NOT NULL DEFAULT 0
    ]])

    -- migração defensiva para bancos antigos
    MySQL.query.await([[
      ALTER TABLE mz_inventory_items
      ADD COLUMN IF NOT EXISTS instance_uid VARCHAR(64) NULL
    ]])

    MySQL.query.await([[
      ALTER TABLE mz_player_vehicles
      ADD COLUMN IF NOT EXISTS metadata_json LONGTEXT NULL
    ]])

    MySQL.query.await([[
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
    
    MySQL.query.await([[
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

    local hasIndex = MySQL.single.await([[
      SELECT COUNT(1) AS total
      FROM information_schema.statistics
      WHERE table_schema = DATABASE()
        AND table_name = 'mz_inventory_items'
        AND index_name = 'uq_mz_inventory_instance_uid'
    ]])

    if not hasIndex or tonumber(hasIndex.total) == 0 then
      MySQL.query.await([[
        ALTER TABLE mz_inventory_items
        ADD UNIQUE KEY uq_mz_inventory_instance_uid (instance_uid)
      ]])
    end

    for _, orgType in ipairs(Config.SeedOrgTypes or {}) do
      MySQL.insert.await([[
        INSERT INTO mz_org_types (code, name)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE name = VALUES(name)
      ]], { orgType.code, orgType.name })
    end
  end)

  if not ok then
    MZCoreState.prepareDone = true
    MZCoreState.prepareOk = false
    MZCoreState.ready = false
    print(('[mz_core] prepare failed: %s'):format(err))
    return
  end

  MZCoreState.prepareDone = true
  MZCoreState.prepareOk = true
  print('[mz_core] prepare completed')
end)
