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

local function isAceAllowed(src, ace)
  local sourceId = tonumber(src)
  if not sourceId or sourceId <= 0 then
    return false, {
      reason = 'invalid_source',
      source = src,
      sourceType = type(src),
      ace = ace
    }
  end

  ace = tostring(ace or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if ace == '' then
    return false, {
      reason = 'invalid_ace',
      source = sourceId,
      ace = ace
    }
  end

  local raw = IsPlayerAceAllowed(sourceId, ace)
  local normalized = tostring(raw):lower()
  local allowed = raw == true or raw == 1 or normalized == '1' or normalized == 'true'

  return allowed, {
    source = sourceId,
    ace = ace,
    raw = raw,
    rawType = type(raw),
    normalized = normalized,
    allowed = allowed
  }
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

local function logInviteMemberAudit(action, actorSource, targetSource, targetPlayer, org, reason, extra)
  if not MZLogService then return end

  extra = type(extra) == 'table' and extra or {}

  MZLogService.createDetailed('orgs', action, {
    actor = buildOrgDetailedActor(actorSource),
    target = {
      type = 'player',
      id = targetPlayer and tostring(targetPlayer.citizenid or targetSource or 'unknown') or tostring(targetSource or 'unknown'),
      source = tonumber(targetSource),
      citizenid = targetPlayer and tostring(targetPlayer.citizenid or '') or nil,
      name = targetPlayer and targetPlayer.charinfo and (('%s %s'):format(tostring(targetPlayer.charinfo.firstname or ''), tostring(targetPlayer.charinfo.lastname or ''))):gsub('^%s+', ''):gsub('%s+$', '') or nil
    },
    context = {
      org_id = org and (tonumber(org.id) or org.id) or nil,
      org_code = org and tostring(org.code or '') or nil,
      org_type = org and tostring(org.type_code or '') or nil
    },
    meta = {
      reason = reason,
      result = extra.result,
      grade_level = extra.gradeLevel,
      grade_code = extra.gradeCode,
      grade_name = extra.gradeName
    }
  })
end

local function logRemoveMemberAudit(action, actorSource, targetCitizenid, targetPlayer, org, reason, extra)
  if not MZLogService then return end

  extra = type(extra) == 'table' and extra or {}

  MZLogService.createDetailed('orgs', action, {
    actor = buildOrgDetailedActor(actorSource),
    target = {
      type = 'player_org',
      id = ('%s:%s'):format(tostring(targetCitizenid or 'unknown'), tostring(org and org.code or 'unknown')),
      citizenid = targetCitizenid and tostring(targetCitizenid) or nil,
      name = targetPlayer and (('%s %s'):format(tostring(targetPlayer.firstname or ''), tostring(targetPlayer.lastname or ''))):gsub('^%s+', ''):gsub('%s+$', '') or nil
    },
    context = {
      org_id = org and (tonumber(org.id) or org.id) or nil,
      org_code = org and tostring(org.code or '') or nil,
      org_type = org and tostring(org.type_code or '') or nil
    },
    before = extra.before or {},
    after = extra.after or {},
    meta = {
      reason = reason,
      result = extra.result,
      actor_grade_level = extra.actorGradeLevel,
      target_grade_level = extra.targetGradeLevel
    }
  })
end

local function logGradeMemberAudit(action, actorSource, targetCitizenid, targetPlayer, org, reason, extra)
  if not MZLogService then return end

  extra = type(extra) == 'table' and extra or {}

  MZLogService.createDetailed('orgs', action, {
    actor = buildOrgDetailedActor(actorSource),
    target = {
      type = 'player_org',
      id = ('%s:%s'):format(tostring(targetCitizenid or 'unknown'), tostring(org and org.code or 'unknown')),
      citizenid = targetCitizenid and tostring(targetCitizenid) or nil,
      name = targetPlayer and (('%s %s'):format(tostring(targetPlayer.firstname or ''), tostring(targetPlayer.lastname or ''))):gsub('^%s+', ''):gsub('%s+$', '') or nil
    },
    context = {
      org_id = org and (tonumber(org.id) or org.id) or nil,
      org_code = org and tostring(org.code or '') or nil,
      org_type = org and tostring(org.type_code or '') or nil
    },
    before = extra.before or {},
    after = extra.after or {},
    meta = {
      reason = reason,
      result = extra.result,
      action = extra.action,
      actor_grade_level = extra.actorGradeLevel,
      target_grade_level = extra.targetGradeLevel,
      new_grade_level = extra.newGradeLevel
    }
  })
end

local function logGoalAudit(action, actorSource, org, reason, extra)
  if not MZLogService then return end

  extra = type(extra) == 'table' and extra or {}

  MZLogService.createDetailed('orgs', action, {
    actor = buildOrgDetailedActor(actorSource),
    target = {
      type = 'org_goal',
      id = extra.goalId and tostring(extra.goalId) or tostring(org and org.code or 'unknown')
    },
    context = {
      org_id = org and (tonumber(org.id) or org.id) or nil,
      org_code = org and tostring(org.code or '') or nil,
      org_type = org and tostring(org.type_code or '') or nil
    },
    before = extra.before or {},
    after = extra.after or {},
    meta = {
      reason = reason,
      result = extra.result,
      title = extra.title,
      type = extra.type,
      target = extra.target
    }
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

local function isOwner(source)
  local ownerAce = (Config and Config.OwnerAce) or 'group.mz_owner'
  local allowed = isAceAllowed(source, ownerAce)
  return allowed == true
end

local function normalizePermission(value)
  if type(value) ~= 'string' then return nil end
  value = value:gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' then return nil end
  return value
end

local function normalizeOrgCode(value)
  if type(value) ~= 'string' and type(value) ~= 'number' then return nil end
  value = tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' then return nil end
  return value
end

local function normalizeString(value, maxLength)
  if value == nil then return nil end
  if type(value) ~= 'string' and type(value) ~= 'number' then return false end

  value = tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' then return nil end

  maxLength = tonumber(maxLength) or 255
  if #value > maxLength then return false end

  return value
end

local function normalizeGoalType(value)
  value = normalizeString(value or 'manual', 32)
  if value == false then return false end
  value = tostring(value or 'manual'):lower()

  local allowed = {
    manual = true,
    weekly = true,
    monthly = true,
    collective = true,
    individual = true
  }

  return allowed[value] and value or false
end

local function normalizeGoalDate(value)
  if value == nil or value == '' then return nil end
  if type(value) ~= 'string' and type(value) ~= 'number' then return false end

  value = tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' then return nil end
  if #value > 32 then return false end
  if not value:match('^%d%d%d%d%-%d%d%-%d%d') then return false end
  local y, m, d = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)')
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if not y or not m or not d or m < 1 or m > 12 or d < 1 or d > 31 then return false end

  if #value == 10 then
    return value .. ' 00:00:00'
  end

  return value:gsub('T', ' '):gsub('Z$', '')
end

local function dateSortKey(value)
  if not value then return nil end
  local y, m, d = tostring(value):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)')
  if not y then return nil end
  return tonumber(y .. m .. d)
end

local function normalizePanelOrgType(orgType)
  orgType = tostring(orgType or '')

  if orgType == 'job' then return 'legal' end
  if orgType == 'gang' then return 'gang' end
  if orgType == 'staff' then return 'staff' end
  if orgType == 'business' then return 'business' end
  if orgType == 'government' then return 'government' end
  if orgType == 'vip' then return 'vip' end

  return 'legal'
end

local function collectOrgCapabilities(org)
  local capabilities = {}
  local seen = {}

  local function addCapability(capability)
    capability = normalizePermission(capability)
    if not capability or seen[capability] then return end
    seen[capability] = true
    capabilities[#capabilities + 1] = capability
  end

  addCapability('org.view')

  for permission, allowed in pairs((org and org.permissions) or {}) do
    if allowed == true then
      addCapability(permission)
    end
  end

  table.sort(capabilities)

  return capabilities
end

local function getPlayerOrgByCode(player, orgCode)
  if not player then return nil end

  for _, org in ipairs(player.orgs or {}) do
    if tostring(org.code or '') == orgCode then
      return org
    end
  end

  return nil
end

local function buildPanelOrgContext(org)
  if type(org) ~= 'table' then return nil end

  local grade = type(org.grade) == 'table' and org.grade or {}
  local code = normalizeOrgCode(org.code)
  if not code then return nil end

  return {
    code = code,
    name = tostring(org.name or code),
    type = normalizePanelOrgType(org.type),
    grade = tonumber(grade.level) or 0,
    gradeCode = tostring(grade.code or ''),
    gradeName = tostring(grade.name or ''),
    capabilities = collectOrgCapabilities(org)
  }
end

local function buildSafeMemberName(row)
  if type(row) ~= 'table' then return 'Membro' end

  local firstName = tostring(row.firstname or ''):gsub('^%s+', ''):gsub('%s+$', '')
  local lastName = tostring(row.lastname or ''):gsub('^%s+', ''):gsub('%s+$', '')
  local fullName = (('%s %s'):format(firstName, lastName)):gsub('^%s+', ''):gsub('%s+$', '')

  if fullName ~= '' then
    return fullName
  end

  return tostring(row.citizenid or 'Membro')
end

local function normalizeOrgMember(row)
  if type(row) ~= 'table' then return nil end
  if not row.citizenid then return nil end

  return {
    citizenid = tostring(row.citizenid),
    name = buildSafeMemberName(row),
    orgCode = tostring(row.org_code or ''),
    grade = tonumber(row.grade_level) or 0,
    gradeCode = tostring(row.grade_code or ''),
    gradeName = tostring(row.grade_name or ''),
    isLeader = asBool(row.is_leader),
    isDuty = asBool(row.duty),
    joinedAt = row.joined_at,
    lastSeen = row.last_seen_at,
    status = asBool(row.active) and 'active' or 'inactive'
  }
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

function MZOrgService.inviteOrgMember(source, orgCode, targetSource, options)
  local originalSource = source
  source = tonumber(source)
  targetSource = tonumber(targetSource)
  orgCode = normalizeOrgCode(orgCode)
  options = type(options) == 'table' and options or {}

  if not source or source <= 0 then
    return false, 'invalid_source'
  end

  if not targetSource or targetSource <= 0 then
    logInviteMemberAudit('org.member.invite.blocked', source, targetSource, nil, nil, 'invalid_target', { result = 'blocked' })
    return false, 'invalid_target'
  end

  if source == targetSource then
    logInviteMemberAudit('org.member.invite.blocked', source, targetSource, nil, nil, 'self_target', { result = 'blocked' })
    return false, 'self_target'
  end

  if not orgCode then
    logInviteMemberAudit('org.member.invite.blocked', source, targetSource, nil, nil, 'invalid_org', { result = 'blocked' })
    return false, 'invalid_org'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    logInviteMemberAudit('org.member.invite.blocked', source, targetSource, nil, nil, 'invalid_org', { result = 'blocked' })
    return false, 'invalid_org'
  end

  local targetPlayer = MZPlayerService.getPlayer(targetSource)
  if not targetPlayer or not targetPlayer.citizenid then
    logInviteMemberAudit('org.member.invite.blocked', source, targetSource, nil, org, 'invalid_target', { result = 'blocked' })
    return false, 'invalid_target'
  end

  local isOwnerActor = MZOrgService.hasGlobalPermission(source, (Config and Config.OwnerAce) or 'group.mz_owner') == true
  local isStaffActor = MZOrgService.hasGlobalPermission(source, 'staff.orgs.manage') == true
    or MZOrgService.hasGlobalPermission(source, 'staff.panel.open') == true
  local canInvite = isOwnerActor
    or isStaffActor
    or MZOrgService.canOrg(source, orgCode, 'members.invite') == true

  if not canInvite then
    logInviteMemberAudit('org.member.invite.blocked', source, targetSource, targetPlayer, org, 'forbidden', { result = 'blocked' })
    return false, 'forbidden'
  end

  local membership = getMembershipSafe(targetPlayer.citizenid, org)
  if membership and asBool(membership.active) then
    logInviteMemberAudit('org.member.invite.blocked', source, targetSource, targetPlayer, org, 'already_member', { result = 'blocked' })
    return false, 'already_member'
  end

  local grades = MZOrgRepository.getGradesForOrg(org.id)
  local requestedGradeLevel = options.gradeLevel ~= nil and tonumber(options.gradeLevel) or nil
  local requestedGradeCode = normalizePermission(options.gradeCode)
  local gradeRequested = requestedGradeLevel ~= nil or requestedGradeCode ~= nil
  local initialGrade = nil

  if requestedGradeLevel ~= nil and requestedGradeLevel <= 0 then
    logInviteMemberAudit('org.member.invite.blocked', source, targetSource, targetPlayer, org, 'invalid_grade', { result = 'blocked' })
    return false, 'invalid_grade'
  end

  if requestedGradeLevel ~= nil then
    initialGrade = MZOrgRepository.getGradeByLevel(org.id, requestedGradeLevel)
    if requestedGradeCode and initialGrade and tostring(initialGrade.code or '') ~= tostring(requestedGradeCode) then
      logInviteMemberAudit('org.member.invite.blocked', source, targetSource, targetPlayer, org, 'invalid_grade', {
        result = 'blocked',
        gradeLevel = requestedGradeLevel,
        gradeCode = requestedGradeCode
      })
      return false, 'invalid_grade'
    end
  elseif requestedGradeCode then
    initialGrade = MZOrgRepository.getGradeByCode(org.id, requestedGradeCode)
  else
    initialGrade = grades and grades[1] or nil
  end

  if not initialGrade then
    local reason = gradeRequested and 'invalid_grade' or 'grade_not_found'
    logInviteMemberAudit('org.member.invite.blocked', source, targetSource, targetPlayer, org, reason, {
      result = 'blocked',
      gradeLevel = requestedGradeLevel,
      gradeCode = requestedGradeCode
    })
    return false, reason
  end

  if gradeRequested and not isOwnerActor and not isStaffActor then
    local actorPlayer = MZPlayerService.getPlayer(source)
    if not actorPlayer or not actorPlayer.citizenid then
      logInviteMemberAudit('org.member.invite.blocked', source, targetSource, targetPlayer, org, 'grade_not_allowed', {
        result = 'blocked',
        gradeLevel = tonumber(initialGrade.level),
        gradeCode = initialGrade.code,
        gradeName = initialGrade.name
      })
      return false, 'grade_not_allowed'
    end

    local actorMembership = getMembershipSafe(actorPlayer.citizenid, org)
    if not actorMembership or not asBool(actorMembership.active) then
      logInviteMemberAudit('org.member.invite.blocked', source, targetSource, targetPlayer, org, 'grade_not_allowed', {
        result = 'blocked',
        gradeLevel = tonumber(initialGrade.level),
        gradeCode = initialGrade.code,
        gradeName = initialGrade.name
      })
      return false, 'grade_not_allowed'
    end

    local actorGrade = MZOrgRepository.getGradeById(actorMembership.grade_id)
    local actorLevel = actorGrade and tonumber(actorGrade.level) or 0
    local selectedLevel = tonumber(initialGrade.level) or 0
    if actorLevel <= selectedLevel then
      logInviteMemberAudit('org.member.invite.blocked', source, targetSource, targetPlayer, org, 'grade_not_allowed', {
        result = 'blocked',
        gradeLevel = selectedLevel,
        gradeCode = initialGrade.code,
        gradeName = initialGrade.name
      })
      return false, 'grade_not_allowed'
    end
  end

  local added, err = MZOrgService.addMember(targetPlayer.citizenid, orgCode, tonumber(initialGrade.level), {
    is_primary = false,
    duty = false
  }, source)

  if not added then
    logInviteMemberAudit('org.member.invite.blocked', source, targetSource, targetPlayer, org, err or 'add_failed', {
      result = 'blocked',
      gradeLevel = tonumber(initialGrade.level),
      gradeCode = initialGrade.code,
      gradeName = initialGrade.name
    })
    return false, err or 'add_failed'
  end

  logInviteMemberAudit('org.member.invite', source, targetSource, targetPlayer, org, 'success', {
    result = 'allowed',
    gradeLevel = tonumber(initialGrade.level),
    gradeCode = initialGrade.code,
    gradeName = initialGrade.name
  })

  return true, {
    orgCode = orgCode,
    targetSource = targetSource,
    targetCitizenId = tostring(targetPlayer.citizenid),
    grade = tonumber(initialGrade.level) or 0,
    gradeCode = tostring(initialGrade.code or ''),
    gradeName = tostring(initialGrade.name or '')
  }
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

function MZOrgService.removeOrgMemberSecure(source, orgCode, targetCitizenId)
  local originalSource = source
  source = tonumber(source)
  orgCode = normalizeOrgCode(orgCode)
  targetCitizenId = normalizePermission(targetCitizenId)

  if not source or source <= 0 then
    return false, 'invalid_source'
  end

  if not orgCode then
    logRemoveMemberAudit('org.member.remove.blocked', source, targetCitizenId, nil, nil, 'invalid_org', { result = 'blocked' })
    return false, 'invalid_org'
  end

  if not targetCitizenId then
    logRemoveMemberAudit('org.member.remove.blocked', source, targetCitizenId, nil, nil, 'invalid_target', { result = 'blocked' })
    return false, 'invalid_target'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    logRemoveMemberAudit('org.member.remove.blocked', source, targetCitizenId, nil, nil, 'invalid_org', { result = 'blocked' })
    return false, 'invalid_org'
  end

  local actorPlayer = MZPlayerService.getPlayer(source)
  if actorPlayer and actorPlayer.citizenid and tostring(actorPlayer.citizenid) == tostring(targetCitizenId) then
    logRemoveMemberAudit('org.member.remove.blocked', source, targetCitizenId, nil, org, 'self_remove', { result = 'blocked' })
    return false, 'self_remove'
  end

  local targetPlayer = MZPlayerRepository.getByCitizenId(targetCitizenId)
  if not targetPlayer then
    logRemoveMemberAudit('org.member.remove.blocked', source, targetCitizenId, nil, org, 'invalid_target', { result = 'blocked' })
    return false, 'invalid_target'
  end

  local targetMembership = getMembershipSafe(targetCitizenId, org)
  if not targetMembership or not asBool(targetMembership.active) then
    logRemoveMemberAudit('org.member.remove.blocked', source, targetCitizenId, targetPlayer, org, 'not_member', { result = 'blocked' })
    return false, 'not_member'
  end

  local targetGrade = MZOrgRepository.getGradeById(targetMembership.grade_id)
  if not targetGrade then
    logRemoveMemberAudit('org.member.remove.blocked', source, targetCitizenId, targetPlayer, org, 'not_member', { result = 'blocked' })
    return false, 'not_member'
  end

  local isOwnerActor = MZOrgService.hasGlobalPermission(source, (Config and Config.OwnerAce) or 'group.mz_owner') == true
  local isStaffActor = MZOrgService.hasGlobalPermission(source, 'staff.orgs.manage') == true
    or MZOrgService.hasGlobalPermission(source, 'staff.panel.open') == true

  local grades = MZOrgRepository.getGradesForOrg(org.id)
  local maxLevel = 0
  for _, grade in ipairs(grades or {}) do
    local level = tonumber(grade.level) or 0
    if level > maxLevel then maxLevel = level end
  end

  local targetLevel = tonumber(targetGrade.level) or 0
  local protectedTarget = maxLevel > 0 and targetLevel >= maxLevel
  if protectedTarget and not isOwnerActor then
    logRemoveMemberAudit('org.member.remove.blocked', source, targetCitizenId, targetPlayer, org, 'protected_target', {
      result = 'blocked',
      targetGradeLevel = targetLevel
    })
    return false, 'protected_target'
  end

  local canRemove = isOwnerActor or isStaffActor
    or MZOrgService.canOrg(source, orgCode, 'members.remove') == true
    or MZOrgService.canOrg(source, orgCode, 'members.kick') == true
    or MZOrgService.canOrg(source, orgCode, 'manage.members') == true

  if not canRemove then
    logRemoveMemberAudit('org.member.remove.blocked', source, targetCitizenId, targetPlayer, org, 'forbidden', { result = 'blocked' })
    return false, 'forbidden'
  end

  if not isOwnerActor and not isStaffActor then
    if not actorPlayer or not actorPlayer.citizenid then
      logRemoveMemberAudit('org.member.remove.blocked', source, targetCitizenId, targetPlayer, org, 'forbidden', { result = 'blocked' })
      return false, 'forbidden'
    end

    local actorMembership = getMembershipSafe(actorPlayer.citizenid, org)
    if not actorMembership or not asBool(actorMembership.active) then
      logRemoveMemberAudit('org.member.remove.blocked', source, targetCitizenId, targetPlayer, org, 'forbidden', { result = 'blocked' })
      return false, 'forbidden'
    end

    local actorGrade = MZOrgRepository.getGradeById(actorMembership.grade_id)
    local actorLevel = actorGrade and tonumber(actorGrade.level) or 0
    if actorLevel <= targetLevel then
      logRemoveMemberAudit('org.member.remove.blocked', source, targetCitizenId, targetPlayer, org, 'target_higher_or_equal', {
        result = 'blocked',
        actorGradeLevel = actorLevel,
        targetGradeLevel = targetLevel
      })
      return false, 'target_higher_or_equal'
    end
  end

  local beforeState = buildMembershipSnapshot(targetCitizenId, org, targetMembership, targetGrade)
  local removed, err = MZOrgService.removeMember(targetCitizenId, orgCode, source)
  if not removed then
    logRemoveMemberAudit('org.member.remove.blocked', source, targetCitizenId, targetPlayer, org, err or 'remove_failed', {
      result = 'blocked',
      before = beforeState,
      targetGradeLevel = targetLevel
    })
    return false, err or 'remove_failed'
  end

  logRemoveMemberAudit('org.member.remove', source, targetCitizenId, targetPlayer, org, 'success', {
    result = 'allowed',
    before = beforeState,
    after = buildMembershipSnapshot(targetCitizenId, org, targetMembership, targetGrade, {
      active = false,
      removed = true
    }),
    targetGradeLevel = targetLevel
  })

  return true, {
    orgCode = orgCode,
    targetCitizenId = tostring(targetCitizenId),
    removed = true
  }
end

local function adjacentGradeForAction(grades, currentLevel, action)
  currentLevel = tonumber(currentLevel) or 0
  local selected = nil

  for _, grade in ipairs(grades or {}) do
    local level = tonumber(grade.level) or 0
    if action == 'promote' then
      if level > currentLevel and (not selected or level < (tonumber(selected.level) or 0)) then
        selected = grade
      end
    elseif action == 'demote' then
      if level < currentLevel and (not selected or level > (tonumber(selected.level) or 0)) then
        selected = grade
      end
    end
  end

  return selected
end

function MZOrgService.changeOrgMemberGradeSecure(source, orgCode, targetCitizenId, action)
  source = tonumber(source)
  orgCode = normalizeOrgCode(orgCode)
  targetCitizenId = normalizePermission(targetCitizenId)
  action = action == 'demote' and 'demote' or 'promote'

  local logAction = action == 'promote' and 'org.member.promote' or 'org.member.demote'
  local blockedAction = logAction .. '.blocked'

  if not source or source <= 0 then
    return false, 'invalid_source'
  end

  if not orgCode then
    logGradeMemberAudit(blockedAction, source, targetCitizenId, nil, nil, 'invalid_org', { result = 'blocked', action = action })
    return false, 'invalid_org'
  end

  if not targetCitizenId then
    logGradeMemberAudit(blockedAction, source, targetCitizenId, nil, nil, 'invalid_target', { result = 'blocked', action = action })
    return false, 'invalid_target'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    logGradeMemberAudit(blockedAction, source, targetCitizenId, nil, nil, 'invalid_org', { result = 'blocked', action = action })
    return false, 'invalid_org'
  end

  local actorPlayer = MZPlayerService.getPlayer(source)
  if actorPlayer and actorPlayer.citizenid and tostring(actorPlayer.citizenid) == tostring(targetCitizenId) then
    logGradeMemberAudit(blockedAction, source, targetCitizenId, nil, org, 'self_action', { result = 'blocked', action = action })
    return false, 'self_action'
  end

  local targetPlayer = MZPlayerRepository.getByCitizenId(targetCitizenId)
  if not targetPlayer then
    logGradeMemberAudit(blockedAction, source, targetCitizenId, nil, org, 'invalid_target', { result = 'blocked', action = action })
    return false, 'invalid_target'
  end

  local targetMembership = getMembershipSafe(targetCitizenId, org)
  if not targetMembership or not asBool(targetMembership.active) then
    logGradeMemberAudit(blockedAction, source, targetCitizenId, targetPlayer, org, 'not_member', { result = 'blocked', action = action })
    return false, 'not_member'
  end

  local targetGrade = MZOrgRepository.getGradeById(targetMembership.grade_id)
  if not targetGrade then
    logGradeMemberAudit(blockedAction, source, targetCitizenId, targetPlayer, org, 'grade_not_found', { result = 'blocked', action = action })
    return false, 'grade_not_found'
  end

  local grades = MZOrgRepository.getGradesForOrg(org.id)
  local newGrade = adjacentGradeForAction(grades, targetGrade.level, action)
  if not newGrade then
    local limitReason = action == 'promote' and 'max_grade' or 'min_grade'
    logGradeMemberAudit(blockedAction, source, targetCitizenId, targetPlayer, org, limitReason, {
      result = 'blocked',
      action = action,
      targetGradeLevel = tonumber(targetGrade.level) or 0
    })
    return false, limitReason
  end

  local maxLevel = 0
  for _, grade in ipairs(grades or {}) do
    local level = tonumber(grade.level) or 0
    if level > maxLevel then maxLevel = level end
  end

  local isOwnerActor = MZOrgService.hasGlobalPermission(source, (Config and Config.OwnerAce) or 'group.mz_owner') == true
  local isStaffActor = MZOrgService.hasGlobalPermission(source, 'staff.orgs.manage') == true
    or MZOrgService.hasGlobalPermission(source, 'staff.panel.open') == true

  local targetLevel = tonumber(targetGrade.level) or 0
  if action == 'demote' and maxLevel > 0 and targetLevel >= maxLevel and not isOwnerActor and not isStaffActor then
    logGradeMemberAudit(blockedAction, source, targetCitizenId, targetPlayer, org, 'protected_target', {
      result = 'blocked',
      action = action,
      targetGradeLevel = targetLevel
    })
    return false, 'protected_target'
  end

  local permission = action == 'promote' and 'members.promote' or 'members.demote'
  local canChange = isOwnerActor or isStaffActor
    or MZOrgService.canOrg(source, orgCode, permission) == true
    or MZOrgService.canOrg(source, orgCode, 'manage.members') == true

  if not canChange then
    logGradeMemberAudit(blockedAction, source, targetCitizenId, targetPlayer, org, 'forbidden', { result = 'blocked', action = action })
    return false, 'forbidden'
  end

  local actorLevel = 0
  if not isOwnerActor and not isStaffActor then
    if not actorPlayer or not actorPlayer.citizenid then
      logGradeMemberAudit(blockedAction, source, targetCitizenId, targetPlayer, org, 'forbidden', { result = 'blocked', action = action })
      return false, 'forbidden'
    end

    local actorMembership = getMembershipSafe(actorPlayer.citizenid, org)
    if not actorMembership or not asBool(actorMembership.active) then
      logGradeMemberAudit(blockedAction, source, targetCitizenId, targetPlayer, org, 'forbidden', { result = 'blocked', action = action })
      return false, 'forbidden'
    end

    local actorGrade = MZOrgRepository.getGradeById(actorMembership.grade_id)
    actorLevel = actorGrade and tonumber(actorGrade.level) or 0

    if actorLevel <= targetLevel then
      logGradeMemberAudit(blockedAction, source, targetCitizenId, targetPlayer, org, 'target_higher_or_equal', {
        result = 'blocked',
        action = action,
        actorGradeLevel = actorLevel,
        targetGradeLevel = targetLevel
      })
      return false, 'target_higher_or_equal'
    end

    if action == 'promote' and actorLevel <= (tonumber(newGrade.level) or 0) then
      logGradeMemberAudit(blockedAction, source, targetCitizenId, targetPlayer, org, 'promotion_above_actor', {
        result = 'blocked',
        action = action,
        actorGradeLevel = actorLevel,
        targetGradeLevel = targetLevel,
        newGradeLevel = tonumber(newGrade.level) or 0
      })
      return false, 'promotion_above_actor'
    end
  end

  local beforeState = buildMembershipSnapshot(targetCitizenId, org, targetMembership, targetGrade)
  MZOrgRepository.updateMembershipGrade(targetCitizenId, org.id, newGrade.id)
  refreshPlayerByCitizenId(targetCitizenId)

  local afterState = buildMembershipSnapshot(targetCitizenId, org, targetMembership, newGrade)
  logGradeMemberAudit(logAction, source, targetCitizenId, targetPlayer, org, 'success', {
    result = 'allowed',
    action = action,
    before = beforeState,
    after = afterState,
    actorGradeLevel = actorLevel,
    targetGradeLevel = targetLevel,
    newGradeLevel = tonumber(newGrade.level) or 0
  })

  return true, {
    orgCode = orgCode,
    targetCitizenId = tostring(targetCitizenId),
    action = action,
    oldGrade = tonumber(targetGrade.level) or 0,
    newGrade = tonumber(newGrade.level) or 0,
    oldGradeCode = tostring(targetGrade.code or ''),
    newGradeCode = tostring(newGrade.code or ''),
    oldGradeName = tostring(targetGrade.name or ''),
    newGradeName = tostring(newGrade.name or '')
  }
end

function MZOrgService.promoteOrgMemberSecure(source, orgCode, targetCitizenId)
  return MZOrgService.changeOrgMemberGradeSecure(source, orgCode, targetCitizenId, 'promote')
end

function MZOrgService.demoteOrgMemberSecure(source, orgCode, targetCitizenId)
  return MZOrgService.changeOrgMemberGradeSecure(source, orgCode, targetCitizenId, 'demote')
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

function MZOrgService.hasGlobalPermission(source, permission)
  local originalSource = source
  source = tonumber(source)
  permission = normalizePermission(permission)

  if not source or source <= 0 or not permission then
    return false
  end

  local ownerAce = (Config and Config.OwnerAce) or 'group.mz_owner'
  local ownerAllowed, ownerDebug = isAceAllowed(source, ownerAce)

  if Config and Config.Debug == true and (permission == ownerAce or permission == 'group.mz_owner') then
    print(('[mz_core][HasGlobalPermission][debug] src=%s srcType=%s permission=%s ownerAce=%s raw=%s rawType=%s normalized=%s allowed=%s resource=%s'):format(
      tostring(source),
      type(originalSource),
      tostring(permission),
      tostring(ownerAce),
      tostring(ownerDebug and ownerDebug.raw),
      tostring(ownerDebug and ownerDebug.rawType),
      tostring(ownerDebug and ownerDebug.normalized),
      tostring(ownerDebug and ownerDebug.allowed),
      tostring(GetCurrentResourceName())
    ))
  end

  if permission == ownerAce or permission == 'group.mz_owner' then
    return ownerAllowed == true
  end

  if ownerAllowed == true then
    return true
  end

  local aceAllowed = isAceAllowed(source, permission)
  if aceAllowed == true then
    return true
  end

  return MZOrgService.hasPermission(source, permission)
end

function MZOrgService.canOrg(source, orgCode, capability)
  source = tonumber(source)
  orgCode = normalizeOrgCode(orgCode)
  capability = normalizePermission(capability)

  if not source or source <= 0 or not orgCode or not capability then
    return false
  end

  if MZOrgService.hasGlobalPermission(source, (Config and Config.OwnerAce) or 'group.mz_owner') == true then
    return true
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    return false
  end

  local player = MZPlayerService.getPlayer(source)
  if not player then
    return false
  end

  if type(player.orgs) ~= 'table' then
    MZOrgService.loadPlayerOrgs(source)
  end

  local playerOrg = getPlayerOrgByCode(player, orgCode)
  if not playerOrg then
    MZOrgService.loadPlayerOrgs(source)
    playerOrg = getPlayerOrgByCode(player, orgCode)
  end

  if not playerOrg then
    return false
  end

  if capability == 'org.view' then
    return true
  end

  return playerOrg.permissions and playerOrg.permissions[capability] == true
end

function MZOrgService.getPlayerOrgContext(source)
  source = tonumber(source)
  if not source or source <= 0 then
    return {}
  end

  local player = MZPlayerService.getPlayer(source)
  if not player then
    return {}
  end

  local orgs = MZOrgService.loadPlayerOrgs(source) or {}
  local result = {}

  for _, org in ipairs(orgs) do
    local context = buildPanelOrgContext(org)
    if context then
      result[#result + 1] = context
    end
  end

  return result
end

function MZOrgService.listOrgMembers(source, orgCode)
  local originalSource = source
  source = tonumber(source)
  orgCode = normalizeOrgCode(orgCode)

  if not source or source <= 0 then
    if Config and Config.Debug == true then
      print(('[mz_core][ListOrgMembers][debug] invalid_source source=%s sourceType=%s orgCode=%s resource=%s'):format(
        tostring(originalSource),
        type(originalSource),
        tostring(orgCode),
        tostring(GetCurrentResourceName())
      ))
    end

    return false, 'invalid_source'
  end

  if not orgCode then
    return false, 'invalid_org'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    return false, 'org_not_found'
  end

  local canView = MZOrgService.hasGlobalPermission(source, (Config and Config.OwnerAce) or 'group.mz_owner') == true
    or MZOrgService.hasGlobalPermission(source, 'staff.orgs.manage') == true
    or MZOrgService.hasGlobalPermission(source, 'staff.panel.open') == true
    or MZOrgService.canOrg(source, orgCode, 'org.view') == true

  if not canView then
    return false, 'forbidden'
  end

  local rows = MZOrgRepository.listMembersForOrg(org.id)
  local members = {}

  for _, row in ipairs(rows or {}) do
    local member = normalizeOrgMember(row)
    if member then
      members[#members + 1] = member
    end
  end

  return members
end

local function safeCapabilityList(values)
  local out = {}
  for permission, allowed in pairs(values or {}) do
    if allowed == true then
      out[#out + 1] = permission
    end
  end

  table.sort(out)
  return out
end

local function directPermissionsForGrade(gradeId, permissions)
  local out = {}
  for _, permission in ipairs(permissions or {}) do
    if permission.grade_id == gradeId and asBool(permission.allow) == true then
      out[#out + 1] = permission.permission
    end
  end

  table.sort(out)
  return out
end

function MZOrgService.getOrgAccessModel(source, orgCode)
  local originalSource = source
  source = tonumber(source)
  orgCode = normalizeOrgCode(orgCode)

  if not source or source <= 0 then
    if Config and Config.Debug == true then
      print(('[mz_core][GetOrgAccessModel][debug] invalid_source source=%s sourceType=%s orgCode=%s resource=%s'):format(
        tostring(originalSource),
        type(originalSource),
        tostring(orgCode),
        tostring(GetCurrentResourceName())
      ))
    end

    return false, 'invalid_source'
  end

  if not orgCode then
    return false, 'invalid_org'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    return false, 'org_not_found'
  end

  local canView = MZOrgService.hasGlobalPermission(source, (Config and Config.OwnerAce) or 'group.mz_owner') == true
    or MZOrgService.hasGlobalPermission(source, 'staff.orgs.manage') == true
    or MZOrgService.hasGlobalPermission(source, 'staff.panel.open') == true
    or MZOrgService.canOrg(source, orgCode, 'manage.permissions') == true
    or MZOrgService.canOrg(source, orgCode, 'manage.members') == true
    or MZOrgService.canOrg(source, orgCode, 'org.view') == true

  if not canView then
    return false, 'forbidden'
  end

  local grades = MZOrgRepository.getGradesForOrg(org.id)
  local permissions = MZOrgRepository.getPermissionsForOrg(org.id)
  local gradeMap = buildGradeMap(grades)
  local basePermissions = {}

  for _, permission in ipairs(permissions or {}) do
    if permission.grade_id == nil then
      basePermissions[permission.permission] = asBool(permission.allow)
    end
  end

  local outGrades = {}
  for _, grade in ipairs(grades or {}) do
    local resolved = {}
    collectInheritedPermissions(grade.id, gradeMap, permissions, resolved)

    local parent = grade.inherits_grade_id and gradeMap[grade.inherits_grade_id] or nil
    outGrades[#outGrades + 1] = {
      level = tonumber(grade.level) or 0,
      code = tostring(grade.code or ''),
      name = tostring(grade.name or ''),
      salary = tonumber(grade.salary) or 0,
      inheritsLevel = parent and tonumber(parent.level) or nil,
      inheritsCode = parent and tostring(parent.code or '') or nil,
      capabilities = safeCapabilityList(resolved),
      directCapabilities = directPermissionsForGrade(grade.id, permissions)
    }
  end

  local playerOverrides = {}
  local player = MZPlayerService.getPlayer(source)
  if player and player.citizenid then
    for _, override in ipairs(MZOrgRepository.getPlayerOverrides(player.citizenid) or {}) do
      playerOverrides[#playerOverrides + 1] = {
        permission = tostring(override.permission or ''),
        allow = asBool(override.allow),
        expiresAt = override.expires_at
      }
    end
  end

  return {
    orgCode = tostring(org.code or orgCode),
    orgName = tostring(org.name or orgCode),
    type = normalizePanelOrgType(org.type_code),
    baseCapabilities = safeCapabilityList(basePermissions),
    grades = outGrades,
    playerOverrides = playerOverrides
  }
end

local function normalizeGoalRow(row)
  if type(row) ~= 'table' then return nil end

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

local function canViewGoals(source, orgCode)
  if MZOrgService.hasGlobalPermission(source, (Config and Config.OwnerAce) or 'group.mz_owner') == true then return true end
  if MZOrgService.hasGlobalPermission(source, 'staff.orgs.manage') == true then return true end
  if MZOrgService.hasGlobalPermission(source, 'staff.panel.open') == true then return true end
  if not orgCode then return false end
  if MZOrgService.canOrg(source, orgCode, 'goals.view') == true then return true end
  if MZOrgService.canOrg(source, orgCode, 'goals.manage') == true then return true end
  return MZOrgService.canOrg(source, orgCode, 'org.view') == true
end

local function canManageGoals(source, orgCode)
  if MZOrgService.hasGlobalPermission(source, (Config and Config.OwnerAce) or 'group.mz_owner') == true then return true end
  if MZOrgService.hasGlobalPermission(source, 'staff.orgs.manage') == true then return true end
  if MZOrgService.hasGlobalPermission(source, 'staff.panel.open') == true then return true end
  if not orgCode then return false end
  if MZOrgService.canOrg(source, orgCode, 'goals.manage') == true then return true end
  return MZOrgService.canOrg(source, orgCode, 'manage.goals') == true
end

local function normalizeGoalFilters(filters)
  filters = type(filters) == 'table' and filters or {}

  return {
    orgCode = normalizeOrgCode(filters.orgCode),
    status = normalizeString(filters.status, 32),
    type = filters.type ~= nil and filters.type ~= '' and normalizeGoalType(filters.type) or nil,
    search = normalizeString(filters.search, 80),
    limit = math.min(math.max(math.floor(tonumber(filters.limit) or 50), 1), 100),
    offset = math.min(math.max(math.floor(tonumber(filters.offset) or 0), 0), 10000)
  }
end

function MZOrgService.listOrgGoals(source, filters)
  source = tonumber(source)
  if not source or source <= 0 then return false, 'invalid_source' end

  filters = normalizeGoalFilters(filters)
  if filters.type == false or filters.status == false or filters.search == false then
    return false, 'invalid_filters'
  end

  if filters.orgCode then
    local org = MZOrgRepository.getOrgByCode(filters.orgCode)
    if not org then return false, 'invalid_org' end
  end

  if not canViewGoals(source, filters.orgCode) then
    return false, 'forbidden'
  end

  local rows = MZOrgRepository.listGoals(filters)
  local out = {}
  for _, row in ipairs(rows or {}) do
    local item = normalizeGoalRow(row)
    if item then out[#out + 1] = item end
  end

  return out
end

function MZOrgService.getOrgGoal(source, goalId)
  source = tonumber(source)
  goalId = tonumber(goalId)
  if not source or source <= 0 then return false, 'invalid_source' end
  if not goalId or goalId <= 0 then return false, 'invalid_goal' end

  local row = MZOrgRepository.getGoalById(goalId)
  if not row then return false, 'goal_not_found' end
  if not canViewGoals(source, row.org_code) then return false, 'forbidden' end

  return normalizeGoalRow(row)
end

function MZOrgService.createOrgGoal(source, orgCode, payload)
  source = tonumber(source)
  orgCode = normalizeOrgCode(orgCode)
  payload = type(payload) == 'table' and payload or {}

  if not source or source <= 0 then return false, 'invalid_source' end
  if not orgCode then
    logGoalAudit('org.goal.create.blocked', source, nil, 'invalid_org', { result = 'blocked' })
    return false, 'invalid_org'
  end

  local org = MZOrgRepository.getOrgByCode(orgCode)
  if not org then
    logGoalAudit('org.goal.create.blocked', source, nil, 'invalid_org', { result = 'blocked' })
    return false, 'invalid_org'
  end

  if not canManageGoals(source, orgCode) then
    logGoalAudit('org.goal.create.blocked', source, org, 'forbidden', { result = 'blocked' })
    return false, 'forbidden'
  end

  local title = normalizeString(payload.title, 120)
  if not title or title == false then
    logGoalAudit('org.goal.create.blocked', source, org, 'invalid_title', { result = 'blocked' })
    return false, 'invalid_title'
  end

  local description = normalizeString(payload.description, 1000)
  if description == false then
    logGoalAudit('org.goal.create.blocked', source, org, 'invalid_description', { result = 'blocked', title = title })
    return false, 'invalid_description'
  end

  local goalType = normalizeGoalType(payload.type)
  if goalType == false then
    logGoalAudit('org.goal.create.blocked', source, org, 'invalid_type', { result = 'blocked', title = title })
    return false, 'invalid_type'
  end

  local target = tonumber(payload.target)
  if not target then target = 1 end
  target = math.floor(target)
  if target < 1 or target > 100000 then
    logGoalAudit('org.goal.create.blocked', source, org, 'invalid_target', { result = 'blocked', title = title, target = target })
    return false, 'invalid_target'
  end

  local startsAt = normalizeGoalDate(payload.startsAt or payload.starts_at)
  local endsAt = normalizeGoalDate(payload.endsAt or payload.ends_at)
  if startsAt == false or endsAt == false then
    logGoalAudit('org.goal.create.blocked', source, org, 'invalid_dates', { result = 'blocked', title = title })
    return false, 'invalid_dates'
  end

  local startKey = dateSortKey(startsAt)
  local endKey = dateSortKey(endsAt)
  if startKey and endKey and endKey < startKey then
    logGoalAudit('org.goal.create.blocked', source, org, 'invalid_dates', { result = 'blocked', title = title })
    return false, 'invalid_dates'
  end

  local player = MZPlayerService.getPlayer(source)
  local citizenid = player and player.citizenid and tostring(player.citizenid) or nil
  local charinfo = player and type(player.charinfo) == 'table' and player.charinfo or {}
  local createdByName = (('%s %s'):format(tostring(charinfo.firstname or ''), tostring(charinfo.lastname or ''))):gsub('^%s+', ''):gsub('%s+$', '')
  if createdByName == '' then createdByName = GetPlayerName(source) or citizenid or 'unknown' end

  local row = MZOrgRepository.createGoal(org, {
    title = title,
    description = description,
    type = goalType or 'manual',
    status = 'active',
    target = target,
    progress = 0,
    starts_at = startsAt,
    ends_at = endsAt,
    created_by_citizenid = citizenid,
    created_by_name = createdByName
  })

  if not row then
    logGoalAudit('org.goal.create.blocked', source, org, 'create_failed', {
      result = 'blocked',
      title = title,
      type = goalType,
      target = target
    })
    return false, 'create_failed'
  end

  local item = normalizeGoalRow(row)
  logGoalAudit('org.goal.create', source, org, 'success', {
    result = 'allowed',
    goalId = item and item.id or row.id,
    after = item or {},
    title = title,
    type = goalType,
    target = target
  })

  return true, item
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
