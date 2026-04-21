# mz_core — Esqueleto profissional de framework FiveM

> Aviso: este arquivo e um blueprint historico do inicio do projeto.
> Ele nao representa o estado oficial atual do `mz_core` nem a definicao documental da v1.0.
> Para o estado atual do projeto, consulte `README.md`, `docs/checklist.md`, `docs/ARCHITECTURE.md` e `docs/V1_SCOPE.md`.

## Objetivo
Criar uma base própria de framework para FiveM com foco em:
- **core pequeno e previsível**
- **módulos separados**
- **cadastro/base de dados preparado antes da lógica pesada**
- **aproveitar o melhor de vRP, QBCore, ESX e Qbox**
- **orgs como sistema central para job/gang/staff/vip/etc**

---

## O que está sendo aproveitado de cada framework

### vRP
- groups/permissões flexíveis
- múltiplas capacidades desacopladas do emprego
- boa base para staff, vip, acessos especiais

### QBCore
- ecossistema mental de `PlayerData`
- compatibilidade com job/gang legados
- estrutura simples para scripts terceiros

### ESX
- society/shared accounts
- folha de pagamento e cofres de organização
- separação mais empresarial para orgs

### Qbox
- organização mais moderna
- contratos claros
- menos lógica espalhada no core
- foco em prepare/cache/segurança

---

# Princípios do mz_core

1. **Core só faz o essencial**
2. **Tudo sensível passa por exports/functions bem definidas**
3. **Prepare/migrations sobem tabelas automaticamente**
4. **`orgs` substitui a bagunça de job/gang/staff/vip separados**
5. **Scripts futuros consomem o core via bridge/api**
6. **Inventário e garagem podem ser nativos ou bridged depois**

---

# Estrutura de pastas sugerida

```text
[mz]\
  mz_core/
    fxmanifest.lua
    config.lua
    shared/
      utils.lua
      constants.lua
      version.lua
    server/
      main.lua
      prepare.lua
      bootstrap.lua
      cache.lua
      player/
        service.lua
        repository.lua
        exports.lua
        events.lua
      orgs/
        service.lua
        repository.lua
        exports.lua
        events.lua
      vehicles/
        service.lua
        repository.lua
        exports.lua
        events.lua
      inventory/
        service.lua
        repository.lua
        exports.lua
        events.lua
      accounts/
        service.lua
        repository.lua
      logs/
        service.lua
      bridges/
        qb.lua
        esx.lua
        vrp.lua
    client/
      main.lua
      player.lua
      orgs.lua
      vehicles.lua
      inventory.lua
    sql/
      schema_reference.sql
    docs/
      architecture.md
      api.md
```

---

# Módulos do core

## 1. Player
Responsável por:
- identidade do player
- citizenid
- license
- metadata
- sessão/cache
- bridge de `PlayerData`

## 2. Orgs
Responsável por:
- org types
- orgs
- grades
- permissões
- memberships
- payroll
- logs
- compatibilidade job/gang/staff/vip

## 3. Vehicles
Responsável por:
- cadastro de veículos do player/org
- storage/state mínimo
- plate/model/garage/fuel/engine/body
- vínculo com owner
- sem garagem completa ainda

## 4. Inventory
Responsável por:
- cadastro de slots/itens
- metadata por item
- peso/capacidade
- stash pessoal e stash de org
- sem UI complexa ainda

## 5. Accounts
Responsável por:
- carteira
- banco pessoal
- contas compartilhadas de org

## 6. Prepare
Responsável por:
- garantir schema
- criar tabelas/índices/colunas automaticamente
- seed inicial de tipos de org

---

# Banco de dados — visão geral

## Players
```sql
CREATE TABLE IF NOT EXISTS mz_players (
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
);
```

## Accounts
```sql
CREATE TABLE IF NOT EXISTS mz_player_accounts (
  id INT AUTO_INCREMENT PRIMARY KEY,
  citizenid VARCHAR(32) NOT NULL,
  wallet BIGINT NOT NULL DEFAULT 0,
  bank BIGINT NOT NULL DEFAULT 0,
  dirty BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_mz_player_accounts_citizenid (citizenid)
);
```

## Org types
```sql
CREATE TABLE IF NOT EXISTS mz_org_types (
  id INT AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(32) NOT NULL,
  name VARCHAR(64) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_mz_org_types_code (code)
);
```

## Orgs
```sql
CREATE TABLE IF NOT EXISTS mz_orgs (
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
);
```

## Org grades
```sql
CREATE TABLE IF NOT EXISTS mz_org_grades (
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
);
```

## Org permissions
```sql
CREATE TABLE IF NOT EXISTS mz_org_permissions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  org_id INT NOT NULL,
  grade_id INT NULL,
  permission VARCHAR(128) NOT NULL,
  allow TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_mz_org_permissions_unique (org_id, grade_id, permission),
  KEY idx_mz_org_permissions_org_id (org_id),
  KEY idx_mz_org_permissions_grade_id (grade_id)
);
```

## Player org memberships
```sql
CREATE TABLE IF NOT EXISTS mz_player_orgs (
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
);
```

## Player permission overrides
```sql
CREATE TABLE IF NOT EXISTS mz_player_permissions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  citizenid VARCHAR(32) NOT NULL,
  permission VARCHAR(128) NOT NULL,
  allow TINYINT(1) NOT NULL DEFAULT 1,
  expires_at TIMESTAMP NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_mz_player_permission_unique (citizenid, permission)
);
```

## Vehicles
```sql
CREATE TABLE IF NOT EXISTS mz_player_vehicles (
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
);
```

## Inventory items
```sql
CREATE TABLE IF NOT EXISTS mz_inventory_items (
  id INT AUTO_INCREMENT PRIMARY KEY,
  owner_type VARCHAR(16) NOT NULL DEFAULT 'player',
  owner_id VARCHAR(64) NOT NULL,
  inventory_type VARCHAR(32) NOT NULL DEFAULT 'main',
  slot INT NOT NULL,
  item VARCHAR(64) NOT NULL,
  amount INT NOT NULL DEFAULT 1,
  metadata LONGTEXT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_mz_inventory_slot (owner_type, owner_id, inventory_type, slot),
  KEY idx_mz_inventory_owner (owner_type, owner_id, inventory_type),
  KEY idx_mz_inventory_item (item)
);
```

## Org accounts
```sql
CREATE TABLE IF NOT EXISTS mz_org_accounts (
  id INT AUTO_INCREMENT PRIMARY KEY,
  org_id INT NOT NULL,
  balance BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_mz_org_accounts_org_id (org_id)
);
```

## Logs
```sql
CREATE TABLE IF NOT EXISTS mz_logs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  scope VARCHAR(32) NOT NULL,
  action VARCHAR(64) NOT NULL,
  actor VARCHAR(64) NULL,
  target VARCHAR(64) NULL,
  data_json LONGTEXT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY idx_mz_logs_scope (scope),
  KEY idx_mz_logs_action (action)
);
```

---

# Seed inicial importante

## Org types padrão
- `job`
- `gang`
- `staff`
- `vip`
- `business`
- `government`
- `event`

---

# fxmanifest.lua
```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mz_core'
author 'Mazus'
description 'Professional modular FiveM core framework skeleton'
version '0.1.0'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
  'shared/*.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/prepare.lua',
  'server/cache.lua',
  'server/bootstrap.lua',
  'server/main.lua',
  'server/player/*.lua',
  'server/orgs/*.lua',
  'server/vehicles/*.lua',
  'server/inventory/*.lua',
  'server/accounts/*.lua',
  'server/logs/*.lua',
  'server/bridges/*.lua'
}

client_scripts {
  'client/main.lua',
  'client/player.lua',
  'client/orgs.lua',
  'client/vehicles.lua',
  'client/inventory.lua'
}

dependencies {
  'oxmysql',
  'ox_lib'
}
```

---

# config.lua
```lua
Config = {}

Config.Framework = 'mz_core'
Config.Debug = true

Config.StarterMoney = {
  wallet = 500,
  bank = 5000,
  dirty = 0
}

Config.Player = {
  defaultMetadata = {
    hunger = 100,
    thirst = 100,
    stress = 0,
    health = 200,
    armor = 0
  }
}

Config.Inventory = {
  defaultSlots = 40,
  defaultWeight = 50000
}

Config.SeedOrgTypes = {
  { code = 'job', name = 'Job' },
  { code = 'gang', name = 'Gang' },
  { code = 'staff', name = 'Staff' },
  { code = 'vip', name = 'VIP' },
  { code = 'business', name = 'Business' },
  { code = 'government', name = 'Government' },
  { code = 'event', name = 'Event' }
}
```

---

# shared/utils.lua
```lua
MZUtils = {}

function MZUtils.jsonDecode(value, fallback)
  if not value or value == '' then return fallback end
  local ok, result = pcall(json.decode, value)
  if not ok then return fallback end
  return result
end

function MZUtils.jsonEncode(value, fallback)
  local ok, result = pcall(json.encode, value or fallback or {})
  if not ok then return json.encode(fallback or {}) end
  return result
end

function MZUtils.generateCitizenId()
  local charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
  local result = ''
  for i = 1, 8 do
    local rand = math.random(1, #charset)
    result = result .. charset:sub(rand, rand)
  end
  return result
end

function MZUtils.tableClone(tbl)
  if type(tbl) ~= 'table' then return tbl end
  local out = {}
  for k, v in pairs(tbl) do
    out[k] = MZUtils.tableClone(v)
  end
  return out
end
```

---

# server/cache.lua
```lua
MZCache = {
  playersBySource = {},
  playersByCitizenId = {},
  orgsByCode = {},
  orgTypesByCode = {},
  gradesByOrgId = {},
  permissionsByOrgId = {}
}
```

---

# server/prepare.lua
```lua
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

  [[CREATE TABLE IF NOT EXISTS mz_inventory_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    owner_type VARCHAR(16) NOT NULL DEFAULT 'player',
    owner_id VARCHAR(64) NOT NULL,
    inventory_type VARCHAR(32) NOT NULL DEFAULT 'main',
    slot INT NOT NULL,
    item VARCHAR(64) NOT NULL,
    amount INT NOT NULL DEFAULT 1,
    metadata LONGTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_inventory_slot (owner_type, owner_id, inventory_type, slot),
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
  for _, statement in ipairs(statements) do
    MySQL.query.await(statement)
  end

  for _, orgType in ipairs(Config.SeedOrgTypes or {}) do
    MySQL.insert.await([[
      INSERT INTO mz_org_types (code, name)
      VALUES (?, ?)
      ON DUPLICATE KEY UPDATE name = VALUES(name)
    ]], { orgType.code, orgType.name })
  end

  print('[mz_core] prepare completed')
end)
```

---

# server/player/repository.lua
```lua
MZPlayerRepository = {}

function MZPlayerRepository.getByLicense(license)
  return MySQL.single.await('SELECT * FROM mz_players WHERE license = ? LIMIT 1', { license })
end

function MZPlayerRepository.getByCitizenId(citizenid)
  return MySQL.single.await('SELECT * FROM mz_players WHERE citizenid = ? LIMIT 1', { citizenid })
end

function MZPlayerRepository.create(data)
  MySQL.insert.await([[
    INSERT INTO mz_players (
      license, citizenid, firstname, lastname, birthdate, gender, nationality, phone, metadata
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    data.license,
    data.citizenid,
    data.firstname or '',
    data.lastname or '',
    data.birthdate or '',
    data.gender or '',
    data.nationality or '',
    data.phone or '',
    MZUtils.jsonEncode(data.metadata or Config.Player.defaultMetadata or {})
  })

  return MZPlayerRepository.getByCitizenId(data.citizenid)
end

function MZPlayerRepository.ensureAccount(citizenid)
  MySQL.insert.await([[
    INSERT INTO mz_player_accounts (citizenid, wallet, bank, dirty)
    VALUES (?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE citizenid = citizenid
  ]], {
    citizenid,
    Config.StarterMoney.wallet,
    Config.StarterMoney.bank,
    Config.StarterMoney.dirty
  })
end

function MZPlayerRepository.getAccount(citizenid)
  return MySQL.single.await('SELECT * FROM mz_player_accounts WHERE citizenid = ? LIMIT 1', { citizenid })
end
```

---

# server/player/service.lua
```lua
MZPlayerService = {}

local function getLicense(source)
  for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
    if identifier:find('license:') == 1 then
      return identifier
    end
  end
  return nil
end

function MZPlayerService.loadPlayer(source)
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

  local playerData = {
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
    gang = nil
  }

  MZCache.playersBySource[source] = playerData
  MZCache.playersByCitizenId[playerData.citizenid] = playerData

  return playerData
end

function MZPlayerService.getPlayer(source)
  return MZCache.playersBySource[source]
end

function MZPlayerService.getPlayerByCitizenId(citizenid)
  return MZCache.playersByCitizenId[citizenid]
end

function MZPlayerService.unloadPlayer(source)
  local player = MZCache.playersBySource[source]
  if not player then return end
  MZCache.playersByCitizenId[player.citizenid] = nil
  MZCache.playersBySource[source] = nil
end
```

---

# server/player/exports.lua
```lua
exports('GetPlayer', function(source)
  return MZPlayerService.getPlayer(source)
end)

exports('GetPlayerByCitizenId', function(citizenid)
  return MZPlayerService.getPlayerByCitizenId(citizenid)
end)
```

---

# server/player/events.lua
```lua
AddEventHandler('playerJoining', function()
  local src = source
  CreateThread(function()
    local playerData = MZPlayerService.loadPlayer(src)
    if not playerData then
      print(('[mz_core] failed to load player source %s'):format(src))
      return
    end

    TriggerClientEvent('mz_core:client:playerLoaded', src, playerData)
  end)
end)

AddEventHandler('playerDropped', function()
  MZPlayerService.unloadPlayer(source)
end)
```

---

# server/orgs/repository.lua
```lua
MZOrgRepository = {}

function MZOrgRepository.getOrgByCode(code)
  return MySQL.single.await([[
    SELECT o.*, t.code AS type_code, t.name AS type_name
    FROM mz_orgs o
    INNER JOIN mz_org_types t ON t.id = o.type_id
    WHERE o.code = ?
    LIMIT 1
  ]], { code })
end

function MZOrgRepository.getPlayerMemberships(citizenid)
  return MySQL.query.await([[
    SELECT po.*, o.code AS org_code, o.name AS org_name, t.code AS type_code,
           g.level AS grade_level, g.code AS grade_code, g.name AS grade_name, g.salary
    FROM mz_player_orgs po
    INNER JOIN mz_orgs o ON o.id = po.org_id
    INNER JOIN mz_org_types t ON t.id = o.type_id
    INNER JOIN mz_org_grades g ON g.id = po.grade_id
    WHERE po.citizenid = ? AND po.active = 1
  ]], { citizenid }) or {}
end

function MZOrgRepository.getPermissionsForOrg(orgId)
  return MySQL.query.await('SELECT * FROM mz_org_permissions WHERE org_id = ?', { orgId }) or {}
end

function MZOrgRepository.getGradesForOrg(orgId)
  return MySQL.query.await('SELECT * FROM mz_org_grades WHERE org_id = ? ORDER BY level ASC', { orgId }) or {}
end
```

---

# server/orgs/service.lua
```lua
MZOrgService = {}

local function buildGradeMap(grades)
  local map = {}
  for _, grade in ipairs(grades) do
    map[grade.id] = grade
    map[grade.level] = grade
  end
  return map
end

local function collectInheritedPermissions(gradeId, gradeMap, permissions, out, visited)
  visited = visited or {}
  if not gradeId or visited[gradeId] then return end
  visited[gradeId] = true

  local grade = gradeMap[gradeId]
  if not grade then return end

  if grade.inherits_grade_id then
    collectInheritedPermissions(grade.inherits_grade_id, gradeMap, permissions, out, visited)
  end

  for _, perm in ipairs(permissions) do
    if perm.grade_id == grade.id then
      out[perm.permission] = perm.allow == 1
    end
  end
end

function MZOrgService.loadPlayerOrgs(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then return {} end

  local memberships = MZOrgRepository.getPlayerMemberships(player.citizenid)
  local result = {}

  for _, membership in ipairs(memberships) do
    local grades = MZOrgRepository.getGradesForOrg(membership.org_id)
    local permissions = MZOrgRepository.getPermissionsForOrg(membership.org_id)
    local gradeMap = buildGradeMap(grades)
    local resolvedPermissions = {}

    for _, perm in ipairs(permissions) do
      if perm.grade_id == nil then
        resolvedPermissions[perm.permission] = perm.allow == 1
      end
    end

    collectInheritedPermissions(membership.grade_id, gradeMap, permissions, resolvedPermissions)

    local orgData = {
      org_id = membership.org_id,
      code = membership.org_code,
      name = membership.org_name,
      type = membership.type_code,
      grade = {
        id = membership.grade_id,
        level = membership.grade_level,
        code = membership.grade_code,
        name = membership.grade_name,
        salary = membership.salary
      },
      isPrimary = membership.is_primary == 1,
      duty = membership.duty == 1,
      permissions = resolvedPermissions
    }

    result[#result + 1] = orgData

    if orgData.type == 'job' and orgData.isPrimary then
      player.job = orgData
    end

    if orgData.type == 'gang' and orgData.isPrimary then
      player.gang = orgData
    end
  end

  player.orgs = result
  return result
end

function MZOrgService.getPlayerOrgs(source)
  local player = MZPlayerService.getPlayer(source)
  return player and player.orgs or {}
end

function MZOrgService.hasPermission(source, permission)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false end

  for _, org in ipairs(player.orgs or {}) do
    if org.permissions and org.permissions[permission] == true then
      return true
    end
  end

  return false
end

function MZOrgService.hasGradeOrAbove(source, orgCode, minLevel)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false end

  for _, org in ipairs(player.orgs or {}) do
    if org.code == orgCode and org.grade and (org.grade.level or 0) >= minLevel then
      return true
    end
  end

  return false
end
```

---

# server/orgs/exports.lua
```lua
exports('GetPlayerOrgs', function(source)
  return MZOrgService.getPlayerOrgs(source)
end)

exports('HasPermission', function(source, permission)
  return MZOrgService.hasPermission(source, permission)
end)

exports('HasGradeOrAbove', function(source, orgCode, minLevel)
  return MZOrgService.hasGradeOrAbove(source, orgCode, minLevel)
end)
```

---

# server/vehicles/repository.lua
```lua
MZVehicleRepository = {}

function MZVehicleRepository.getByOwner(ownerType, ownerId)
  return MySQL.query.await([[
    SELECT * FROM mz_player_vehicles
    WHERE owner_type = ? AND owner_id = ?
    ORDER BY id DESC
  ]], { ownerType, ownerId }) or {}
end

function MZVehicleRepository.create(data)
  return MySQL.insert.await([[
    INSERT INTO mz_player_vehicles (
      owner_type, owner_id, plate, model, category, garage, state, fuel, engine, body, props_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    data.owner_type,
    data.owner_id,
    data.plate,
    data.model,
    data.category or 'car',
    data.garage or 'default',
    data.state or 'stored',
    data.fuel or 100,
    data.engine or 1000,
    data.body or 1000,
    MZUtils.jsonEncode(data.props_json or {})
  })
end
```

---

# server/vehicles/service.lua
```lua
MZVehicleService = {}

function MZVehicleService.getPlayerVehicles(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then return {} end
  return MZVehicleRepository.getByOwner('player', player.citizenid)
end

function MZVehicleService.registerPlayerVehicle(source, model, plate, props)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, 'player_not_loaded' end

  MZVehicleRepository.create({
    owner_type = 'player',
    owner_id = player.citizenid,
    model = model,
    plate = plate,
    props_json = props or {}
  })

  return true
end
```

---

# server/vehicles/exports.lua
```lua
exports('GetPlayerVehicles', function(source)
  return MZVehicleService.getPlayerVehicles(source)
end)

exports('RegisterPlayerVehicle', function(source, model, plate, props)
  return MZVehicleService.registerPlayerVehicle(source, model, plate, props)
end)
```

---

# server/inventory/repository.lua
```lua
MZInventoryRepository = {}

function MZInventoryRepository.getInventory(ownerType, ownerId, inventoryType)
  return MySQL.query.await([[
    SELECT * FROM mz_inventory_items
    WHERE owner_type = ? AND owner_id = ? AND inventory_type = ?
    ORDER BY slot ASC
  ]], { ownerType, ownerId, inventoryType }) or {}
end

function MZInventoryRepository.setSlot(data)
  MySQL.insert.await([[
    INSERT INTO mz_inventory_items (owner_type, owner_id, inventory_type, slot, item, amount, metadata)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      item = VALUES(item),
      amount = VALUES(amount),
      metadata = VALUES(metadata),
      updated_at = CURRENT_TIMESTAMP
  ]], {
    data.owner_type,
    data.owner_id,
    data.inventory_type,
    data.slot,
    data.item,
    data.amount,
    MZUtils.jsonEncode(data.metadata or {})
  })
end

function MZInventoryRepository.clearSlot(ownerType, ownerId, inventoryType, slot)
  MySQL.query.await([[
    DELETE FROM mz_inventory_items
    WHERE owner_type = ? AND owner_id = ? AND inventory_type = ? AND slot = ?
  ]], { ownerType, ownerId, inventoryType, slot })
end
```

---

# server/inventory/service.lua
```lua
MZInventoryService = {}

function MZInventoryService.getPlayerInventory(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then return {} end
  return MZInventoryRepository.getInventory('player', player.citizenid, 'main')
end

function MZInventoryService.setPlayerSlot(source, slot, item, amount, metadata)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, 'player_not_loaded' end

  MZInventoryRepository.setSlot({
    owner_type = 'player',
    owner_id = player.citizenid,
    inventory_type = 'main',
    slot = slot,
    item = item,
    amount = amount,
    metadata = metadata or {}
  })

  return true
end

function MZInventoryService.clearPlayerSlot(source, slot)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, 'player_not_loaded' end
  MZInventoryRepository.clearSlot('player', player.citizenid, 'main', slot)
  return true
end
```

---

# server/inventory/exports.lua
```lua
exports('GetPlayerInventory', function(source)
  return MZInventoryService.getPlayerInventory(source)
end)

exports('SetPlayerSlot', function(source, slot, item, amount, metadata)
  return MZInventoryService.setPlayerSlot(source, slot, item, amount, metadata)
end)

exports('ClearPlayerSlot', function(source, slot)
  return MZInventoryService.clearPlayerSlot(source, slot)
end)
```

---

# server/accounts/service.lua
```lua
MZAccountService = {}

function MZAccountService.getMoney(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then return nil end
  return player.money
end
```

---

# server/logs/service.lua
```lua
MZLogService = {}

function MZLogService.create(scope, action, actor, target, data)
  MySQL.insert.await([[
    INSERT INTO mz_logs (scope, action, actor, target, data_json)
    VALUES (?, ?, ?, ?, ?)
  ]], {
    scope,
    action,
    actor,
    target,
    MZUtils.jsonEncode(data or {})
  })
end
```

---

# server/bootstrap.lua
```lua
CreateThread(function()
  Wait(1000)
  print('[mz_core] bootstrap complete')
end)
```

---

# server/main.lua
```lua
lib.callback.register('mz_core:server:getPlayerData', function(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then
    player = MZPlayerService.loadPlayer(source)
  end

  MZOrgService.loadPlayerOrgs(source)
  return player
end)
```

---

# client/main.lua
```lua
MZClient = {
  PlayerData = nil
}

RegisterNetEvent('mz_core:client:playerLoaded', function(playerData)
  MZClient.PlayerData = playerData
end)

CreateThread(function()
  Wait(2000)
  local data = lib.callback.await('mz_core:server:getPlayerData', false)
  MZClient.PlayerData = data
end)
```

---

# client/player.lua
```lua
exports('GetPlayerData', function()
  return MZClient.PlayerData
end)
```

---

# Compatibilidade futura

## Adapter job/gang estilo QBCore
Scripts antigos poderão fazer:
```lua
local Player = exports['mz_core']:GetPlayer(source)
local job = Player.job
local gang = Player.gang
```

## Permissão estilo vRP, mas mais forte
```lua
exports['mz_core']:HasPermission(source, 'police.armory.basic')
exports['mz_core']:HasGradeOrAbove(source, 'police', 3)
```

## Society estilo ESX
```lua
mz_org_accounts
```

## Estrutura moderna estilo Qbox
- prepare automático
- serviços por domínio
- repository separado
- cache separado
- exports pequenos

---

# O que este esqueleto já resolve

- criação automática das tabelas
- cadastro automático de player na base
- contas do player
- estrutura de orgs/grades/permissões
- herança de grade preparada no domínio de orgs
- cadastro de veículos
- inventário base por slots
- exports básicos para outros scripts
- base limpa para evoluir depois

---

# O que ainda não faz de propósito

- sistema completo de dinheiro com add/remove seguro
- garagem visual/NUI
- stash avançado
- crafting
- paycheck scheduler
- admin menu
- character selector
- clothes/housing/phone/hud
- combat logs avançados
- statebags avançados
- sync fina de duty

Isso está certo, porque agora o foco é **esqueleto sólido**.

---

# Próxima ordem ideal de evolução

## Fase 1
- terminar money functions (`AddMoney`, `RemoveMoney`, `SetMoney`)
- player metadata setters
- eventos internos do core

## Fase 2
- completar CRUD de orgs
- promote/demote/hire/fire
- permission overrides
- payroll base

## Fase 3
- item definitions
- peso real
- add/remove item com stack
- stash pessoal/org

## Fase 4
- garagem real
- state out/in garage
- impound
- shared vehicles de org

## Fase 5
- bridge de compatibilidade para scripts externos
- wrapper QBCore-like
- wrapper ESX-like opcional

---

# Minha recomendação prática

Nomeie o recurso como `mz_core` e faça ele ser o **único lugar oficial** de:
- player identity
- orgs
- permission checks
- money state
- vehicles ownership
- inventory ownership

E não deixe scripts futuros criarem isso por fora.

Isso evita o inferno de 20 recursos cada um criando sua própria lógica.

---

# Decisão de arquitetura mais importante

## Não faça isso
- `job` e `gang` como modelos centrais separados
- permissões hardcoded em scripts aleatórios
- inventário acoplado no player service
- veículos acoplados no job

## Faça isso
- `orgs` central
- `grades` central
- `permissions` central
- `repositories` separados
- `prepare` obrigatório
- `exports` curtos e estáveis

---

# Resumo final

O `mz_core` ideal para você deve nascer assim:
- **player** = identidade e sessão
- **orgs** = job/gang/staff/vip/business
- **vehicles** = posse e estado básico
- **inventory** = posse e slots básicos
- **prepare** = banco automático
- **accounts** = dinheiro pessoal e compartilhado
- **logs** = trilha mínima de auditoria

Esse desenho é forte, escalável e muito mais profissional do que copiar qualquer framework inteira.

