MZOrgService = {}

local function asBool(value)
  if value == true then return true end
  if value == false or value == nil then return false end
  if type(value) == 'number' then return value == 1 end
  if type(value) == 'string' then
    value = value:lower()
    return value == '1' or value == 'true'
  end
  return false
end

local function trim(value)
  if type(value) ~= 'string' and type(value) ~= 'number' then return nil end
  value = tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' then return nil end
  return value
end

local function limitString(value, maxLength)
  value = trim(value)
  if not value then return nil end
  maxLength = tonumber(maxLength) or 64
  if #value > maxLength then value = value:sub(1, maxLength) end
  return value
end

local function normalizeNumber(value, fallback, minValue, maxValue)
  value = tonumber(value) or fallback
  value = math.floor(value or 0)
  if minValue and value < minValue then value = minValue end
  if maxValue and value > maxValue then value = maxValue end
  return value
end

local function normalizeSource(source)
  source = tonumber(source)
  if not source or source <= 0 then return nil end
  return math.floor(source)
end

local function isAceAllowed(source, ace)
  local src = normalizeSource(source)
  ace = limitString(ace, 128)
  if not src or not ace then return false end

  local allowed = IsPlayerAceAllowed(src, ace)
  local normalized = tostring(allowed):lower()
  return allowed == true or allowed == 1 or normalized == '1' or normalized == 'true'
end

local function isOwner(source)
  return isAceAllowed(source, (Config and Config.OwnerAce) or 'group.mz_owner')
end

local function getPlayerNameFromRow(row)
  if not row then return nil end
  local first = trim(row.firstname) or ''
  local last = trim(row.lastname) or ''
  local full = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+$', '')
  if full ~= '' then return full end
  return nil
end

local function getPlayerDisplayName(player, source)
  if player and player.charinfo then
    local first = trim(player.charinfo.firstname) or ''
    local last = trim(player.charinfo.lastname) or ''
    local full = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+$', '')
    if full ~= '' then return full end
  end

  local src = normalizeSource(source)
  if src then
    local ok, name = pcall(GetPlayerName, src)
    if ok and trim(name) then return trim(name) end
  end

  return nil
end

local function makeActor(source)
  local src = normalizeSource(source)
  local player = src and MZPlayerService.getPlayer(src) or nil
  if player and player.citizenid then
    return {
      type = 'player',
      id = tostring(player.citizenid),
      citizenid = tostring(player.citizenid),
      source = src,
      name = getPlayerDisplayName(player, src)
    }
  end

  if tonumber(source) == 0 then
    return { type = 'console', id = 'console' }
  end

  return { type = 'source', id = tostring(source or 'unknown') }
end

local function logDetailed(scope, action, payload)
  if MZLogService and MZLogService.createDetailed then
    MZLogService.createDetailed(scope, action, payload or {})
  end
end

local function logBlocked(action, source, orgCode, targetCitizenId, reason, meta)
  logDetailed('orgs', action, {
    actor = makeActor(source),
    target = {
      type = 'player',
      id = tostring(targetCitizenId or 'unknown'),
      citizenid = targetCitizenId
    },
    context = {
      org_code = orgCode
    },
    meta = {
      reason = reason,
      extra = meta or {}
    }
  })
end

local function buildGradeMap(grades)
  local byId = {}
  local byLevel = {}
  local byCode = {}

  for _, grade in ipairs(grades or {}) do
    byId[tonumber(grade.id) or grade.id] = grade
    byLevel[tonumber(grade.level) or grade.level] = grade
    byCode[tostring(grade.code or '')] = grade
  end

  return byId, byLevel, byCode
end

local function collectInheritedPermissions(gradeId, gradeMap, permissions, out, visited)
  if not gradeId then return end
  visited = visited or {}
  local key = tonumber(gradeId) or gradeId
  if visited[key] then return end
  visited[key] = true

  local grade = gradeMap[key]
  if not grade then return end

  if grade.inherits_grade_id then
    collectInheritedPermissions(grade.inherits_grade_id, gradeMap, permissions, out, visited)
  end

  for _, permission in ipairs(permissions or {}) do
    if tonumber(permission.grade_id) == tonumber(grade.id) then
      out[tostring(permission.permission)] = asBool(permission.allow)
    end
  end
end

local function resolveOrgPermissions(orgId, gradeId)
  local grades = MZOrgRepository.getGradesForOrg(orgId)
  local permissions = MZOrgRepository.getPermissionsForOrg(orgId)
  local gradeMap = buildGradeMap(grades)
  local out = {}

  for _, permission in ipairs(permissions or {}) do
    if permission.grade_id == nil then
      out[tostring(permission.permission)] = asBool(permission.allow)
    end
  end

  collectInheritedPermissions(gradeId, gradeMap, permissions, out)
  return out, grades, permissions
end

local function hasPlayerOverride(citizenid, permission)
  if not citizenid or not permission then return nil end
  for _, row in ipairs(MZOrgRepository.getPlayerOverrides(citizenid) or {}) do
    if row.permission == permission then
      return asBool(row.allow)
    end
  end
  return nil
end

local function getOrgMemberContext(source, orgCode)
  local player = MZPlayerService.getPlayer(source)
  if not player then return nil end
  orgCode = tostring(orgCode or '')

  for _, org in ipairs(player.orgs or {}) do
    if tostring(org.code or '') == orgCode then
      return org
    end
  end

  MZOrgService.loadPlayerOrgs(source)
  player = MZPlayerService.getPlayer(source)
  for _, org in ipairs((player and player.orgs) or {}) do
    if tostring(org.code or '') == orgCode then
      return org
    end
  end

  return nil
end

local function hasAnyOrgCapability(source, orgCode, capabilities)
  for _, capability in ipairs(capabilities or {}) do
    if MZOrgService.canOrg(source, orgCode, capability) == true then
      return true
    end
  end
  return false
end

local function hasStaffManage(source)
  return MZOrgService.hasGlobalPermission(source, 'staff.orgs.manage') == true
end

local function hasStaffView(source)
  return MZOrgService.hasGlobalPermission(source, 'staff.orgs.view') == true
    or MZOrgService.hasGlobalPermission(source, 'staff.orgs.create') == true
    or MZOrgService.hasGlobalPermission(source, 'staff.orgs.set_leader') == true
    or hasStaffManage(source)
end

local function canViewOrg(source, orgCode)
  return isOwner(source)
    or hasStaffView(source)
    or MZOrgService.canOrg(source, orgCode, 'org.view') == true
    or MZOrgService.canOrg(source, orgCode, 'members.view') == true
end

local function canManageMembers(source, orgCode)
  return isOwner(source)
    or hasStaffManage(source)
    or hasAnyOrgCapability(source, orgCode, { 'members.invite', 'manage.members' })
end

local function canManageRecruitment(source, orgCode)
  return isOwner(source)
    or hasAnyOrgCapability(source, orgCode, { 'recruitment.manage', 'members.invite', 'manage.members' })
end

local function canViewRecruitment(source, orgCode)
  return isOwner(source)
    or hasStaffView(source)
    or hasAnyOrgCapability(source, orgCode, { 'recruitment.view', 'recruitment.manage', 'members.invite', 'manage.members' })
end

local function hasLeaderPermission(source, orgCode)
  return isOwner(source)
    or MZOrgService.hasGlobalPermission(source, 'staff.orgs.set_leader') == true
    or MZOrgService.canOrg(source, orgCode, 'members.set_leader') == true
end

local function canStaffSetLeader(source, orgCode)
  return isOwner(source)
    or MZOrgService.hasGlobalPermission(source, 'staff.orgs.set_leader') == true
    or MZOrgService.canOrg(source, orgCode, 'staff.orgs.set_leader') == true
end

local function canCreateOrgs(source)
  return isOwner(source)
    or MZOrgService.hasGlobalPermission(source, 'staff.orgs.create') == true
end

local function canUpdateOrgBasicInfo(source)
  return isOwner(source)
    or MZOrgService.hasGlobalPermission(source, 'staff.orgs.manage') == true
end

local OfficialGradePermissions = {
  -- Org geral
  'org.view',

  -- Membros
  'members.view', 'members.invite', 'members.remove', 'members.promote',
  'members.demote', 'members.set_leader', 'manage.members',

  -- Banco
  'account.view', 'account.deposit', 'account.withdraw', 'account.manage',
  'manage.account',

  -- Metas
  'goals.view', 'goals.manage', 'manage.goals',

  -- Recrutamento
  'recruitment.view', 'recruitment.manage',

  -- Logs
  'logs.view',

  -- Staff/admin
  'staff.panel.open', 'staff.orgs.view', 'staff.orgs.manage',
  'staff.orgs.create', 'staff.orgs.set_leader', 'staff.members.invite',
  'staff.members.remove', 'staff.members.promote', 'staff.members.demote',
  'staff.staff.manage', 'staff.logs.view',

  -- Aliases legados e dominio dos seeds
  'members.kick', 'members.suspend', 'account.transfer', 'manage.permissions',
  'radio.use', 'tablet.open', 'mdt.open', 'storage.open', 'storage.deposit',
  'storage.withdraw', 'storage.manage', 'armory.basic', 'vehicle.basic',
  'vehicle.medium', 'vehicle.advanced', 'vehicle.manage', 'patrol.basic',
  'patrol.lead', 'reports.approve', 'manage.team', 'boss.actions',
  'org.settings', 'highcommand', 'command.full',

  -- Staff legado/dominio
  'staff.report.view', 'staff.kick', 'staff.spectate', 'staff.ban',
  'staff.teleport', 'staff.players.manage',

  -- VIP e dominios
  'vip.chat.tag', 'vip.kit.bronze', 'vip.kit.silver', 'vip.kit.gold',
  'ambulance.radio.use', 'ambulance.tablet.open', 'ambulance.medkit.basic',
  'ambulance.revive.basic', 'ambulance.revive.advanced', 'ambulance.vehicle.basic',
  'ambulance.manage.team', 'mechanic.tablet.open', 'mechanic.repair.basic',
  'mechanic.repair.advanced', 'mechanic.tow.use', 'mechanic.manage.team',
  'mechanic.boss.actions'
}

local OfficialGradePermissionSet = {}
for _, permission in ipairs(OfficialGradePermissions) do
  OfficialGradePermissionSet[permission] = true
end

local function normalizeOrgGradePermission(value)
  value = limitString(value, 128)
  if not value then return nil end
  value = value:lower()
  if not OfficialGradePermissionSet[value] then return nil end
  return value
end

local function isStaffPermission(permission)
  return type(permission) == 'string' and permission:match('^staff%.') ~= nil
end

local function validateGradePermissionChange(source, org, orgCode, permission)
  if not permission then return false, 'invalid_permission' end

  if isStaffPermission(permission) then
    if tostring(org.type_code or '') ~= 'staff' then
      return false, 'permission_not_allowed_for_org_type'
    end

    if not isOwner(source) then
      return false, 'sensitive_permission_requires_owner'
    end
  end

  if permission == 'members.set_leader' and not canStaffSetLeader(source, orgCode) then
    return false, 'leader_permission_required'
  end

  return true
end

local function normalizeOrgBasicName(value)
  value = limitString(value, 120)
  if not value then return nil end
  if #value < 2 then return nil end
  return value
end

local function normalizeOrgBasicStatus(value, currentOrg)
  value = limitString(value, 32)
  if not value then
    return {
      status = (asBool(currentOrg.active) and (asBool(currentOrg.is_public) and 'public' or 'private') or 'inactive'),
      is_public = asBool(currentOrg.is_public),
      active = asBool(currentOrg.active)
    }
  end

  value = value:lower()
  if value == 'active' then value = 'private' end

  if value == 'public' then
    return { status = 'public', is_public = true, active = true }
  end

  if value == 'private' then
    return { status = 'private', is_public = false, active = true }
  end

  if value == 'inactive' then
    return { status = 'inactive', is_public = false, active = false }
  end

  return nil
end

local function logOrgUpdateBasicBlocked(source, orgCode, reason, meta)
  logDetailed('orgs', 'org.update_basic.blocked', {
    actor = makeActor(source),
    target = {
      type = 'org',
      id = tostring(orgCode or 'unknown'),
      code = orgCode
    },
    context = {
      org_code = orgCode
    },
    meta = {
      reason = reason,
      extra = meta or {}
    }
  })
end

local function logOrgArchiveBlocked(action, source, orgCode, reason, meta)
  logDetailed('orgs', action, {
    actor = makeActor(source),
    target = {
      type = 'org',
      id = tostring(orgCode or 'unknown'),
      code = orgCode
    },
    context = {
      org_code = orgCode
    },
    meta = {
      reason = reason,
      extra = meta or {}
    }
  })
end

local function logOrgGradeBlocked(action, source, orgCode, gradeId, reason, meta)
  logDetailed('orgs', action, {
    actor = makeActor(source),
    target = {
      type = 'org_grade',
      id = tostring(gradeId or 'unknown')
    },
    context = {
      org_code = orgCode
    },
    meta = {
      reason = reason,
      extra = meta or {}
    }
  })
end

local function logOrgGradePermissionBlocked(action, source, orgCode, gradeId, permission, reason, meta)
  logDetailed('orgs', action, {
    actor = makeActor(source),
    target = {
      type = 'org_grade_permission',
      id = tostring(gradeId or 'unknown'),
      permission = permission
    },
    context = {
      org_code = orgCode
    },
    meta = {
      reason = reason,
      extra = meta or {}
    }
  })
end

local function directPermissionSnapshot(orgId, gradeId)
  local out = {}
  for _, row in ipairs(MZOrgRepository.listOrgGradePermissions(orgId, gradeId) or {}) do
    out[#out + 1] = row.permission
  end
  table.sort(out)
  return out
end

local function normalizeOrgGradeCode(value)
  value = limitString(value, 64)
  if not value then return nil end
  value = value:lower():gsub('%s+', '_')
  if #value < 2 or #value > 48 then return nil end
  if not value:match('^[a-z0-9_-]+$') then return nil end
  return value
end

local function normalizeOrgGradeName(value)
  value = limitString(value, 120)
  if not value then return nil end
  if #value < 2 then return nil end
  return value
end

local function normalizeOrgGradeLevel(value)
  local level = tonumber(value)
  if not level then return nil end
  level = math.floor(level)
  if level < 1 or level > 1000 then return nil end
  return level
end

local function normalizeOrgGradeSalary(value)
  local salary = tonumber(value)
  if not salary then return nil end
  salary = math.floor(salary)
  if salary < 0 or salary > 100000000 then return nil end
  return salary
end

local function normalizeOrgGradePriority(value, fallback)
  local priority = tonumber(value)
  if not priority then return fallback end
  priority = math.floor(priority)
  if priority < 0 then priority = 0 end
  if priority > 1000 then priority = 1000 end
  return priority
end

local function gradeSnapshot(grade, memberCount)
  if not grade then return nil end
  return {
    id = tonumber(grade.id) or grade.id,
    code = grade.code,
    name = grade.name,
    level = tonumber(grade.level) or 0,
    salary = tonumber(grade.salary) or 0,
    priority = tonumber(grade.priority) or 0,
    active = grade.active == nil and true or asBool(grade.active),
    inherits_grade_id = grade.inherits_grade_id and (tonumber(grade.inherits_grade_id) or grade.inherits_grade_id) or nil,
    member_count = memberCount
  }
end

local function getInheritanceGrade(orgId, value)
  local level = normalizeOrgGradeLevel(value)
  if not level then return nil, 'invalid_inheritance' end
  local grade = MZOrgRepository.getGradeByLevel(orgId, level)
  if not grade then return nil, 'invalid_inheritance' end
  return grade
end

local function wouldCreateInheritanceCycle(orgId, gradeId, inheritsGradeId)
  if not gradeId or not inheritsGradeId then return false end
  local visited = {}
  local currentId = tonumber(inheritsGradeId)
  local targetId = tonumber(gradeId)

  while currentId do
    if currentId == targetId then return true end
    if visited[currentId] then return true end
    visited[currentId] = true

    local grade = MZOrgRepository.getOrgGradeById(orgId, currentId)
    currentId = grade and grade.inherits_grade_id and tonumber(grade.inherits_grade_id) or nil
  end

  return false
end

local OrgCreationTemplates = {
  job = {
    has_salary = true,
    has_shared_account = true,
    requires_shared_account = true,
    has_storage = true,
    grades = {
      { level = 1, code = 'recruta', name = 'Recruta', salary = 1200 },
      { level = 2, code = 'membro', name = 'Membro', salary = 1500 },
      { level = 3, code = 'supervisor', name = 'Supervisor', salary = 2200 },
      { level = 4, code = 'gerente', name = 'Gerente', salary = 3200 },
      { level = 5, code = 'lider', name = 'Lider', salary = 4500 }
    },
    base_permissions = {
      'org.view',
      'members.view',
      'goals.view',
      'account.view',
      'recruitment.view',
      'logs.view'
    },
    grade_permissions = {
      [2] = { 'account.deposit' },
      [3] = { 'members.invite', 'goals.manage', 'recruitment.manage', 'account.deposit' },
      [4] = { 'members.remove', 'members.promote', 'members.demote', 'manage.members', 'account.withdraw', 'account.manage', 'goals.manage', 'recruitment.manage' },
      [5] = { 'manage.members', 'members.set_leader', 'account.manage', 'account.withdraw', 'manage.account', 'goals.manage', 'recruitment.manage', 'boss.actions' }
    }
  },
  gang = {
    has_salary = false,
    has_shared_account = true,
    requires_shared_account = true,
    has_storage = true,
    grades = {
      { level = 1, code = 'recruta', name = 'Recruta', salary = 0 },
      { level = 2, code = 'membro', name = 'Membro', salary = 0 },
      { level = 3, code = 'gerente', name = 'Gerente', salary = 0 },
      { level = 4, code = 'lider', name = 'Lider', salary = 0 }
    },
    base_permissions = {
      'org.view',
      'members.view',
      'goals.view',
      'account.view',
      'recruitment.view',
      'logs.view'
    },
    grade_permissions = {
      [2] = { 'account.deposit' },
      [3] = { 'members.invite', 'members.remove', 'members.promote', 'members.demote', 'goals.manage', 'recruitment.manage', 'account.deposit' },
      [4] = { 'manage.members', 'members.set_leader', 'account.manage', 'account.withdraw', 'manage.account', 'goals.manage', 'recruitment.manage', 'boss.actions' }
    }
  },
  business = {
    has_salary = true,
    has_shared_account = true,
    requires_shared_account = true,
    has_storage = true,
    grades = {
      { level = 1, code = 'funcionario', name = 'Funcionario', salary = 1000 },
      { level = 2, code = 'supervisor', name = 'Supervisor', salary = 1600 },
      { level = 3, code = 'gerente', name = 'Gerente', salary = 2400 },
      { level = 4, code = 'dono', name = 'Dono', salary = 0 }
    },
    base_permissions = {
      'org.view',
      'members.view',
      'goals.view',
      'account.view',
      'logs.view'
    },
    grade_permissions = {
      [2] = { 'account.deposit', 'goals.manage' },
      [3] = { 'members.invite', 'members.remove', 'members.promote', 'members.demote', 'manage.members', 'account.withdraw', 'account.manage', 'goals.manage' },
      [4] = { 'manage.members', 'members.set_leader', 'account.manage', 'account.withdraw', 'manage.account', 'goals.manage', 'boss.actions' }
    }
  },
  government = {
    has_salary = true,
    has_shared_account = true,
    requires_shared_account = true,
    has_storage = true,
    grades = {
      { level = 1, code = 'assistente', name = 'Assistente', salary = 1200 },
      { level = 2, code = 'agente', name = 'Agente', salary = 1800 },
      { level = 3, code = 'coordenador', name = 'Coordenador', salary = 2800 },
      { level = 4, code = 'diretor', name = 'Diretor', salary = 4200 }
    },
    base_permissions = {
      'org.view',
      'members.view',
      'goals.view',
      'account.view',
      'recruitment.view',
      'logs.view'
    },
    grade_permissions = {
      [2] = { 'account.deposit' },
      [3] = { 'members.invite', 'members.remove', 'members.promote', 'members.demote', 'goals.manage', 'recruitment.manage', 'account.deposit' },
      [4] = { 'manage.members', 'members.set_leader', 'account.manage', 'account.withdraw', 'manage.account', 'goals.manage', 'recruitment.manage', 'boss.actions' }
    }
  },
  vip = {
    has_salary = false,
    has_shared_account = false,
    has_storage = false,
    grades = {
      { level = 1, code = 'membro', name = 'Membro', salary = 0 },
      { level = 2, code = 'vip', name = 'VIP', salary = 0 },
      { level = 3, code = 'vip_plus', name = 'VIP Plus', salary = 0 }
    },
    base_permissions = {
      'org.view',
      'members.view',
      'logs.view'
    },
    grade_permissions = {
      [2] = { 'vip.chat.tag' },
      [3] = { 'members.invite', 'members.remove', 'manage.members', 'members.set_leader', 'vip.chat.tag' }
    }
  },
  event = {
    has_salary = false,
    has_shared_account = false,
    has_storage = false,
    grades = {
      { level = 1, code = 'participante', name = 'Participante', salary = 0 },
      { level = 2, code = 'organizador', name = 'Organizador', salary = 0 },
      { level = 3, code = 'coordenador', name = 'Coordenador', salary = 0 }
    },
    base_permissions = {
      'org.view',
      'members.view',
      'goals.view',
      'logs.view'
    },
    grade_permissions = {
      [2] = { 'members.invite', 'goals.manage' },
      [3] = { 'members.invite', 'members.remove', 'members.promote', 'members.demote', 'manage.members', 'members.set_leader', 'goals.manage', 'boss.actions' }
    }
  }
}

local function normalizeOrgCreateType(value)
  value = limitString(value, 32)
  if not value then return nil end
  value = value:lower()
  if value == 'legal' then value = 'job' end
  if value == 'illegal' then value = 'gang' end
  if value == 'staff' then return nil end
  return OrgCreationTemplates[value] and value or nil
end

local function normalizeOrgCreateCode(value)
  value = limitString(value, 64)
  if not value then return nil end
  value = value:lower()
  value = value:gsub('%s+', '_')
  if not value:match('^[a-z0-9_-]+$') then return nil end
  if #value < 2 or #value > 48 then return nil end
  return value
end

local function normalizeOrgCreateName(value)
  value = limitString(value, 120)
  if not value then return nil end
  if #value < 2 then return nil end
  return value
end

local function logOrgCreateBlocked(source, orgCode, reason, meta)
  logDetailed('orgs', 'org.create.blocked', {
    actor = makeActor(source),
    target = {
      type = 'org',
      id = tostring(orgCode or 'unknown')
    },
    context = {
      org_code = orgCode
    },
    meta = {
      reason = reason,
      extra = meta or {}
    }
  })
end

local function maxGradeLevel(grades)
  local maxLevel = nil
  for _, grade in ipairs(grades or {}) do
    local level = tonumber(grade.level)
    if level and (not maxLevel or level > maxLevel) then
      maxLevel = level
    end
  end
  return maxLevel
end

local function topGrade(grades)
  local selected = nil
  for _, grade in ipairs(grades or {}) do
    local level = tonumber(grade.level)
    if level and (not selected or level > tonumber(selected.level)) then
      selected = grade
    end
  end
  return selected
end

local function lowestGrade(grades)
  local selected = nil
  for _, grade in ipairs(grades or {}) do
    local level = tonumber(grade.level)
    if level and level > 0 and (not selected or level < tonumber(selected.level)) then
      selected = grade
    end
  end
  return selected
end

local function resolveGrade(org, options)
  options = type(options) == 'table' and options or {}
  local grades = MZOrgRepository.getGradesForOrg(org.id)
  local _, byLevel, byCode = buildGradeMap(grades)
  local grade = nil

  local level = tonumber(options.gradeLevel or options.grade_level or options.level)
  local code = limitString(options.gradeCode or options.grade_code or options.code, 64)

  if level then
    grade = byLevel[math.floor(level)]
  elseif code then
    grade = byCode[code]
  else
    grade = lowestGrade(grades)
  end

  if not grade then
    return nil, 'grade_not_found'
  end

  return grade, nil, grades
end

local function actorGradeLevel(source, orgCode)
  local org = getOrgMemberContext(source, orgCode)
  if not org or not org.grade then return nil end
  if type(org.grade) == 'table' then return tonumber(org.grade.level) end
  return tonumber(org.grade)
end

local function validateGradeForActor(source, org, grade, grades)
  if not grade then return false, 'invalid_grade' end
  if isOwner(source) then return true end

  local targetLevel = tonumber(grade.level) or 0
  local maxLevel = maxGradeLevel(grades or MZOrgRepository.getGradesForOrg(org.id)) or targetLevel

  if targetLevel >= maxLevel and not hasLeaderPermission(source, org.code) then
    return false, 'leader_permission_required'
  end

  if hasStaffManage(source) then
    return true
  end

  local actorLevel = actorGradeLevel(source, org.code)
  if not actorLevel or actorLevel <= targetLevel then
    return false, 'grade_not_allowed'
  end

  return true
end

local function normalizeOrgRow(row)
  if not row then return nil end
  return {
    id = row.id,
    code = row.code,
    name = row.name,
    type = row.type_code,
    typeCode = row.type_code,
    typeName = row.type_name,
    is_public = asBool(row.is_public),
    requiresWhitelist = asBool(row.requires_whitelist),
    hasSalary = asBool(row.has_salary),
    hasSharedAccount = asBool(row.has_shared_account),
    hasStorage = asBool(row.has_storage),
    active = asBool(row.active),
    status = asBool(row.active) and (asBool(row.is_public) and 'public' or 'private') or 'inactive',
    config = MZUtils.jsonDecode(row.config_json, {}) or {}
  }
end

local function normalizeMemberRow(row)
  if not row then return nil end
  local name = getPlayerNameFromRow(row) or row.citizenid
  return {
    citizenid = tostring(row.citizenid),
    name = name,
    orgCode = row.org_code,
    orgName = row.org_name,
    type = row.type_code,
    grade = tonumber(row.grade_level) or 0,
    gradeLevel = tonumber(row.grade_level) or 0,
    gradeCode = row.grade_code,
    gradeName = row.grade_name,
    isLeader = asBool(row.is_leader),
    isDuty = asBool(row.duty),
    joinedAt = row.joined_at,
    updatedAt = row.updated_at,
    lastSeen = row.last_seen_at,
    status = asBool(row.active) and 'active' or 'inactive'
  }
end

local function normalizeGoalRow(row)
  if not row then return nil end
  local target = tonumber(row.target) or 0
  local progress = tonumber(row.progress) or 0
  local percent = target > 0 and math.floor((progress / target) * 100) or 0
  if percent < 0 then percent = 0 end
  if percent > 100 then percent = 100 end

  return {
    id = row.id,
    orgCode = row.org_code,
    title = row.title,
    description = row.description,
    type = row.type,
    status = row.status,
    target = target,
    progress = progress,
    progressPercent = percent,
    startsAt = row.starts_at,
    endsAt = row.ends_at,
    createdByCitizenId = row.created_by_citizenid,
    createdByName = row.created_by_name,
    createdAt = row.created_at,
    updatedAt = row.updated_at
  }
end

local function normalizeRecruitmentRow(row)
  if not row then return nil end
  return {
    id = tonumber(row.id) or row.id,
    orgCode = row.org_code,
    targetCitizenId = row.target_citizenid,
    targetName = row.target_name,
    candidateCitizenId = row.target_citizenid,
    candidateName = row.target_name,
    status = row.status,
    desiredGradeLevel = tonumber(row.desired_grade_level),
    desiredGradeCode = row.desired_grade_code,
    note = row.note,
    message = row.note,
    createdByCitizenId = row.created_by_citizenid,
    createdByName = row.created_by_name,
    reviewedByCitizenId = row.reviewed_by_citizenid,
    reviewedByName = row.reviewed_by_name,
    reviewedAt = row.reviewed_at,
    decisionNote = row.decision_note,
    metadata = MZUtils.jsonDecode(row.metadata_json, {}) or {},
    createdAt = row.created_at,
    updatedAt = row.updated_at,
    type = 'application'
  }
end

local function getPlayerRowByCitizenId(citizenid)
  citizenid = limitString(citizenid, 64)
  if not citizenid then return nil end
  return MZPlayerRepository.getByCitizenId(citizenid)
end

local function refreshOnlinePlayerByCitizenId(citizenid)
  local target = MZPlayerService.getPlayerByCitizenId(citizenid)
  if not target or not target.source then return end
  MZOrgService.loadPlayerOrgs(target.source)
  TriggerClientEvent('mz_core:client:playerLoaded', target.source, target)
end

function MZOrgService.loadPlayerOrgs(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then return {} end

  local memberships = MZOrgRepository.getPlayerMemberships(player.citizenid)
  local result = {}

  player.job = nil
  player.gang = nil

  for _, membership in ipairs(memberships or {}) do
    local resolvedPermissions = resolveOrgPermissions(membership.org_id, membership.grade_id)
    local permissionList = {}
    for permission, allowed in pairs(resolvedPermissions) do
      if allowed == true then permissionList[#permissionList + 1] = permission end
    end
    table.sort(permissionList)

    local orgData = {
      org_id = membership.org_id,
      orgId = membership.org_id,
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
      gradeLevel = membership.grade_level,
      gradeCode = membership.grade_code,
      gradeName = membership.grade_name,
      isPrimary = asBool(membership.is_primary),
      duty = asBool(membership.duty),
      permissions = resolvedPermissions,
      capabilities = permissionList
    }

    result[#result + 1] = orgData

    if orgData.type == 'job' and orgData.isPrimary then player.job = orgData end
    if orgData.type == 'gang' and orgData.isPrimary then player.gang = orgData end
  end

  player.orgs = result
  return result
end

function MZOrgService.getPlayerOrgs(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then return {} end
  if not player.orgs then return MZOrgService.loadPlayerOrgs(source) end
  return player.orgs or {}
end

function MZOrgService.getPlayerOrgContext(source)
  return MZOrgService.getPlayerOrgs(source)
end

function MZOrgService.hasPermission(source, permission)
  permission = limitString(permission, 128)
  if not permission then return false end
  if isOwner(source) then return true end

  local player = MZPlayerService.getPlayer(source)
  if not player then return false end

  local override = hasPlayerOverride(player.citizenid, permission)
  if override ~= nil then return override == true end

  for _, org in ipairs(MZOrgService.getPlayerOrgs(source) or {}) do
    if org.permissions and org.permissions[permission] == true then
      return true
    end
  end

  return false
end

function MZOrgService.hasGlobalPermission(source, permission)
  permission = limitString(permission, 128)
  if not permission then return false end
  if isOwner(source) then return true end
  if isAceAllowed(source, permission) then return true end
  return MZOrgService.hasPermission(source, permission) == true
end

function MZOrgService.canOrg(source, orgCode, capability)
  orgCode = limitString(orgCode, 64)
  capability = limitString(capability, 128)
  if not orgCode or not capability then return false end
  if isOwner(source) then return true end

  local player = MZPlayerService.getPlayer(source)
  if not player then return false end

  local override = hasPlayerOverride(player.citizenid, capability)
  if override ~= nil then return override == true end

  local org = getOrgMemberContext(source, orgCode)
  return org and org.permissions and org.permissions[capability] == true or false
end

function MZOrgService.hasGradeOrAbove(source, orgCode, minLevel)
  local org = getOrgMemberContext(source, orgCode)
  if not org or not org.grade then return false end
  local level = type(org.grade) == 'table' and tonumber(org.grade.level) or tonumber(org.grade)
  return (level or 0) >= (tonumber(minLevel) or 0)
end

function MZOrgService.getOrgByCode(orgCode)
  orgCode = limitString(orgCode, 64)
  if not orgCode then return nil end
  return normalizeOrgRow(MZOrgRepository.getOrgByCode(orgCode))
end

function MZOrgService.listOrgs(orgTypeCode)
  local rows = MZOrgRepository.listOrgs(limitString(orgTypeCode, 32))
  local out = {}
  for _, row in ipairs(rows or {}) do out[#out + 1] = normalizeOrgRow(row) end
  return out
end

function MZOrgService.listOrgMembers(source, orgCode)
  orgCode = limitString(orgCode, 64)
  if not orgCode then return false, 'invalid_org' end
  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'invalid_org' end
  if not canViewOrg(source, orgCode) then return false, 'forbidden' end

  local rows = MZOrgRepository.listMembersForOrg(org.id)
  local out = {}
  for _, row in ipairs(rows or {}) do out[#out + 1] = normalizeMemberRow(row) end
  return out
end

function MZOrgService.getOrgAccessModel(source, orgCode)
  orgCode = limitString(orgCode, 64)
  if not orgCode then return false, 'invalid_org' end
  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'invalid_org' end
  if not canViewOrg(source, orgCode) then return false, 'forbidden' end

  local grades = MZOrgRepository.getGradesForOrg(org.id, hasStaffView(source))
  local permissions = MZOrgRepository.getPermissionsForOrg(org.id)
  local gradeMap = buildGradeMap(grades)
  local baseCapabilities = {}
  local gradeOut = {}

  for _, permission in ipairs(permissions or {}) do
    if permission.grade_id == nil and asBool(permission.allow) then
      baseCapabilities[#baseCapabilities + 1] = permission.permission
    end
  end
  table.sort(baseCapabilities)

  for _, grade in ipairs(grades or {}) do
    local resolved = {}
    local direct = {}
    for _, capability in ipairs(baseCapabilities) do resolved[capability] = true end
    collectInheritedPermissions(grade.id, gradeMap, permissions, resolved)

    local caps = {}
    for capability, allowed in pairs(resolved) do
      if allowed then caps[#caps + 1] = capability end
    end
    table.sort(caps)

    for _, permission in ipairs(permissions or {}) do
      if tonumber(permission.grade_id) == tonumber(grade.id) and asBool(permission.allow) then
        direct[#direct + 1] = permission.permission
      end
    end
    table.sort(direct)

    local inherits = grade.inherits_grade_id and gradeMap[tonumber(grade.inherits_grade_id)] or nil
    gradeOut[#gradeOut + 1] = {
      id = grade.id,
      level = tonumber(grade.level) or 0,
      code = grade.code,
      name = grade.name,
      salary = tonumber(grade.salary) or 0,
      priority = tonumber(grade.priority) or 0,
      active = grade.active == nil and true or asBool(grade.active),
      inheritsGradeId = grade.inherits_grade_id and (tonumber(grade.inherits_grade_id) or grade.inherits_grade_id) or nil,
      inheritsLevel = inherits and tonumber(inherits.level) or nil,
      inheritsCode = inherits and inherits.code or nil,
      capabilities = caps,
      directCapabilities = direct
    }
  end

  local player = MZPlayerService.getPlayer(source)
  local overrides = {}
  if player and player.citizenid then
    for _, row in ipairs(MZOrgRepository.getPlayerOverrides(player.citizenid) or {}) do
      overrides[#overrides + 1] = {
        permission = row.permission,
        allow = asBool(row.allow),
        expiresAt = row.expires_at
      }
    end
  end

  return {
    orgCode = org.code,
    orgName = org.name,
    type = org.type_code,
    baseCapabilities = baseCapabilities,
    grades = gradeOut,
    playerOverrides = overrides
  }
end

function MZOrgService.addMember(citizenid, orgCode, gradeLevel, options, actor)
  citizenid = limitString(citizenid, 64)
  orgCode = limitString(orgCode, 64)
  if not citizenid then return false, 'invalid_target' end
  if not orgCode then return false, 'invalid_org' end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'invalid_org' end
  local playerRow = getPlayerRowByCitizenId(citizenid)
  if not playerRow then return false, 'target_not_found' end

  local existingMembership = MZOrgRepository.getPlayerMembership(citizenid, org.id)
  if existingMembership and asBool(existingMembership.active) then
    return false, 'already_member'
  end

  options = type(options) == 'table' and options or {}
  if gradeLevel then options.gradeLevel = gradeLevel end
  local grade, gradeErr = resolveGrade(org, options)
  if not grade then return false, gradeErr or 'invalid_grade' end

  MZOrgRepository.setMembership(citizenid, org.id, grade.id, options.is_primary, options.duty, options.expiresAt)
  if options.is_primary then
    MZOrgRepository.setPrimaryMembership(citizenid, org.type_code, org.id)
  end

  refreshOnlinePlayerByCitizenId(citizenid)
  logDetailed('orgs', 'org.member.add', {
    actor = makeActor(actor),
    target = {
      type = 'player',
      id = citizenid,
      citizenid = citizenid,
      name = getPlayerNameFromRow(playerRow)
    },
    context = {
      org_code = org.code,
      org_id = org.id
    },
    after = {
      grade_level = tonumber(grade.level),
      grade_code = grade.code
    }
  })

  return true, {
    orgCode = org.code,
    targetCitizenId = citizenid,
    targetName = getPlayerNameFromRow(playerRow),
    grade = tonumber(grade.level) or grade.level,
    gradeLevel = tonumber(grade.level) or grade.level,
    gradeCode = grade.code,
    gradeName = grade.name
  }
end

function MZOrgService.inviteOrgMemberByCitizenId(source, orgCode, targetCitizenId, options)
  local src = normalizeSource(source)
  orgCode = limitString(orgCode, 64)
  targetCitizenId = limitString(targetCitizenId, 64)

  if not src then return false, 'invalid_source' end
  if not orgCode then return false, 'invalid_org' end
  if not targetCitizenId then return false, 'invalid_target' end

  local actor = MZPlayerService.getPlayer(src)
  if not actor or not actor.citizenid then
    return false, 'player_not_loaded'
  end

  if tostring(actor.citizenid) == tostring(targetCitizenId) then
    return false, 'self_target'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'invalid_org' end
  if not canManageMembers(src, orgCode) then
    logBlocked('org.member.invite.blocked', src, orgCode, targetCitizenId, 'forbidden')
    return false, 'forbidden'
  end

  local targetRow = getPlayerRowByCitizenId(targetCitizenId)
  if not targetRow then return false, 'target_not_found' end
  local existingMembership = MZOrgRepository.getPlayerMembership(targetCitizenId, org.id)
  if existingMembership and asBool(existingMembership.active) then return false, 'already_member' end

  local grade, gradeErr, grades = resolveGrade(org, options)
  if not grade then return false, gradeErr or 'invalid_grade' end

  local allowed, gradeBlock = validateGradeForActor(src, org, grade, grades)
  if not allowed then
    logBlocked('org.member.invite.blocked', src, orgCode, targetCitizenId, gradeBlock, {
      desired_grade_level = tonumber(grade.level),
      desired_grade_code = grade.code
    })
    return false, gradeBlock
  end

  local ok, dataOrErr = MZOrgService.addMember(targetCitizenId, orgCode, grade.level, {
    is_primary = true,
    duty = false
  }, src)
  if not ok then return false, dataOrErr end

  logDetailed('orgs', 'org.member.invite', {
    actor = makeActor(src),
    target = {
      type = 'player',
      id = targetCitizenId,
      citizenid = targetCitizenId,
      name = getPlayerNameFromRow(targetRow)
    },
    context = {
      org_code = org.code,
      org_id = org.id
    },
    after = {
      grade_level = tonumber(grade.level),
      grade_code = grade.code
    }
  })

  return true, dataOrErr
end

function MZOrgService.inviteOrgMember(source, orgCode, targetSource, options)
  local target = MZPlayerService.getPlayer(tonumber(targetSource))
  if not target or not target.citizenid then return false, 'target_not_found' end
  return MZOrgService.inviteOrgMemberByCitizenId(source, orgCode, target.citizenid, options)
end

local function validateMemberAction(source, orgCode, targetCitizenId, permissionList)
  local src = normalizeSource(source)
  orgCode = limitString(orgCode, 64)
  targetCitizenId = limitString(targetCitizenId, 64)
  if not src then return false, 'invalid_source' end
  if not orgCode then return false, 'invalid_org' end
  if not targetCitizenId then return false, 'invalid_target' end

  local actor = MZPlayerService.getPlayer(src)
  if not actor or not actor.citizenid then return false, 'player_not_loaded' end
  if tostring(actor.citizenid) == tostring(targetCitizenId) then return false, 'self_action' end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'invalid_org' end
  if not (isOwner(src) or hasStaffManage(src) or hasAnyOrgCapability(src, orgCode, permissionList)) then
    return false, 'forbidden'
  end

  local targetMembership = MZOrgRepository.getPlayerMembership(targetCitizenId, org.id)
  if not targetMembership or not asBool(targetMembership.active) then return false, 'not_member' end

  local grades = MZOrgRepository.getGradesForOrg(org.id)
  local _, byLevel = buildGradeMap(grades)
  local targetGrade = MZOrgRepository.getGradeById(targetMembership.grade_id)
  local actorLevel = actorGradeLevel(src, orgCode)
  local targetLevel = targetGrade and tonumber(targetGrade.level) or 0
  local maxLevel = maxGradeLevel(grades) or targetLevel

  if targetLevel >= maxLevel and not hasLeaderPermission(src, orgCode) then
    return false, 'leader_permission_required'
  end

  if not isOwner(src) and not hasStaffManage(src) and (not actorLevel or actorLevel <= targetLevel) then
    return false, 'target_higher_or_equal'
  end

  return true, {
    source = src,
    actor = actor,
    org = org,
    targetMembership = targetMembership,
    targetGrade = targetGrade,
    targetLevel = targetLevel,
    actorLevel = actorLevel,
    maxLevel = maxLevel,
    grades = grades,
    gradesByLevel = byLevel
  }
end

function MZOrgService.removeOrgMemberSecure(source, orgCode, targetCitizenId)
  local ok, ctxOrErr = validateMemberAction(source, orgCode, targetCitizenId, { 'members.remove', 'members.kick', 'manage.members' })
  if not ok then return false, ctxOrErr == 'self_action' and 'self_remove' or ctxOrErr end
  MZOrgRepository.removeMembership(targetCitizenId, ctxOrErr.org.id)
  refreshOnlinePlayerByCitizenId(targetCitizenId)
  logDetailed('orgs', 'org.member.remove', {
    actor = makeActor(source),
    target = { type = 'player', id = targetCitizenId, citizenid = targetCitizenId },
    context = { org_code = ctxOrErr.org.code, org_id = ctxOrErr.org.id },
    before = { grade_level = ctxOrErr.targetLevel }
  })
  return true, { orgCode = ctxOrErr.org.code, targetCitizenId = targetCitizenId, removed = true }
end

function MZOrgService.removeMember(citizenid, orgCode, actor)
  return MZOrgService.removeOrgMemberSecure(actor, orgCode, citizenid)
end

-- Caminho administrativo interno usado somente pelo comando protegido no
-- console. Nao e exportado e nao transforma source=0 em bypass dos endpoints
-- seguros usados por jogadores/resources.
function MZOrgService.removeMemberFromConsole(citizenid, orgCode, actor)
  if tonumber(actor) ~= 0 then return false, 'forbidden' end
  citizenid = limitString(citizenid, 64)
  orgCode = limitString(orgCode, 64)
  if not citizenid then return false, 'invalid_target' end
  if not orgCode then return false, 'invalid_org' end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'invalid_org' end
  local membership = MZOrgRepository.getPlayerMembership(citizenid, org.id)
  if not membership or not asBool(membership.active) then return false, 'not_member' end

  MZOrgRepository.removeMembership(citizenid, org.id)
  refreshOnlinePlayerByCitizenId(citizenid)
  logDetailed('orgs', 'org.member.remove', {
    actor = makeActor(0),
    target = { type = 'player', id = citizenid, citizenid = citizenid },
    context = { org_code = org.code, org_id = org.id },
    before = { grade_id = tonumber(membership.grade_id) or membership.grade_id },
    meta = { command = 'mzorg_remove', console = true }
  })
  return true, { orgCode = org.code, targetCitizenId = citizenid, removed = true }
end

function MZOrgService.promoteOrgMemberSecure(source, orgCode, targetCitizenId)
  local ok, ctxOrErr = validateMemberAction(source, orgCode, targetCitizenId, { 'members.promote', 'manage.members' })
  if not ok then return false, ctxOrErr end

  local nextGrade = nil
  for _, grade in ipairs(ctxOrErr.grades or {}) do
    local level = tonumber(grade.level)
    if level and level > ctxOrErr.targetLevel and (not nextGrade or level < tonumber(nextGrade.level)) then
      nextGrade = grade
    end
  end

  if not nextGrade then return false, 'max_grade' end
  if tonumber(nextGrade.level) >= ctxOrErr.maxLevel and not hasLeaderPermission(source, orgCode) then
    return false, 'leader_permission_required'
  end
  if not isOwner(source) and not hasStaffManage(source) and ctxOrErr.actorLevel and tonumber(nextGrade.level) >= ctxOrErr.actorLevel then
    return false, 'promotion_above_actor'
  end

  MZOrgRepository.updateMembershipGrade(targetCitizenId, ctxOrErr.org.id, nextGrade.id)
  refreshOnlinePlayerByCitizenId(targetCitizenId)
  return true, {
    orgCode = ctxOrErr.org.code,
    targetCitizenId = targetCitizenId,
    oldGrade = ctxOrErr.targetLevel,
    newGrade = tonumber(nextGrade.level),
    grade = tonumber(nextGrade.level),
    gradeCode = nextGrade.code,
    gradeName = nextGrade.name
  }
end

function MZOrgService.demoteOrgMemberSecure(source, orgCode, targetCitizenId)
  local ok, ctxOrErr = validateMemberAction(source, orgCode, targetCitizenId, { 'members.demote', 'manage.members' })
  if not ok then return false, ctxOrErr end

  local prevGrade = nil
  for _, grade in ipairs(ctxOrErr.grades or {}) do
    local level = tonumber(grade.level)
    if level and level < ctxOrErr.targetLevel and (not prevGrade or level > tonumber(prevGrade.level)) then
      prevGrade = grade
    end
  end

  if not prevGrade then return false, 'min_grade' end
  MZOrgRepository.updateMembershipGrade(targetCitizenId, ctxOrErr.org.id, prevGrade.id)
  refreshOnlinePlayerByCitizenId(targetCitizenId)
  return true, {
    orgCode = ctxOrErr.org.code,
    targetCitizenId = targetCitizenId,
    oldGrade = ctxOrErr.targetLevel,
    newGrade = tonumber(prevGrade.level),
    grade = tonumber(prevGrade.level),
    gradeCode = prevGrade.code,
    gradeName = prevGrade.name
  }
end

function MZOrgService.promote(citizenid, orgCode, actor)
  return MZOrgService.promoteOrgMemberSecure(actor, orgCode, citizenid)
end

function MZOrgService.demote(citizenid, orgCode, actor)
  return MZOrgService.demoteOrgMemberSecure(actor, orgCode, citizenid)
end

function MZOrgService.setDuty(citizenid, orgCode, duty, actor)
  citizenid = limitString(citizenid, 64)
  orgCode = limitString(orgCode, 64)
  local org = orgCode and MZOrgRepository.getOrgByCode(orgCode) or nil
  if not citizenid then return false, 'invalid_target' end
  if not org then return false, 'invalid_org' end
  if not MZOrgRepository.getPlayerMembership(citizenid, org.id) then return false, 'not_member' end
  MZOrgRepository.setMembershipDuty(citizenid, org.id, duty)
  refreshOnlinePlayerByCitizenId(citizenid)
  return true, { orgCode = org.code, targetCitizenId = citizenid, duty = asBool(duty) }
end

function MZOrgService.setPrimary(citizenid, orgCode, actor)
  citizenid = limitString(citizenid, 64)
  orgCode = limitString(orgCode, 64)
  local org = orgCode and MZOrgRepository.getOrgByCode(orgCode) or nil
  if not citizenid then return false, 'invalid_target' end
  if not org then return false, 'invalid_org' end
  if not MZOrgRepository.getPlayerMembership(citizenid, org.id) then return false, 'not_member' end
  MZOrgRepository.setPrimaryMembership(citizenid, org.type_code, org.id)
  refreshOnlinePlayerByCitizenId(citizenid)
  return true, { orgCode = org.code, targetCitizenId = citizenid, primary = true }
end

function MZOrgService.setGrade(citizenid, orgCode, gradeLevel, actor)
  citizenid = limitString(citizenid, 64)
  orgCode = limitString(orgCode, 64)
  local org = orgCode and MZOrgRepository.getOrgByCode(orgCode) or nil
  if not citizenid then return false, 'invalid_target' end
  if not org then return false, 'invalid_org' end
  local membership = MZOrgRepository.getPlayerMembership(citizenid, org.id)
  if not membership then return false, 'not_member' end
  local grade = MZOrgRepository.getGradeByLevel(org.id, tonumber(gradeLevel))
  if not grade then return false, 'grade_not_found' end
  MZOrgRepository.updateMembershipGrade(citizenid, org.id, grade.id)
  refreshOnlinePlayerByCitizenId(citizenid)
  return true, { orgCode = org.code, targetCitizenId = citizenid, grade = tonumber(grade.level), gradeCode = grade.code }
end

function MZOrgService.setLeaderByCitizenId(source, orgCode, targetCitizenId, options)
  local src = normalizeSource(source)
  orgCode = limitString(orgCode, 64)
  targetCitizenId = limitString(targetCitizenId, 64)
  options = type(options) == 'table' and options or {}

  if not src then return false, 'invalid_source' end
  if not orgCode then return false, 'invalid_org' end
  if not targetCitizenId then return false, 'invalid_target' end

  local actor = MZPlayerService.getPlayer(src)
  if not actor or not actor.citizenid then
    logBlocked('org.member.set_leader.blocked', src, orgCode, targetCitizenId, 'player_not_loaded')
    return false, 'player_not_loaded'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    logBlocked('org.member.set_leader.blocked', src, orgCode, targetCitizenId, 'invalid_org')
    return false, 'invalid_org'
  end

  if tostring(actor.citizenid) == tostring(targetCitizenId) and not isOwner(src) then
    logBlocked('org.member.set_leader.blocked', src, orgCode, targetCitizenId, 'forbidden', {
      self_target = true
    })
    return false, 'forbidden'
  end

  if not canStaffSetLeader(src, orgCode) then
    logBlocked('org.member.set_leader.blocked', src, orgCode, targetCitizenId, 'forbidden')
    return false, 'forbidden'
  end

  local targetRow = getPlayerRowByCitizenId(targetCitizenId)
  if not targetRow then
    logBlocked('org.member.set_leader.blocked', src, orgCode, targetCitizenId, 'target_not_found')
    return false, 'target_not_found'
  end

  local grades = MZOrgRepository.getGradesForOrg(org.id)
  local grade = topGrade(grades)
  if not grade then
    logBlocked('org.member.set_leader.blocked', src, orgCode, targetCitizenId, 'top_grade_not_found')
    return false, 'top_grade_not_found'
  end

  local beforeMembership = MZOrgRepository.getPlayerMembership(targetCitizenId, org.id)
  local beforeGrade = beforeMembership and beforeMembership.grade_id and MZOrgRepository.getGradeById(beforeMembership.grade_id) or nil
  local affectedOk = true

  if beforeMembership and asBool(beforeMembership.active) then
    MZOrgRepository.updateMembershipGrade(targetCitizenId, org.id, grade.id)
    MZOrgRepository.setPrimaryMembership(targetCitizenId, org.type_code, org.id)
  else
    MZOrgRepository.setMembership(targetCitizenId, org.id, grade.id, true, false, nil)
    MZOrgRepository.setPrimaryMembership(targetCitizenId, org.type_code, org.id)
  end

  local afterMembership = MZOrgRepository.getPlayerMembership(targetCitizenId, org.id)
  if not afterMembership or tonumber(afterMembership.grade_id) ~= tonumber(grade.id) or not asBool(afterMembership.active) then
    affectedOk = false
  end

  if not affectedOk then
    logBlocked('org.member.set_leader.blocked', src, orgCode, targetCitizenId, 'set_leader_failed', {
      top_grade_level = tonumber(grade.level),
      top_grade_code = grade.code
    })
    return false, 'set_leader_failed'
  end

  refreshOnlinePlayerByCitizenId(targetCitizenId)

  local reason = limitString(options.reason, 255)
  logDetailed('orgs', 'org.member.set_leader', {
    actor = makeActor(src),
    target = {
      type = 'player',
      id = targetCitizenId,
      citizenid = targetCitizenId,
      name = getPlayerNameFromRow(targetRow)
    },
    context = {
      org_code = org.code,
      org_id = org.id
    },
    before = {
      was_member = beforeMembership and asBool(beforeMembership.active) or false,
      grade_level = beforeGrade and tonumber(beforeGrade.level) or nil,
      grade_code = beforeGrade and beforeGrade.code or nil
    },
    after = {
      grade_level = tonumber(grade.level),
      grade_code = grade.code,
      is_primary = true
    },
    meta = {
      reason = reason,
      top_grade_level = tonumber(grade.level),
      top_grade_code = grade.code
    }
  })

  return true, {
    orgCode = org.code,
    orgName = org.name,
    targetCitizenId = targetCitizenId,
    targetName = getPlayerNameFromRow(targetRow),
    wasMember = beforeMembership and asBool(beforeMembership.active) or false,
    oldGrade = beforeGrade and tonumber(beforeGrade.level) or nil,
    oldGradeCode = beforeGrade and beforeGrade.code or nil,
    grade = tonumber(grade.level),
    gradeLevel = tonumber(grade.level),
    gradeCode = grade.code,
    gradeName = grade.name,
    topGradeLevel = tonumber(grade.level),
    topGradeCode = grade.code
  }
end

function MZOrgService.listOrgGoals(source, filters)
  filters = type(filters) == 'table' and filters or {}
  local orgCode = limitString(filters.orgCode or filters.org_code, 64)
  if orgCode then
    local org = MZOrgRepository.getOrgByCode(orgCode)
    if not org then return false, 'invalid_org' end
    if not (isOwner(source) or hasStaffView(source) or hasAnyOrgCapability(source, orgCode, { 'goals.view', 'goals.manage', 'org.view' })) then
      return false, 'forbidden'
    end
  elseif not isOwner(source) and not hasStaffView(source) then
    return false, 'forbidden'
  end

  local rows = MZOrgRepository.listGoals({
    orgCode = orgCode,
    status = limitString(filters.status, 32),
    type = limitString(filters.type, 32),
    search = limitString(filters.search, 80),
    limit = normalizeNumber(filters.limit, 50, 1, 100),
    offset = normalizeNumber(filters.offset, 0, 0, 10000)
  })

  local out = {}
  for _, row in ipairs(rows or {}) do out[#out + 1] = normalizeGoalRow(row) end
  return out
end

function MZOrgService.getOrgGoal(source, goalId)
  goalId = tonumber(goalId)
  if not goalId then return nil end
  local row = MZOrgRepository.getGoalById(goalId)
  if not row then return nil end
  if not (isOwner(source) or hasStaffView(source) or hasAnyOrgCapability(source, row.org_code, { 'goals.view', 'goals.manage', 'org.view' })) then
    return nil
  end
  return normalizeGoalRow(row)
end

function MZOrgService.createOrgGoal(source, orgCode, payload)
  orgCode = limitString(orgCode, 64)
  payload = type(payload) == 'table' and payload or {}
  if not orgCode then return false, 'invalid_org' end
  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'invalid_org' end
  if not (isOwner(source) or hasStaffManage(source) or hasAnyOrgCapability(source, orgCode, { 'goals.manage', 'manage.goals' })) then
    return false, 'forbidden'
  end

  local title = limitString(payload.title, 120)
  if not title then return false, 'invalid_title' end
  local target = normalizeNumber(payload.target, 1, 1, 100000)
  local actor = MZPlayerService.getPlayer(source)
  local row = MZOrgRepository.createGoal(org, {
    title = title,
    description = limitString(payload.description, 1000),
    type = limitString(payload.type, 32) or 'manual',
    status = 'active',
    target = target,
    progress = 0,
    starts_at = limitString(payload.startsAt or payload.starts_at, 32),
    ends_at = limitString(payload.endsAt or payload.ends_at, 32),
    created_by_citizenid = actor and actor.citizenid or nil,
    created_by_name = getPlayerDisplayName(actor, source)
  })

  if not row then return false, 'create_failed' end
  logDetailed('orgs', 'org.goal.create', {
    actor = makeActor(source),
    target = { type = 'org_goal', id = tostring(row.id) },
    context = { org_code = orgCode },
    after = { title = title, target = target, type = payload.type or 'manual' }
  })
  return true, normalizeGoalRow(row)
end

function MZOrgService.createRecruitment(source, orgCode, payload)
  local src = normalizeSource(source)
  orgCode = limitString(orgCode, 64)
  payload = type(payload) == 'table' and payload or {}
  local targetCitizenId = limitString(payload.citizenid or payload.targetCitizenId or payload.target_citizenid, 64)

  if not src then return false, 'invalid_source' end
  if not orgCode then return false, 'invalid_org' end
  if not targetCitizenId then return false, 'invalid_target' end

  local actor = MZPlayerService.getPlayer(src)
  if not actor or not actor.citizenid then return false, 'player_not_loaded' end
  if tostring(actor.citizenid) == tostring(targetCitizenId) then return false, 'self_target' end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'invalid_org' end
  if not canManageRecruitment(src, orgCode) then
    logBlocked('org.recruitment.create.blocked', src, orgCode, targetCitizenId, 'forbidden')
    return false, 'forbidden'
  end

  local targetRow = getPlayerRowByCitizenId(targetCitizenId)
  if not targetRow then return false, 'target_not_found' end
  local existingMembership = MZOrgRepository.getPlayerMembership(targetCitizenId, org.id)
  if existingMembership and asBool(existingMembership.active) then return false, 'already_member' end
  if MZOrgRepository.findPendingRecruitment(orgCode, targetCitizenId) then return false, 'already_pending' end

  local grade = nil
  local gradeErr = nil
  if payload.desiredGradeLevel or payload.gradeLevel or payload.desiredGradeCode or payload.gradeCode then
    grade, gradeErr = resolveGrade(org, {
      gradeLevel = payload.desiredGradeLevel or payload.gradeLevel,
      gradeCode = payload.desiredGradeCode or payload.gradeCode
    })
    if not grade then return false, gradeErr or 'invalid_grade' end
    local allowed, block = validateGradeForActor(src, org, grade)
    if not allowed then return false, block end
  end

  local row = MZOrgRepository.createRecruitmentApplication({
    org_code = orgCode,
    target_citizenid = targetCitizenId,
    target_name = getPlayerNameFromRow(targetRow),
    status = 'pending',
    desired_grade_level = grade and tonumber(grade.level) or nil,
    desired_grade_code = grade and grade.code or nil,
    note = limitString(payload.note, 1000),
    created_by_citizenid = actor.citizenid,
    created_by_name = getPlayerDisplayName(actor, src),
    metadata = {
      created_source = src
    }
  })

  if not row then return false, 'create_failed' end
  logDetailed('orgs', 'org.recruitment.create', {
    actor = makeActor(src),
    target = { type = 'player', id = targetCitizenId, citizenid = targetCitizenId, name = getPlayerNameFromRow(targetRow) },
    context = { org_code = orgCode, recruitment_id = row.id },
    after = { status = 'pending', desired_grade_level = grade and tonumber(grade.level) or nil, desired_grade_code = grade and grade.code or nil }
  })

  return true, normalizeRecruitmentRow(row)
end

function MZOrgService.listRecruitment(source, orgCode, filters)
  local src = normalizeSource(source)
  orgCode = limitString(orgCode, 64)
  filters = type(filters) == 'table' and filters or {}
  if not src then return false, 'invalid_source' end
  if not orgCode then return false, 'invalid_org' end
  if not MZOrgRepository.getOrgByCode(orgCode) then return false, 'invalid_org' end
  if not canViewRecruitment(src, orgCode) then return false, 'forbidden' end

  local rows = MZOrgRepository.listRecruitment({
    orgCode = orgCode,
    status = limitString(filters.status, 32),
    search = limitString(filters.search, 80),
    limit = normalizeNumber(filters.limit, 50, 1, 100),
    offset = normalizeNumber(filters.offset, 0, 0, 10000)
  })

  local out = {}
  for _, row in ipairs(rows or {}) do out[#out + 1] = normalizeRecruitmentRow(row) end
  return out
end

function MZOrgService.getRecruitment(source, recruitmentId)
  local src = normalizeSource(source)
  local id = tonumber(recruitmentId)
  if not src then return false, 'invalid_source' end
  if not id then return false, 'invalid_recruitment' end

  local row = MZOrgRepository.getRecruitmentById(id)
  if not row then return false, 'recruitment_not_found' end
  if not canViewRecruitment(src, row.org_code) then return false, 'forbidden' end
  return normalizeRecruitmentRow(row)
end

function MZOrgService.approveRecruitment(source, recruitmentId, options)
  local src = normalizeSource(source)
  local id = tonumber(recruitmentId)
  options = type(options) == 'table' and options or {}
  if not src then return false, 'invalid_source' end
  if not id then return false, 'invalid_recruitment' end

  local row = MZOrgRepository.getRecruitmentById(id)
  if not row then return false, 'recruitment_not_found' end
  if row.status ~= 'pending' then return false, 'invalid_status' end

  local org = MZOrgRepository.getOrgByCode(row.org_code)
  if not org then return false, 'invalid_org' end
  if not canManageRecruitment(src, row.org_code) then
    logBlocked('org.recruitment.approve.blocked', src, row.org_code, row.target_citizenid, 'forbidden', { recruitment_id = id })
    return false, 'forbidden'
  end

  local targetRow = getPlayerRowByCitizenId(row.target_citizenid)
  if not targetRow then return false, 'target_not_found' end
  local existingMembership = MZOrgRepository.getPlayerMembership(row.target_citizenid, org.id)
  if existingMembership and asBool(existingMembership.active) then return false, 'already_member' end

  local grade, gradeErr, grades = resolveGrade(org, {
    gradeLevel = options.gradeLevel or options.grade_level or row.desired_grade_level,
    gradeCode = options.gradeCode or options.grade_code or row.desired_grade_code
  })
  if not grade then return false, gradeErr or 'invalid_grade' end

  local allowed, block = validateGradeForActor(src, org, grade, grades)
  if not allowed then
    logBlocked('org.recruitment.approve.blocked', src, row.org_code, row.target_citizenid, block, { recruitment_id = id })
    return false, block
  end

  local addOk, addDataOrErr = MZOrgService.addMember(row.target_citizenid, row.org_code, grade.level, {
    is_primary = true,
    duty = false
  }, src)
  if not addOk then return false, addDataOrErr or 'approve_failed' end

  local actor = MZPlayerService.getPlayer(src)
  local updated = MZOrgRepository.updateRecruitmentStatus(id, 'approved', {
    reviewed_by_citizenid = actor and actor.citizenid or nil,
    reviewed_by_name = getPlayerDisplayName(actor, src),
    decision_note = limitString(options.note or options.decisionNote, 1000),
    metadata = {
      approved_grade_level = tonumber(grade.level),
      approved_grade_code = grade.code
    }
  })

  logDetailed('orgs', 'org.recruitment.approve', {
    actor = makeActor(src),
    target = { type = 'player', id = row.target_citizenid, citizenid = row.target_citizenid, name = getPlayerNameFromRow(targetRow) },
    context = { org_code = row.org_code, recruitment_id = id },
    before = { status = 'pending' },
    after = { status = 'approved', grade_level = tonumber(grade.level), grade_code = grade.code }
  })

  return true, {
    recruitment = normalizeRecruitmentRow(updated),
    member = addDataOrErr
  }
end

function MZOrgService.rejectRecruitment(source, recruitmentId, reason)
  local src = normalizeSource(source)
  local id = tonumber(recruitmentId)
  if not src then return false, 'invalid_source' end
  if not id then return false, 'invalid_recruitment' end

  local row = MZOrgRepository.getRecruitmentById(id)
  if not row then return false, 'recruitment_not_found' end
  if row.status ~= 'pending' then return false, 'invalid_status' end
  if not canManageRecruitment(src, row.org_code) then
    logBlocked('org.recruitment.reject.blocked', src, row.org_code, row.target_citizenid, 'forbidden', { recruitment_id = id })
    return false, 'forbidden'
  end

  local actor = MZPlayerService.getPlayer(src)
  local updated = MZOrgRepository.updateRecruitmentStatus(id, 'rejected', {
    reviewed_by_citizenid = actor and actor.citizenid or nil,
    reviewed_by_name = getPlayerDisplayName(actor, src),
    decision_note = limitString(reason, 1000),
    metadata = {}
  })

  logDetailed('orgs', 'org.recruitment.reject', {
    actor = makeActor(src),
    target = { type = 'player', id = row.target_citizenid, citizenid = row.target_citizenid },
    context = { org_code = row.org_code, recruitment_id = id },
    before = { status = 'pending' },
    after = { status = 'rejected' },
    meta = { reason = limitString(reason, 1000) }
  })

  return true, normalizeRecruitmentRow(updated)
end

function MZOrgService.cancelRecruitment(source, recruitmentId, reason)
  local src = normalizeSource(source)
  local id = tonumber(recruitmentId)
  if not src then return false, 'invalid_source' end
  if not id then return false, 'invalid_recruitment' end

  local row = MZOrgRepository.getRecruitmentById(id)
  if not row then return false, 'recruitment_not_found' end
  if row.status ~= 'pending' then return false, 'invalid_status' end
  if not canManageRecruitment(src, row.org_code) then return false, 'forbidden' end

  local actor = MZPlayerService.getPlayer(src)
  local updated = MZOrgRepository.updateRecruitmentStatus(id, 'cancelled', {
    reviewed_by_citizenid = actor and actor.citizenid or nil,
    reviewed_by_name = getPlayerDisplayName(actor, src),
    decision_note = limitString(reason, 1000),
    metadata = {}
  })

  logDetailed('orgs', 'org.recruitment.cancel', {
    actor = makeActor(src),
    target = { type = 'player', id = row.target_citizenid, citizenid = row.target_citizenid },
    context = { org_code = row.org_code, recruitment_id = id },
    before = { status = 'pending' },
    after = { status = 'cancelled' },
    meta = { reason = limitString(reason, 1000) }
  })

  return true, normalizeRecruitmentRow(updated)
end

function MZOrgService.createOrgFromTemplate(source, payload)
  local src = normalizeSource(source)
  payload = type(payload) == 'table' and payload or {}

  if not src then return false, 'invalid_source' end

  local actor = MZPlayerService.getPlayer(src)
  if not actor or not actor.citizenid then
    logOrgCreateBlocked(src, nil, 'player_not_loaded')
    return false, 'player_not_loaded'
  end

  local orgType = normalizeOrgCreateType(payload.type or payload.orgType or payload.typeCode)
  local code = normalizeOrgCreateCode(payload.code or payload.orgCode)
  local name = normalizeOrgCreateName(payload.name or payload.label)
  local reason = limitString(payload.reason, 255)

  if not orgType then
    logOrgCreateBlocked(src, code, 'invalid_type', { requested_type = payload.type or payload.orgType or payload.typeCode })
    return false, 'invalid_type'
  end

  if not code then
    logOrgCreateBlocked(src, nil, 'invalid_code')
    return false, 'invalid_code'
  end

  if not name then
    logOrgCreateBlocked(src, code, 'invalid_name')
    return false, 'invalid_name'
  end

  if not canCreateOrgs(src) then
    logOrgCreateBlocked(src, code, 'forbidden', { org_type = orgType })
    return false, 'forbidden'
  end

  local template = OrgCreationTemplates[orgType]
  if not template then
    logOrgCreateBlocked(src, code, 'template_not_found', { org_type = orgType })
    return false, 'template_not_found'
  end

  local typeRow = MZOrgRepository.getOrgTypeByCode(orgType)
  if not typeRow then
    logOrgCreateBlocked(src, code, 'invalid_type', { org_type = orgType })
    return false, 'invalid_type'
  end

  if MZOrgRepository.getOrgByCode(code) then
    logOrgCreateBlocked(src, code, 'org_already_exists', { org_type = orgType })
    return false, 'org_already_exists'
  end

  local hasSharedAccount = template.requires_shared_account == true
    or asBool(payload.hasSharedAccount)
    or asBool(payload.has_shared_account)
    or template.has_shared_account == true
  local hasSalary = template.has_salary == true or asBool(payload.hasSalary) or asBool(payload.has_salary)
  local hasStorage = template.has_storage == true or asBool(payload.hasStorage) or asBool(payload.has_storage)

  local org = MZOrgRepository.createOrg({
    type_id = typeRow.id,
    code = code,
    name = name,
    is_public = false,
    requires_whitelist = true,
    has_salary = hasSalary,
    has_shared_account = hasSharedAccount,
    has_storage = hasStorage,
    active = true,
    config = {
      created_from_template = orgType,
      created_by = tostring(actor.citizenid),
      created_reason = reason
    }
  })

  if not org then
    logOrgCreateBlocked(src, code, 'create_org_failed', { org_type = orgType })
    return false, 'create_org_failed'
  end

  local gradesByLevel = {}
  local previousGrade = nil

  for _, gradeDef in ipairs(template.grades or {}) do
    local salary = hasSalary and (tonumber(gradeDef.salary) or 0) or 0
    local grade = MZOrgRepository.createGrade(org.id, {
      level = gradeDef.level,
      code = gradeDef.code,
      name = gradeDef.name,
      salary = salary,
      inherits_grade_id = previousGrade and previousGrade.id or nil,
      priority = gradeDef.priority or gradeDef.level,
      config = {
        template = orgType
      }
    })

    if not grade then
      logOrgCreateBlocked(src, code, 'create_grade_failed', {
        org_type = orgType,
        grade_level = gradeDef.level,
        grade_code = gradeDef.code
      })
      return false, 'create_grade_failed'
    end

    gradesByLevel[tonumber(grade.level)] = grade
    previousGrade = grade
  end

  local permissionOk = true
  for _, permission in ipairs(template.base_permissions or {}) do
    local okSet = pcall(function()
      MZOrgRepository.setPermission(org.id, nil, permission, true)
    end)
    if not okSet then permissionOk = false end
  end

  for level, permissions in pairs(template.grade_permissions or {}) do
    local grade = gradesByLevel[tonumber(level)]
    if grade then
      for _, permission in ipairs(permissions or {}) do
        local okSet = pcall(function()
          MZOrgRepository.setPermission(org.id, grade.id, permission, true)
        end)
        if not okSet then permissionOk = false end
      end
    end
  end

  if not permissionOk then
    logOrgCreateBlocked(src, code, 'create_permission_failed', { org_type = orgType, org_id = org.id })
    return false, 'create_permission_failed'
  end

  if hasSharedAccount then
    if not MZOrgAccountService or not MZOrgAccountService.getBalance then
      logOrgCreateBlocked(src, code, 'create_account_failed', { org_type = orgType, org_id = org.id })
      return false, 'create_account_failed'
    end

    local accountOk, accountErr = MZOrgAccountService.getBalance(code)
    if accountOk ~= true then
      logOrgCreateBlocked(src, code, 'create_account_failed', {
        org_type = orgType,
        org_id = org.id,
        account_error = accountErr
      })
      return false, 'create_account_failed'
    end
  end

  logDetailed('orgs', 'org.create', {
    actor = makeActor(src),
    target = {
      type = 'org',
      id = tostring(org.id),
      code = code,
      name = name
    },
    context = {
      org_id = org.id,
      org_code = code,
      org_type = orgType
    },
    after = {
      name = name,
      type = orgType,
      has_salary = hasSalary,
      has_shared_account = hasSharedAccount,
      has_storage = hasStorage,
      grades = #template.grades
    },
    meta = {
      reason = reason,
      template = orgType
    }
  })

  return true, {
    org = normalizeOrgRow(MZOrgRepository.getOrgByCode(code) or org),
    grades = template.grades,
    template = orgType,
    hasSharedAccount = hasSharedAccount,
    hasSalary = hasSalary,
    hasStorage = hasStorage
  }
end

function MZOrgService.updateOrgBasicInfo(source, orgCode, payload)
  local src = normalizeSource(source)
  orgCode = limitString(orgCode, 64)
  payload = type(payload) == 'table' and payload or {}

  if not src then return false, 'invalid_source' end

  local actor = MZPlayerService.getPlayer(src)
  if not actor or not actor.citizenid then
    logOrgUpdateBasicBlocked(src, orgCode, 'player_not_loaded')
    return false, 'player_not_loaded'
  end

  if not orgCode then
    logOrgUpdateBasicBlocked(src, nil, 'invalid_org')
    return false, 'invalid_org'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    logOrgUpdateBasicBlocked(src, orgCode, 'org_not_found')
    return false, 'org_not_found'
  end

  if not canUpdateOrgBasicInfo(src) then
    logOrgUpdateBasicBlocked(src, orgCode, 'forbidden')
    return false, 'forbidden'
  end

  local name = normalizeOrgBasicName(payload.name)
  if not name then
    logOrgUpdateBasicBlocked(src, orgCode, 'invalid_name')
    return false, 'invalid_name'
  end

  local status = normalizeOrgBasicStatus(payload.status, org)
  if not status then
    logOrgUpdateBasicBlocked(src, orgCode, 'invalid_status', { requested_status = payload.status })
    return false, 'invalid_status'
  end

  local reason = limitString(payload.reason, 255)
  local before = {
    name = org.name,
    status = asBool(org.active) and (asBool(org.is_public) and 'public' or 'private') or 'inactive',
    is_public = asBool(org.is_public),
    has_salary = asBool(org.has_salary),
    has_shared_account = asBool(org.has_shared_account),
    has_storage = asBool(org.has_storage),
    active = asBool(org.active)
  }

  local function boolPayload(primary, legacy, current)
    if primary ~= nil then return asBool(primary) end
    if legacy ~= nil then return asBool(legacy) end
    return asBool(current)
  end

  local updateData = {
    name = name,
    is_public = status.is_public,
    has_salary = boolPayload(payload.hasSalary, payload.has_salary, org.has_salary),
    has_shared_account = boolPayload(payload.hasSharedAccount, payload.has_shared_account, org.has_shared_account),
    has_storage = boolPayload(payload.hasStorage, payload.has_storage, org.has_storage),
    active = status.active
  }

  local updated = MZOrgRepository.updateOrgBasicInfo(orgCode, updateData)
  if not updated then
    logOrgUpdateBasicBlocked(src, orgCode, 'update_org_failed')
    return false, 'update_org_failed'
  end

  if updateData.has_shared_account and MZOrgAccountService and MZOrgAccountService.getBalance then
    local accountOk, accountErr = MZOrgAccountService.getBalance(orgCode)
    if accountOk ~= true then
      logOrgUpdateBasicBlocked(src, orgCode, 'update_org_failed', { account_error = accountErr })
      return false, 'update_org_failed'
    end
  end

  local after = {
    name = updated.name,
    status = asBool(updated.active) and (asBool(updated.is_public) and 'public' or 'private') or 'inactive',
    is_public = asBool(updated.is_public),
    has_salary = asBool(updated.has_salary),
    has_shared_account = asBool(updated.has_shared_account),
    has_storage = asBool(updated.has_storage),
    active = asBool(updated.active)
  }

  logDetailed('orgs', 'org.update_basic', {
    actor = makeActor(src),
    target = {
      type = 'org',
      id = tostring(updated.id),
      code = orgCode,
      name = updated.name
    },
    context = {
      org_id = updated.id,
      org_code = orgCode,
      org_type = updated.type_code
    },
    before = before,
    after = after,
    meta = {
      reason = reason
    }
  })

  return true, {
    org = normalizeOrgRow(updated),
    before = before,
    after = after
  }
end

function MZOrgService.createOrgGrade(source, orgCode, payload)
  local src = normalizeSource(source)
  orgCode = limitString(orgCode, 64)
  payload = type(payload) == 'table' and payload or {}

  if not src then return false, 'invalid_source' end

  local actor = MZPlayerService.getPlayer(src)
  if not actor or not actor.citizenid then
    logOrgGradeBlocked('org.grade.create.blocked', src, orgCode, nil, 'player_not_loaded')
    return false, 'player_not_loaded'
  end

  if not orgCode then
    logOrgGradeBlocked('org.grade.create.blocked', src, nil, nil, 'invalid_org')
    return false, 'invalid_org'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    logOrgGradeBlocked('org.grade.create.blocked', src, orgCode, nil, 'org_not_found')
    return false, 'org_not_found'
  end

  if not asBool(org.active) then
    logOrgGradeBlocked('org.grade.create.blocked', src, orgCode, nil, 'org_archived')
    return false, 'org_archived'
  end

  if not canUpdateOrgBasicInfo(src) then
    logOrgGradeBlocked('org.grade.create.blocked', src, orgCode, nil, 'forbidden')
    return false, 'forbidden'
  end

  local code = normalizeOrgGradeCode(payload.code)
  if not code then
    logOrgGradeBlocked('org.grade.create.blocked', src, orgCode, nil, 'invalid_code')
    return false, 'invalid_code'
  end

  local name = normalizeOrgGradeName(payload.name)
  if not name then
    logOrgGradeBlocked('org.grade.create.blocked', src, orgCode, nil, 'invalid_name')
    return false, 'invalid_name'
  end

  local level = normalizeOrgGradeLevel(payload.level)
  if not level then
    logOrgGradeBlocked('org.grade.create.blocked', src, orgCode, nil, 'invalid_level')
    return false, 'invalid_level'
  end

  local salary = normalizeOrgGradeSalary(payload.salary or 0)
  if not salary then
    logOrgGradeBlocked('org.grade.create.blocked', src, orgCode, nil, 'invalid_salary')
    return false, 'invalid_salary'
  end

  if MZOrgRepository.getGradeByCode(org.id, code, true) then
    logOrgGradeBlocked('org.grade.create.blocked', src, orgCode, nil, 'grade_code_conflict', { code = code })
    return false, 'grade_code_conflict'
  end

  if MZOrgRepository.getGradeByLevel(org.id, level, true) then
    logOrgGradeBlocked('org.grade.create.blocked', src, orgCode, nil, 'grade_level_conflict', { level = level })
    return false, 'grade_level_conflict'
  end

  local grades = MZOrgRepository.getGradesForOrg(org.id)
  local currentTopLevel = maxGradeLevel(grades) or 0
  if level > currentTopLevel and not canStaffSetLeader(src, orgCode) then
    logOrgGradeBlocked('org.grade.create.blocked', src, orgCode, nil, 'leader_permission_required', {
      requested_level = level,
      current_top_level = currentTopLevel
    })
    return false, 'leader_permission_required'
  end

  local inheritsGradeId = nil
  if payload.inheritsLevel ~= nil and tostring(payload.inheritsLevel) ~= '' then
    local inherits, inheritErr = getInheritanceGrade(org.id, payload.inheritsLevel)
    if not inherits then
      logOrgGradeBlocked('org.grade.create.blocked', src, orgCode, nil, inheritErr or 'invalid_inheritance')
      return false, inheritErr or 'invalid_inheritance'
    end
    inheritsGradeId = inherits.id
  end

  local priority = normalizeOrgGradePriority(payload.priority, level)
  local reason = limitString(payload.reason, 255)
  local grade = MZOrgRepository.createGrade(org.id, {
    level = level,
    code = code,
    name = name,
    salary = salary,
    inherits_grade_id = inheritsGradeId,
    priority = priority,
    config = {}
  })

  if not grade then
    logOrgGradeBlocked('org.grade.create.blocked', src, orgCode, nil, 'create_grade_failed')
    return false, 'create_grade_failed'
  end

  local after = gradeSnapshot(grade, 0)
  logDetailed('orgs', 'org.grade.create', {
    actor = makeActor(src),
    target = {
      type = 'org_grade',
      id = tostring(grade.id),
      code = code,
      name = name
    },
    context = {
      org_id = org.id,
      org_code = orgCode
    },
    after = after,
    meta = {
      reason = reason
    }
  })

  return true, {
    grade = after
  }
end

function MZOrgService.updateOrgGradeBasic(source, orgCode, gradeId, payload)
  local src = normalizeSource(source)
  orgCode = limitString(orgCode, 64)
  gradeId = tonumber(gradeId)
  payload = type(payload) == 'table' and payload or {}

  if not src then return false, 'invalid_source' end

  local actor = MZPlayerService.getPlayer(src)
  if not actor or not actor.citizenid then
    logOrgGradeBlocked('org.grade.update.blocked', src, orgCode, gradeId, 'player_not_loaded')
    return false, 'player_not_loaded'
  end

  if not orgCode then
    logOrgGradeBlocked('org.grade.update.blocked', src, nil, gradeId, 'invalid_org')
    return false, 'invalid_org'
  end

  if not gradeId then
    logOrgGradeBlocked('org.grade.update.blocked', src, orgCode, nil, 'invalid_grade')
    return false, 'invalid_grade'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    logOrgGradeBlocked('org.grade.update.blocked', src, orgCode, gradeId, 'org_not_found')
    return false, 'org_not_found'
  end

  if not asBool(org.active) then
    logOrgGradeBlocked('org.grade.update.blocked', src, orgCode, gradeId, 'org_archived')
    return false, 'org_archived'
  end

  if not canUpdateOrgBasicInfo(src) then
    logOrgGradeBlocked('org.grade.update.blocked', src, orgCode, gradeId, 'forbidden')
    return false, 'forbidden'
  end

  local grade = MZOrgRepository.getOrgGradeById(org.id, gradeId)
  if not grade then
    logOrgGradeBlocked('org.grade.update.blocked', src, orgCode, gradeId, 'grade_not_found')
    return false, 'grade_not_found'
  end

  if not asBool(grade.active) then
    logOrgGradeBlocked('org.grade.update.blocked', src, orgCode, gradeId, 'grade_already_disabled')
    return false, 'grade_already_disabled'
  end

  local name = normalizeOrgGradeName(payload.name)
  if not name then
    logOrgGradeBlocked('org.grade.update.blocked', src, orgCode, gradeId, 'invalid_name')
    return false, 'invalid_name'
  end

  local level = normalizeOrgGradeLevel(payload.level)
  if not level then
    logOrgGradeBlocked('org.grade.update.blocked', src, orgCode, gradeId, 'invalid_level')
    return false, 'invalid_level'
  end

  local salary = normalizeOrgGradeSalary(payload.salary or 0)
  if not salary then
    logOrgGradeBlocked('org.grade.update.blocked', src, orgCode, gradeId, 'invalid_salary')
    return false, 'invalid_salary'
  end

  local levelConflict = MZOrgRepository.getGradeByLevel(org.id, level, true)
  if levelConflict and tonumber(levelConflict.id) ~= tonumber(grade.id) then
    logOrgGradeBlocked('org.grade.update.blocked', src, orgCode, gradeId, 'grade_level_conflict', { level = level })
    return false, 'grade_level_conflict'
  end

  local grades = MZOrgRepository.getGradesForOrg(org.id)
  local currentTop = topGrade(grades)
  local currentTopLevel = currentTop and tonumber(currentTop.level) or 0
  local oldLevel = tonumber(grade.level) or 0
  local isCurrentTop = currentTop and tonumber(currentTop.id) == tonumber(grade.id)
  local changesLeadership = (isCurrentTop and level ~= oldLevel) or (not isCurrentTop and level > currentTopLevel)

  if changesLeadership and not canStaffSetLeader(src, orgCode) then
    logOrgGradeBlocked('org.grade.update.blocked', src, orgCode, gradeId, 'leader_permission_required', {
      requested_level = level,
      current_top_level = currentTopLevel,
      old_level = oldLevel
    })
    return false, 'leader_permission_required'
  end

  local inheritsGradeId = nil
  if payload.inheritsLevel ~= nil and tostring(payload.inheritsLevel) ~= '' then
    local inherits, inheritErr = getInheritanceGrade(org.id, payload.inheritsLevel)
    if not inherits then
      logOrgGradeBlocked('org.grade.update.blocked', src, orgCode, gradeId, inheritErr or 'invalid_inheritance')
      return false, inheritErr or 'invalid_inheritance'
    end

    if tonumber(inherits.id) == tonumber(grade.id) then
      logOrgGradeBlocked('org.grade.update.blocked', src, orgCode, gradeId, 'invalid_inheritance')
      return false, 'invalid_inheritance'
    end

    if wouldCreateInheritanceCycle(org.id, grade.id, inherits.id) then
      logOrgGradeBlocked('org.grade.update.blocked', src, orgCode, gradeId, 'inheritance_cycle')
      return false, 'inheritance_cycle'
    end

    inheritsGradeId = inherits.id
  end

  local memberCount = MZOrgRepository.countMembersByGrade(org.id, grade.id)
  local before = gradeSnapshot(grade, memberCount)
  local priority = normalizeOrgGradePriority(payload.priority, level)
  local reason = limitString(payload.reason, 255)
  local updated = MZOrgRepository.updateOrgGradeBasic(org.id, grade.id, {
    level = level,
    name = name,
    salary = salary,
    inherits_grade_id = inheritsGradeId,
    priority = priority
  })

  if not updated then
    logOrgGradeBlocked('org.grade.update.blocked', src, orgCode, gradeId, 'update_grade_failed')
    return false, 'update_grade_failed'
  end

  local after = gradeSnapshot(updated, memberCount)
  logDetailed('orgs', 'org.grade.update', {
    actor = makeActor(src),
    target = {
      type = 'org_grade',
      id = tostring(updated.id),
      code = updated.code,
      name = updated.name
    },
    context = {
      org_id = org.id,
      org_code = orgCode
    },
    before = before,
    after = after,
    meta = {
      reason = reason
    }
  })

  return true, {
    grade = after,
    before = before,
    after = after
  }
end

function MZOrgService.archiveOrg(source, orgCode, reason)
  local src = normalizeSource(source)
  orgCode = limitString(orgCode, 64)
  reason = limitString(reason, 255)

  if not src then return false, 'invalid_source' end

  local actor = MZPlayerService.getPlayer(src)
  if not actor or not actor.citizenid then
    logOrgArchiveBlocked('org.archive.blocked', src, orgCode, 'player_not_loaded')
    return false, 'player_not_loaded'
  end

  if not orgCode then
    logOrgArchiveBlocked('org.archive.blocked', src, nil, 'invalid_org')
    return false, 'invalid_org'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    logOrgArchiveBlocked('org.archive.blocked', src, orgCode, 'org_not_found')
    return false, 'org_not_found'
  end

  if not canUpdateOrgBasicInfo(src) then
    logOrgArchiveBlocked('org.archive.blocked', src, orgCode, 'forbidden')
    return false, 'forbidden'
  end

  if tostring(org.type_code or '') == 'staff' and not isOwner(src) then
    logOrgArchiveBlocked('org.archive.blocked', src, orgCode, 'protected_org')
    return false, 'protected_org'
  end

  if not asBool(org.active) then
    logOrgArchiveBlocked('org.archive.blocked', src, orgCode, 'org_already_archived')
    return false, 'org_already_archived'
  end

  local before = normalizeOrgRow(org)
  local updated = MZOrgRepository.setOrgActive(orgCode, false)
  if not updated then
    logOrgArchiveBlocked('org.archive.blocked', src, orgCode, 'archive_org_failed')
    return false, 'archive_org_failed'
  end

  local after = normalizeOrgRow(updated)
  logDetailed('orgs', 'org.archive', {
    actor = makeActor(src),
    target = {
      type = 'org',
      id = tostring(updated.id),
      code = orgCode,
      name = updated.name
    },
    context = {
      org_id = updated.id,
      org_code = orgCode
    },
    before = before,
    after = after,
    meta = {
      reason = reason
    }
  })

  return true, {
    org = after,
    before = before,
    after = after
  }
end

function MZOrgService.reactivateOrg(source, orgCode, reason)
  local src = normalizeSource(source)
  orgCode = limitString(orgCode, 64)
  reason = limitString(reason, 255)

  if not src then return false, 'invalid_source' end

  local actor = MZPlayerService.getPlayer(src)
  if not actor or not actor.citizenid then
    logOrgArchiveBlocked('org.reactivate.blocked', src, orgCode, 'player_not_loaded')
    return false, 'player_not_loaded'
  end

  if not orgCode then
    logOrgArchiveBlocked('org.reactivate.blocked', src, nil, 'invalid_org')
    return false, 'invalid_org'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    logOrgArchiveBlocked('org.reactivate.blocked', src, orgCode, 'org_not_found')
    return false, 'org_not_found'
  end

  if not canUpdateOrgBasicInfo(src) then
    logOrgArchiveBlocked('org.reactivate.blocked', src, orgCode, 'forbidden')
    return false, 'forbidden'
  end

  if asBool(org.active) then
    logOrgArchiveBlocked('org.reactivate.blocked', src, orgCode, 'org_already_active')
    return false, 'org_already_active'
  end

  local before = normalizeOrgRow(org)
  local updated = MZOrgRepository.setOrgActive(orgCode, true)
  if not updated then
    logOrgArchiveBlocked('org.reactivate.blocked', src, orgCode, 'reactivate_org_failed')
    return false, 'reactivate_org_failed'
  end

  local after = normalizeOrgRow(updated)
  logDetailed('orgs', 'org.reactivate', {
    actor = makeActor(src),
    target = {
      type = 'org',
      id = tostring(updated.id),
      code = orgCode,
      name = updated.name
    },
    context = {
      org_id = updated.id,
      org_code = orgCode
    },
    before = before,
    after = after,
    meta = {
      reason = reason
    }
  })

  return true, {
    org = after,
    before = before,
    after = after
  }
end

function MZOrgService.disableOrgGrade(source, orgCode, gradeId, reason)
  local src = normalizeSource(source)
  orgCode = limitString(orgCode, 64)
  gradeId = tonumber(gradeId)
  reason = limitString(reason, 255)

  if not src then return false, 'invalid_source' end

  local actor = MZPlayerService.getPlayer(src)
  if not actor or not actor.citizenid then
    logOrgGradeBlocked('org.grade.disable.blocked', src, orgCode, gradeId, 'player_not_loaded')
    return false, 'player_not_loaded'
  end

  if not orgCode then
    logOrgGradeBlocked('org.grade.disable.blocked', src, nil, gradeId, 'invalid_org')
    return false, 'invalid_org'
  end

  if not gradeId then
    logOrgGradeBlocked('org.grade.disable.blocked', src, orgCode, nil, 'invalid_grade')
    return false, 'invalid_grade'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    logOrgGradeBlocked('org.grade.disable.blocked', src, orgCode, gradeId, 'org_not_found')
    return false, 'org_not_found'
  end

  if not asBool(org.active) then
    logOrgGradeBlocked('org.grade.disable.blocked', src, orgCode, gradeId, 'org_archived')
    return false, 'org_archived'
  end

  if not canUpdateOrgBasicInfo(src) then
    logOrgGradeBlocked('org.grade.disable.blocked', src, orgCode, gradeId, 'forbidden')
    return false, 'forbidden'
  end

  local grade = MZOrgRepository.getOrgGradeById(org.id, gradeId)
  if not grade then
    logOrgGradeBlocked('org.grade.disable.blocked', src, orgCode, gradeId, 'grade_not_found')
    return false, 'grade_not_found'
  end

  if not asBool(grade.active) then
    logOrgGradeBlocked('org.grade.disable.blocked', src, orgCode, gradeId, 'grade_already_disabled')
    return false, 'grade_already_disabled'
  end

  local memberCount = MZOrgRepository.countMembersByGrade(org.id, grade.id)
  if memberCount > 0 then
    logOrgGradeBlocked('org.grade.disable.blocked', src, orgCode, gradeId, 'grade_in_use', { member_count = memberCount })
    return false, 'grade_in_use'
  end

  local currentTop = topGrade(MZOrgRepository.getGradesForOrg(org.id))
  if currentTop and tonumber(currentTop.id) == tonumber(grade.id) then
    logOrgGradeBlocked('org.grade.disable.blocked', src, orgCode, gradeId, 'top_grade_protected')
    return false, 'top_grade_protected'
  end

  local before = gradeSnapshot(grade, memberCount)
  local updated = MZOrgRepository.setOrgGradeActive(org.id, grade.id, false)
  if not updated then
    logOrgGradeBlocked('org.grade.disable.blocked', src, orgCode, gradeId, 'disable_grade_failed')
    return false, 'disable_grade_failed'
  end

  local after = gradeSnapshot(updated, memberCount)
  logDetailed('orgs', 'org.grade.disable', {
    actor = makeActor(src),
    target = {
      type = 'org_grade',
      id = tostring(updated.id),
      code = updated.code,
      name = updated.name
    },
    context = {
      org_id = org.id,
      org_code = orgCode
    },
    before = before,
    after = after,
    meta = {
      reason = reason
    }
  })

  return true, {
    grade = after,
    before = before,
    after = after
  }
end

function MZOrgService.reactivateOrgGrade(source, orgCode, gradeId, reason)
  local src = normalizeSource(source)
  orgCode = limitString(orgCode, 64)
  gradeId = tonumber(gradeId)
  reason = limitString(reason, 255)

  if not src then return false, 'invalid_source' end

  local actor = MZPlayerService.getPlayer(src)
  if not actor or not actor.citizenid then
    logOrgGradeBlocked('org.grade.reactivate.blocked', src, orgCode, gradeId, 'player_not_loaded')
    return false, 'player_not_loaded'
  end

  if not orgCode then
    logOrgGradeBlocked('org.grade.reactivate.blocked', src, nil, gradeId, 'invalid_org')
    return false, 'invalid_org'
  end

  if not gradeId then
    logOrgGradeBlocked('org.grade.reactivate.blocked', src, orgCode, nil, 'invalid_grade')
    return false, 'invalid_grade'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    logOrgGradeBlocked('org.grade.reactivate.blocked', src, orgCode, gradeId, 'org_not_found')
    return false, 'org_not_found'
  end

  if not asBool(org.active) then
    logOrgGradeBlocked('org.grade.reactivate.blocked', src, orgCode, gradeId, 'org_archived')
    return false, 'org_archived'
  end

  if not canUpdateOrgBasicInfo(src) then
    logOrgGradeBlocked('org.grade.reactivate.blocked', src, orgCode, gradeId, 'forbidden')
    return false, 'forbidden'
  end

  local grade = MZOrgRepository.getOrgGradeById(org.id, gradeId)
  if not grade then
    logOrgGradeBlocked('org.grade.reactivate.blocked', src, orgCode, gradeId, 'grade_not_found')
    return false, 'grade_not_found'
  end

  if asBool(grade.active) then
    logOrgGradeBlocked('org.grade.reactivate.blocked', src, orgCode, gradeId, 'grade_already_active')
    return false, 'grade_already_active'
  end

  local memberCount = MZOrgRepository.countMembersByGrade(org.id, grade.id)
  local before = gradeSnapshot(grade, memberCount)
  local updated = MZOrgRepository.setOrgGradeActive(org.id, grade.id, true)
  if not updated then
    logOrgGradeBlocked('org.grade.reactivate.blocked', src, orgCode, gradeId, 'reactivate_grade_failed')
    return false, 'reactivate_grade_failed'
  end

  local after = gradeSnapshot(updated, memberCount)
  logDetailed('orgs', 'org.grade.reactivate', {
    actor = makeActor(src),
    target = {
      type = 'org_grade',
      id = tostring(updated.id),
      code = updated.code,
      name = updated.name
    },
    context = {
      org_id = org.id,
      org_code = orgCode
    },
    before = before,
    after = after,
    meta = {
      reason = reason
    }
  })

  return true, {
    grade = after,
    before = before,
    after = after
  }
end

function MZOrgService.addOrgGradePermission(source, orgCode, gradeId, permission, reason)
  local src = normalizeSource(source)
  orgCode = limitString(orgCode, 64)
  gradeId = tonumber(gradeId)
  permission = normalizeOrgGradePermission(permission)
  reason = limitString(reason, 255)

  if not src then return false, 'invalid_source' end

  local actor = MZPlayerService.getPlayer(src)
  if not actor or not actor.citizenid then
    logOrgGradePermissionBlocked('org.grade.permission.add.blocked', src, orgCode, gradeId, permission, 'player_not_loaded')
    return false, 'player_not_loaded'
  end

  if not orgCode then
    logOrgGradePermissionBlocked('org.grade.permission.add.blocked', src, nil, gradeId, permission, 'invalid_org')
    return false, 'invalid_org'
  end

  if not gradeId then
    logOrgGradePermissionBlocked('org.grade.permission.add.blocked', src, orgCode, nil, permission, 'invalid_grade')
    return false, 'invalid_grade'
  end

  if not permission then
    logOrgGradePermissionBlocked('org.grade.permission.add.blocked', src, orgCode, gradeId, nil, 'invalid_permission')
    return false, 'invalid_permission'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    logOrgGradePermissionBlocked('org.grade.permission.add.blocked', src, orgCode, gradeId, permission, 'org_not_found')
    return false, 'org_not_found'
  end

  if not asBool(org.active) then
    logOrgGradePermissionBlocked('org.grade.permission.add.blocked', src, orgCode, gradeId, permission, 'org_archived')
    return false, 'org_archived'
  end

  if not canUpdateOrgBasicInfo(src) then
    logOrgGradePermissionBlocked('org.grade.permission.add.blocked', src, orgCode, gradeId, permission, 'forbidden')
    return false, 'forbidden'
  end

  local grade = MZOrgRepository.getOrgGradeById(org.id, gradeId)
  if not grade then
    logOrgGradePermissionBlocked('org.grade.permission.add.blocked', src, orgCode, gradeId, permission, 'grade_not_found')
    return false, 'grade_not_found'
  end

  if not asBool(grade.active) then
    logOrgGradePermissionBlocked('org.grade.permission.add.blocked', src, orgCode, gradeId, permission, 'grade_inactive')
    return false, 'grade_inactive'
  end

  local allowed, allowErr = validateGradePermissionChange(src, org, orgCode, permission)
  if not allowed then
    logOrgGradePermissionBlocked('org.grade.permission.add.blocked', src, orgCode, gradeId, permission, allowErr)
    return false, allowErr
  end

  local existing = MZOrgRepository.getOrgGradePermission(org.id, grade.id, permission)
  if existing and asBool(existing.allow) then
    logOrgGradePermissionBlocked('org.grade.permission.add.blocked', src, orgCode, gradeId, permission, 'permission_already_exists')
    return false, 'permission_already_exists'
  end

  local before = directPermissionSnapshot(org.id, grade.id)
  local ok = MZOrgRepository.setPermission(org.id, grade.id, permission, true)
  local after = directPermissionSnapshot(org.id, grade.id)
  if not ok and not MZOrgRepository.getOrgGradePermission(org.id, grade.id, permission) then
    logOrgGradePermissionBlocked('org.grade.permission.add.blocked', src, orgCode, gradeId, permission, 'add_permission_failed')
    return false, 'add_permission_failed'
  end

  logDetailed('orgs', 'org.grade.permission.add', {
    actor = makeActor(src),
    target = {
      type = 'org_grade_permission',
      id = tostring(grade.id),
      code = grade.code,
      name = grade.name,
      permission = permission
    },
    context = {
      org_id = org.id,
      org_code = orgCode
    },
    before = before,
    after = after,
    meta = {
      reason = reason,
      permission = permission
    }
  })

  return true, {
    gradeId = grade.id,
    permission = permission,
    permissions = after,
    before = before,
    after = after
  }
end

function MZOrgService.removeOrgGradePermission(source, orgCode, gradeId, permission, reason)
  local src = normalizeSource(source)
  orgCode = limitString(orgCode, 64)
  gradeId = tonumber(gradeId)
  permission = normalizeOrgGradePermission(permission)
  reason = limitString(reason, 255)

  if not src then return false, 'invalid_source' end

  local actor = MZPlayerService.getPlayer(src)
  if not actor or not actor.citizenid then
    logOrgGradePermissionBlocked('org.grade.permission.remove.blocked', src, orgCode, gradeId, permission, 'player_not_loaded')
    return false, 'player_not_loaded'
  end

  if not orgCode then
    logOrgGradePermissionBlocked('org.grade.permission.remove.blocked', src, nil, gradeId, permission, 'invalid_org')
    return false, 'invalid_org'
  end

  if not gradeId then
    logOrgGradePermissionBlocked('org.grade.permission.remove.blocked', src, orgCode, nil, permission, 'invalid_grade')
    return false, 'invalid_grade'
  end

  if not permission then
    logOrgGradePermissionBlocked('org.grade.permission.remove.blocked', src, orgCode, gradeId, nil, 'invalid_permission')
    return false, 'invalid_permission'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    logOrgGradePermissionBlocked('org.grade.permission.remove.blocked', src, orgCode, gradeId, permission, 'org_not_found')
    return false, 'org_not_found'
  end

  if not asBool(org.active) then
    logOrgGradePermissionBlocked('org.grade.permission.remove.blocked', src, orgCode, gradeId, permission, 'org_archived')
    return false, 'org_archived'
  end

  if not canUpdateOrgBasicInfo(src) then
    logOrgGradePermissionBlocked('org.grade.permission.remove.blocked', src, orgCode, gradeId, permission, 'forbidden')
    return false, 'forbidden'
  end

  local grade = MZOrgRepository.getOrgGradeById(org.id, gradeId)
  if not grade then
    logOrgGradePermissionBlocked('org.grade.permission.remove.blocked', src, orgCode, gradeId, permission, 'grade_not_found')
    return false, 'grade_not_found'
  end

  if not asBool(grade.active) then
    logOrgGradePermissionBlocked('org.grade.permission.remove.blocked', src, orgCode, gradeId, permission, 'grade_inactive')
    return false, 'grade_inactive'
  end

  local allowed, allowErr = validateGradePermissionChange(src, org, orgCode, permission)
  if not allowed then
    logOrgGradePermissionBlocked('org.grade.permission.remove.blocked', src, orgCode, gradeId, permission, allowErr)
    return false, allowErr
  end

  local existing = MZOrgRepository.getOrgGradePermission(org.id, grade.id, permission)
  if not existing or not asBool(existing.allow) then
    logOrgGradePermissionBlocked('org.grade.permission.remove.blocked', src, orgCode, gradeId, permission, 'permission_not_found')
    return false, 'permission_not_found'
  end

  local before = directPermissionSnapshot(org.id, grade.id)
  MZOrgRepository.setPermission(org.id, grade.id, permission, false)
  local after = directPermissionSnapshot(org.id, grade.id)

  logDetailed('orgs', 'org.grade.permission.remove', {
    actor = makeActor(src),
    target = {
      type = 'org_grade_permission',
      id = tostring(grade.id),
      code = grade.code,
      name = grade.name,
      permission = permission
    },
    context = {
      org_id = org.id,
      org_code = orgCode
    },
    before = before,
    after = after,
    meta = {
      reason = reason,
      permission = permission
    }
  })

  return true, {
    gradeId = grade.id,
    permission = permission,
    permissions = after,
    before = before,
    after = after
  }
end

function MZOrgService.createOrg(data, actor)
  return false, 'not_implemented'
end

function MZOrgService.createGrade(orgCode, data, actor)
  return false, 'not_implemented'
end

function MZOrgService.setOrgPermission(orgCode, permission, allow, actor)
  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'invalid_org' end
  MZOrgRepository.setPermission(org.id, nil, permission, allow)
  return true
end

function MZOrgService.setGradePermission(orgCode, gradeLevel, permission, allow, actor)
  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'invalid_org' end
  local grade = MZOrgRepository.getGradeByLevel(org.id, tonumber(gradeLevel))
  if not grade then return false, 'grade_not_found' end
  MZOrgRepository.setPermission(org.id, grade.id, permission, allow)
  return true
end

function MZOrgService.setPlayerPermission(citizenid, permission, allow, expiresAt, actor)
  citizenid = limitString(citizenid, 64)
  permission = limitString(permission, 128)
  if not citizenid then return false, 'invalid_target' end
  if not permission then return false, 'invalid_permission' end
  MZOrgRepository.setPlayerOverride(citizenid, permission, allow, expiresAt)
  return true
end

function MZOrgService.removePlayerPermission(citizenid, permission, actor)
  citizenid = limitString(citizenid, 64)
  permission = limitString(permission, 128)
  if not citizenid then return false, 'invalid_target' end
  if not permission then return false, 'invalid_permission' end
  MZOrgRepository.removePlayerOverride(citizenid, permission)
  return true
end
