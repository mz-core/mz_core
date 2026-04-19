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

local function logOrgAction(action, actor, target, data)
  if not MZLogService then return end
  MZLogService.create('orgs', action, actor, target, data or {})
end

local function normalizeActor(actor)
  if actor == nil then
    return 'system'
  end

  if type(actor) == 'number' then
    if actor == 0 then
      return 'console'
    end

    local player = MZPlayerService.getPlayer(actor)
    if player and player.citizenid then
      return player.citizenid
    end

    return ('source:%s'):format(actor)
  end

  return tostring(actor)
end

local function buildOrgDetailedActor(actor)
  if actor == nil then
    return {
      type = 'system',
      id = 'system'
    }
  end

  if tonumber(actor) == 0 then
    return {
      type = 'console',
      id = 'console'
    }
  end

  if type(actor) == 'number' then
    local player = MZPlayerService.getPlayer(actor)
    if player and player.citizenid then
      return {
        type = 'player',
        id = tostring(player.citizenid),
        source = actor
      }
    end

    return {
      type = 'source',
      id = tostring(actor)
    }
  end

  return {
    type = 'system',
    id = tostring(actor)
  }
end

local function buildMembershipSnapshot(citizenid, org, membership, grade, overrides)
  local snapshot = {
    citizenid = citizenid and tostring(citizenid) or nil,
    org_id = org and (tonumber(org.id) or org.id) or (membership and (tonumber(membership.org_id) or membership.org_id) or nil),
    org_code = org and tostring(org.code) or (membership and membership.org_code and tostring(membership.org_code) or nil),
    org_type = org and org.type_code and tostring(org.type_code) or (membership and membership.type_code and tostring(membership.type_code) or nil),
    grade_id = grade and (tonumber(grade.id) or grade.id) or (membership and (tonumber(membership.grade_id) or membership.grade_id) or nil),
    grade_level = grade and tonumber(grade.level) or (membership and tonumber(membership.grade_level) or nil),
    grade_code = grade and grade.code and tostring(grade.code) or (membership and membership.grade_code and tostring(membership.grade_code) or nil),
    grade_name = grade and grade.name and tostring(grade.name) or (membership and membership.grade_name and tostring(membership.grade_name) or nil),
    is_primary = membership ~= nil and asBool(membership.is_primary) or nil,
    duty = membership ~= nil and asBool(membership.duty) or nil,
    active = membership ~= nil and asBool(membership.active) or nil,
    expires_at = membership and membership.expires_at or nil
  }

  for key, value in pairs(overrides or {}) do
    snapshot[key] = value
  end

  return snapshot
end

local function logOrgActionDetailed(action, actor, citizenid, org, beforeState, afterState, meta)
  if not MZLogService or not org then return end

  MZLogService.createDetailed('orgs', action, {
    actor = buildOrgDetailedActor(actor),
    target = {
      type = 'player_org',
      id = ('%s:%s'):format(tostring(citizenid or 'unknown'), tostring(org.code or 'unknown')),
      citizenid = citizenid and tostring(citizenid) or nil,
      org_code = org.code and tostring(org.code) or nil
    },
    context = {
      org_id = tonumber(org.id) or org.id,
      org_code = tostring(org.code or ''),
      org_type = tostring(org.type_code or '')
    },
    before = beforeState or {},
    after = afterState or {},
    meta = meta or {}
  })
end

local function buildGradeMap(grades)
  local map = {}
  for _, grade in ipairs(grades) do
    map[grade.id] = grade
  end
  return map
end

local function collectInheritedPermissions(gradeId, gradeMap, permissions, out, visited)
  if not gradeId then return end
  visited = visited or {}
  if visited[gradeId] then return end
  visited[gradeId] = true

  local grade = gradeMap[gradeId]
  if not grade then return end

  if grade.inherits_grade_id then
    collectInheritedPermissions(grade.inherits_grade_id, gradeMap, permissions, out, visited)
  end

  for _, perm in ipairs(permissions) do
    if perm.grade_id == grade.id then
      out[perm.permission] = asBool(perm.allow)
    end
  end
end


local function getMembershipSafe(citizenid, org)
  if not org or not org.id then
    return nil
  end

  local membership = MZOrgRepository.getPlayerMembership(citizenid, org.id)
  if membership then
    return membership
  end

  local memberships = MZOrgRepository.getPlayerMemberships(citizenid)
  for _, row in ipairs(memberships or {}) do
    if tonumber(row.org_id) == tonumber(org.id) then
      return row
    end

    if row.org_code and org.code and row.org_code == org.code then
      return row
    end
  end

  return nil
end


local function refreshPlayerByCitizenId(citizenid)
  local src = MZPlayerService.getSourceByCitizenId(citizenid)
  if not src then return end
  MZOrgService.loadPlayerOrgs(src)
  local player = MZPlayerService.getPlayer(src)
  TriggerClientEvent('mz_core:client:playerLoaded', src, player)
end

function MZOrgService.loadPlayerOrgs(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then return {} end

  local memberships = MZOrgRepository.getPlayerMemberships(player.citizenid)
  local overrides = MZOrgRepository.getPlayerOverrides(player.citizenid)
  local result = {}
  player.job = nil
  player.gang = nil

  for _, membership in ipairs(memberships) do
    local grades = MZOrgRepository.getGradesForOrg(membership.org_id)
    local permissions = MZOrgRepository.getPermissionsForOrg(membership.org_id)
    local gradeMap = buildGradeMap(grades)
    local resolvedPermissions = {}

    for _, perm in ipairs(permissions) do
      if perm.grade_id == nil then
        resolvedPermissions[perm.permission] = asBool(perm.allow)
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
      isPrimary = asBool(membership.is_primary),
      duty = asBool(membership.duty),
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

  for _, override in ipairs(overrides) do
    for _, org in ipairs(result) do
      org.permissions[override.permission] = asBool(override.allow)
    end
  end

  player.orgs = result
  return result
end

function MZOrgService.getPlayerOrgs(source)
  local player = MZPlayerService.getPlayer(source)
  return player and player.orgs or {}
end

function MZOrgService.getOrgByCode(code)
  return MZOrgRepository.getOrgByCode(code)
end

function MZOrgService.listOrgs(orgTypeCode)
  return MZOrgRepository.listOrgs(orgTypeCode)
end

function MZOrgService.createOrg(data, actor)
  if type(data) ~= 'table' then return false, 'invalid_data' end
  if not data.type then return false, 'missing_type' end
  if not data.code or not data.name then return false, 'missing_fields' end

  local orgType = MZOrgRepository.getOrgTypeByCode(data.type)
  if not orgType then return false, 'org_type_not_found' end
  if MZOrgRepository.getOrgByCode(data.code) then return false, 'org_code_exists' end

  local org = MZOrgRepository.createOrg({
    type_id = orgType.id,
    code = data.code,
    name = data.name,
    is_public = data.is_public,
    requires_whitelist = data.requires_whitelist,
    has_salary = data.has_salary,
    has_shared_account = data.has_shared_account,
    has_storage = data.has_storage,
    active = data.active,
    config = data.config
  })

  if org and asBool(org.has_shared_account) then
    MySQL.insert.await([[
      INSERT INTO mz_org_accounts (org_id, balance)
      VALUES (?, 0)
      ON DUPLICATE KEY UPDATE org_id = org_id
    ]], { org.id })
  end

  logOrgAction('create_org', normalizeActor(actor), org and org.code or nil, {
    type = data.type,
    code = data.code,
    name = data.name
  })

  return true, org
end

function MZOrgService.createGrade(orgCode, data, actor)
  if type(data) ~= 'table' then return false, 'invalid_data' end
  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'org_not_found' end
  if type(data.level) ~= 'number' then return false, 'invalid_level' end
  if not data.code or not data.name then return false, 'missing_fields' end
  if MZOrgRepository.getGradeByLevel(org.id, data.level) then return false, 'grade_level_exists' end
  if MZOrgRepository.getGradeByCode(org.id, data.code) then return false, 'grade_code_exists' end

  local inheritsGradeId = nil
  if data.inherits_level ~= nil then
    local inheritsGrade = MZOrgRepository.getGradeByLevel(org.id, data.inherits_level)
    if not inheritsGrade then return false, 'inherits_grade_not_found' end
    inheritsGradeId = inheritsGrade.id
  elseif data.inherits_grade_id ~= nil then
    inheritsGradeId = data.inherits_grade_id
  end

  local grade = MZOrgRepository.createGrade(org.id, {
    level = data.level,
    code = data.code,
    name = data.name,
    salary = data.salary,
    inherits_grade_id = inheritsGradeId,
    priority = data.priority,
    config = data.config
  })

  logOrgAction('create_grade', normalizeActor(actor), org.code, {
    org = org.code,
    level = data.level,
    code = data.code,
    name = data.name,
    salary = data.salary or 0,
    inherits_level = data.inherits_level
  })

  return true, grade
end

function MZOrgService.setOrgPermission(orgCode, permission, allow, actor)
  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'org_not_found' end
  if not permission or permission == '' then return false, 'invalid_permission' end
  MZOrgRepository.setPermission(org.id, nil, permission, allow ~= false)

  logOrgAction('set_org_permission', normalizeActor(actor), org.code, {
    org = org.code,
    permission = permission,
    allow = allow ~= false
  })

  return true
end

function MZOrgService.setGradePermission(orgCode, gradeLevel, permission, allow, actor)
  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'org_not_found' end
  local grade = MZOrgRepository.getGradeByLevel(org.id, gradeLevel)
  if not grade then return false, 'grade_not_found' end
  if not permission or permission == '' then return false, 'invalid_permission' end
  MZOrgRepository.setPermission(org.id, grade.id, permission, allow ~= false)

  logOrgAction('set_grade_permission', normalizeActor(actor), org.code, {
    org = org.code,
    grade_level = gradeLevel,
    permission = permission,
    allow = allow ~= false
  })

  return true
end

function MZOrgService.addMember(citizenid, orgCode, gradeLevel, options, actor)
  options = options or {}
  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'org_not_found' end
  local target = MZPlayerRepository.getByCitizenId(citizenid)
  if not target then return false, 'player_not_found' end
  local grade = MZOrgRepository.getGradeByLevel(org.id, gradeLevel)
  if not grade then return false, 'grade_not_found' end
  local beforeMembership = getMembershipSafe(citizenid, org)
  local beforeGrade = beforeMembership and MZOrgRepository.getGradeById(beforeMembership.grade_id) or nil

  MZOrgRepository.setMembership(citizenid, org.id, grade.id, options.is_primary == true, options.duty == true, options.expires_at)

  if options.is_primary == true then
    MZOrgRepository.setPrimaryMembership(citizenid, org.type_code, org.id)
  end

  refreshPlayerByCitizenId(citizenid)

  logOrgActionDetailed(
    'add_member',
    actor,
    citizenid,
    org,
    buildMembershipSnapshot(citizenid, org, beforeMembership, beforeGrade),
    buildMembershipSnapshot(citizenid, org, beforeMembership, grade, {
      is_primary = options.is_primary == true,
      duty = options.duty == true,
      active = true,
      expires_at = options.expires_at
    }),
    {
      requested_grade_level = tonumber(gradeLevel) or gradeLevel
    }
  )

  return true
end

function MZOrgService.removeMember(citizenid, orgCode, actor)
  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'org_not_found' end

  local membership = getMembershipSafe(citizenid, org)
  if not membership or not asBool(membership.active) then
    return false, 'membership_not_found'
  end
  local currentGrade = MZOrgRepository.getGradeById(membership.grade_id)

  MZOrgRepository.removeMembership(citizenid, org.id)
  refreshPlayerByCitizenId(citizenid)

  logOrgActionDetailed(
    'remove_member',
    actor,
    citizenid,
    org,
    buildMembershipSnapshot(citizenid, org, membership, currentGrade),
    buildMembershipSnapshot(citizenid, org, membership, currentGrade, {
      active = false,
      removed = true
    }),
    {
      removed = true
    }
  )

  return true
end

function MZOrgService.setPrimary(citizenid, orgCode, actor)
  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'org_not_found' end

  local membership = getMembershipSafe(citizenid, org)
  if not membership or not asBool(membership.active) then
    return false, 'membership_not_found'
  end
  local currentGrade = MZOrgRepository.getGradeById(membership.grade_id)

  MZOrgRepository.setPrimaryMembership(citizenid, org.type_code, org.id)

  refreshPlayerByCitizenId(citizenid)

  logOrgActionDetailed(
    'set_primary',
    actor,
    citizenid,
    org,
    buildMembershipSnapshot(citizenid, org, membership, currentGrade),
    buildMembershipSnapshot(citizenid, org, membership, currentGrade, {
      is_primary = true
    })
  )

  return true
end

function MZOrgService.setDuty(citizenid, orgCode, duty, actor)
  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'org_not_found' end

  local membership = getMembershipSafe(citizenid, org)
  if not membership or not asBool(membership.active) then
    return false, 'membership_not_found'
  end
  local currentGrade = MZOrgRepository.getGradeById(membership.grade_id)

  MZOrgRepository.setMembershipDuty(citizenid, org.id, duty == true)

  refreshPlayerByCitizenId(citizenid)

  logOrgActionDetailed(
    'set_duty',
    actor,
    citizenid,
    org,
    buildMembershipSnapshot(citizenid, org, membership, currentGrade),
    buildMembershipSnapshot(citizenid, org, membership, currentGrade, {
      duty = duty == true
    }),
    {
      duty = duty == true
    }
  )

  return true
end

function MZOrgService.setGrade(citizenid, orgCode, gradeLevel, actor)
  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'org_not_found' end

  local membership = getMembershipSafe(citizenid, org)
  if not membership or not asBool(membership.active) then
    return false, 'membership_not_found'
  end

  local grade = MZOrgRepository.getGradeByLevel(org.id, gradeLevel)
  if not grade then return false, 'grade_not_found' end

  MZOrgRepository.updateMembershipGrade(citizenid, org.id, grade.id)
  refreshPlayerByCitizenId(citizenid)

  logOrgAction('set_grade', normalizeActor(actor), citizenid, {
    org = org.code,
    grade_level = gradeLevel,
    grade_code = grade.code
  })

  return true
end

function MZOrgService.promote(citizenid, orgCode, actor)
  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'org_not_found' end

  local membership = getMembershipSafe(citizenid, org)
  if not membership or not asBool(membership.active) then
    return false, 'membership_not_found'
  end

  local currentGrade = MZOrgRepository.getGradeById(membership.grade_id)
  if not currentGrade then return false, 'grade_not_found' end

  local nextGrade = MZOrgRepository.getGradeByLevel(org.id, tonumber(currentGrade.level) + 1)
  if not nextGrade then return false, 'max_grade_reached' end

  MZOrgRepository.updateMembershipGrade(citizenid, org.id, nextGrade.id)

  refreshPlayerByCitizenId(citizenid)

  logOrgActionDetailed(
    'promote_member',
    actor,
    citizenid,
    org,
    buildMembershipSnapshot(citizenid, org, membership, currentGrade),
    buildMembershipSnapshot(citizenid, org, membership, nextGrade),
    {
      from_level = tonumber(currentGrade.level) or currentGrade.level,
      from_code = currentGrade.code,
      to_level = tonumber(nextGrade.level) or nextGrade.level,
      to_code = nextGrade.code
    }
  )

  return true, nextGrade
end

function MZOrgService.demote(citizenid, orgCode, actor)
  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then return false, 'org_not_found' end

  local membership = getMembershipSafe(citizenid, org)
  if not membership or not asBool(membership.active) then
    return false, 'membership_not_found'
  end

  local currentGrade = MZOrgRepository.getGradeById(membership.grade_id)
  if not currentGrade then return false, 'grade_not_found' end

  local nextGrade = MZOrgRepository.getGradeByLevel(org.id, tonumber(currentGrade.level) - 1)
  if not nextGrade then return false, 'min_grade_reached' end

  MZOrgRepository.updateMembershipGrade(citizenid, org.id, nextGrade.id)

  refreshPlayerByCitizenId(citizenid)

  logOrgActionDetailed(
    'demote_member',
    actor,
    citizenid,
    org,
    buildMembershipSnapshot(citizenid, org, membership, currentGrade),
    buildMembershipSnapshot(citizenid, org, membership, nextGrade),
    {
      from_level = tonumber(currentGrade.level) or currentGrade.level,
      from_code = currentGrade.code,
      to_level = tonumber(nextGrade.level) or nextGrade.level,
      to_code = nextGrade.code
    }
  )

  return true, nextGrade
end

function MZOrgService.setPlayerPermission(citizenid, permission, allow, expiresAt, actor)
  if not MZPlayerRepository.getByCitizenId(citizenid) then return false, 'player_not_found' end
  if not permission or permission == '' then return false, 'invalid_permission' end

  MZOrgRepository.setPlayerOverride(citizenid, permission, allow ~= false, expiresAt)
  refreshPlayerByCitizenId(citizenid)

  logOrgAction('set_player_permission', normalizeActor(actor), citizenid, {
    permission = permission,
    allow = allow ~= false,
    expires_at = expiresAt
  })

  return true
end

function MZOrgService.removePlayerPermission(citizenid, permission, actor)
  MZOrgRepository.removePlayerOverride(citizenid, permission)
  refreshPlayerByCitizenId(citizenid)

  logOrgAction('remove_player_permission', normalizeActor(actor), citizenid, {
    permission = permission
  })

  return true
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
    if org.code == orgCode and org.grade and tonumber(org.grade.level or 0) >= tonumber(minLevel or 0) then
      return true
    end
  end

  return false
end
