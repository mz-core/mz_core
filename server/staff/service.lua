MZStaffService = MZStaffService or {}

local ContextCache = {}
local OWNER_LEVEL = 1000000

local function trim(value, maxLength)
  if type(value) ~= 'string' and type(value) ~= 'number' then return nil end
  value = tostring(value):gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' then return nil end
  if maxLength and #value > maxLength then return nil end
  return value
end

local function asBool(value)
  return value == true or value == 1 or tostring(value):lower() == 'true'
end

local function sourceId(value)
  value = tonumber(value)
  return value and value > 0 and math.floor(value) or nil
end

local function owner(source)
  source = sourceId(source)
  if not source then return false end
  local allowed = IsPlayerAceAllowed(source, (Config and Config.OwnerAce) or 'group.mz_owner')
  return allowed == true or allowed == 1 or tostring(allowed):lower() == 'true'
end

local function actorPlayer(source)
  source = sourceId(source)
  local player = source and MZPlayerService.getPlayer(source) or nil
  return player and player.citizenid and player or nil
end

local function permissionList(roleId)
  local list, set = {}, {}
  for _, row in ipairs(MZStaffRepository.getRolePermissions(roleId) or {}) do
    local permission = tostring(row.permission or '')
    if MZStaffPermissionSet[permission] and asBool(row.allow) then
      set[permission] = true
      list[#list + 1] = permission
    end
  end
  table.sort(list)
  return list, set
end

local function loadCitizenContext(citizenid)
  citizenid = trim(citizenid, 32)
  if not citizenid then return nil end
  if ContextCache[citizenid] ~= nil then return ContextCache[citizenid] or nil end

  local assignment = MZStaffRepository.getAssignment(citizenid)
  if not assignment or not asBool(assignment.active) or not asBool(assignment.role_active) then
    ContextCache[citizenid] = false
    return nil
  end

  local permissions, permissionSet = permissionList(assignment.role_id)
  local context = {
    citizenid = citizenid,
    assignmentId = tonumber(assignment.id),
    role = {
      id = tonumber(assignment.role_id),
      code = tostring(assignment.role_code or ''),
      name = tostring(assignment.role_name or ''),
      level = tonumber(assignment.role_level) or 0,
      revision = tonumber(assignment.role_revision) or 1
    },
    permissions = permissions,
    permissionSet = permissionSet
  }
  ContextCache[citizenid] = context
  return context
end

local function invalidate(citizenid)
  if citizenid then ContextCache[tostring(citizenid)] = nil else ContextCache = {} end
end

local function actorContext(source)
  local player = actorPlayer(source)
  if not player then return nil, 'player_not_loaded' end
  if owner(source) then
    local permissions = {}
    for _, definition in ipairs(MZStaffPermissionCatalog or {}) do
      permissions[#permissions + 1] = definition.code
    end
    return {
      owner = true,
      citizenid = tostring(player.citizenid),
      name = GetPlayerName(source),
      level = OWNER_LEVEL,
      role = { code = 'owner', name = 'Owner', level = OWNER_LEVEL },
      permissions = permissions
    }
  end

  local context = loadCitizenContext(player.citizenid)
  local allowed = MZOrgService
    and MZOrgService.hasGlobalPermission
    and MZOrgService.hasGlobalPermission(source, 'staff.roles.manage') == true
  if not allowed then return nil, 'permission_denied' end

  return {
    owner = false,
    citizenid = tostring(player.citizenid),
    name = GetPlayerName(source),
    level = context and tonumber(context.role.level) or 0,
    role = context and context.role or nil,
    permissions = context and context.permissions or {}
  }
end

local function audit(source, action, target, before, after, reason)
  if not MZLogService or type(MZLogService.createDetailed) ~= 'function' then return end
  local actor = actorPlayer(source)
  pcall(MZLogService.createDetailed, 'staff', action, {
    actor = {
      type = 'player', source = source,
      citizenid = actor and actor.citizenid,
      name = GetPlayerName(source)
    },
    target = target or {},
    before = before or {},
    after = after or {},
    meta = { reason = reason }
  })
end

local function roleDto(role)
  local permissions = permissionList(role.id)
  return {
    id = tonumber(role.id),
    code = tostring(role.code or ''),
    name = tostring(role.name or ''),
    level = tonumber(role.level) or 0,
    active = asBool(role.active),
    revision = tonumber(role.revision) or 1,
    permissions = permissions
  }
end

local function manageable(actor, role)
  return actor.owner == true or (tonumber(role.level) or 0) < (tonumber(actor.level) or 0)
end

local function playerTargetDto(source, player, context, isOwner)
  local role = context and context.role or nil
  return {
    source = sourceId(source),
    citizenid = tostring(player.citizenid),
    name = tostring(GetPlayerName(source) or player.citizenid),
    owner = isOwner == true,
    staff = isOwner == true or context ~= nil,
    level = isOwner == true and OWNER_LEVEL or (role and tonumber(role.level) or 0),
    role = isOwner == true
      and { code = 'owner', name = 'Owner', level = OWNER_LEVEL }
      or role
  }
end

function MZStaffService.HasPermission(source, permission)
  permission = trim(permission, 128)
  if not permission or not MZStaffPermissionSet[permission] then return false end
  local player = actorPlayer(source)
  if not player then return false end
  local context = loadCitizenContext(player.citizenid)
  return context ~= nil and context.permissionSet[permission] == true
end

function MZStaffService.CanActOnPlayer(actorSource, targetSource)
  actorSource = sourceId(actorSource)
  targetSource = sourceId(targetSource)
  if not actorSource or not targetSource then return false, 'invalid_source' end

  local actor = actorPlayer(actorSource)
  if not actor then return false, 'actor_not_loaded' end
  local target = actorPlayer(targetSource)
  if not target then return false, 'target_not_loaded' end

  local actorOwner = owner(actorSource)
  local targetOwner = owner(targetSource)
  local actorContextValue = loadCitizenContext(actor.citizenid)
  local targetContextValue = loadCitizenContext(target.citizenid)
  local context = {
    actor = playerTargetDto(actorSource, actor, actorContextValue, actorOwner),
    target = playerTargetDto(targetSource, target, targetContextValue, targetOwner)
  }

  if actorSource == targetSource then
    context.relationship = 'self'
    return true, 'self', context
  end

  if actorOwner then
    context.relationship = 'owner_override'
    return true, 'owner_override', context
  end

  if targetOwner then
    context.relationship = 'target_owner'
    return false, 'target_owner', context
  end

  if not targetContextValue then
    context.relationship = 'target_not_staff'
    return true, 'target_not_staff', context
  end

  if not actorContextValue then
    context.relationship = 'actor_without_staff_level'
    return false, 'actor_without_staff_level', context
  end

  if (tonumber(actorContextValue.role.level) or 0) <= (tonumber(targetContextValue.role.level) or 0) then
    context.relationship = 'target_higher_or_equal'
    return false, 'target_higher_or_equal', context
  end

  context.relationship = 'target_lower_staff'
  return true, 'target_lower_staff', context
end

function MZStaffService.GetContext(source)
  local player = actorPlayer(source)
  if not player then return nil end
  if owner(source) then
    return { owner = true, citizenid = player.citizenid, role = { code = 'owner', name = 'Owner', level = OWNER_LEVEL } }
  end
  local context = loadCitizenContext(player.citizenid)
  if not context then return nil end
  return {
    owner = false,
    citizenid = context.citizenid,
    role = context.role,
    permissions = context.permissions
  }
end

function MZStaffService.ListManagement(source)
  local actor, err = actorContext(source)
  if not actor then return false, err end
  local roles = {}
  for _, row in ipairs(MZStaffRepository.listRoles()) do
    if manageable(actor, row) then roles[#roles + 1] = roleDto(row) end
  end
  local assignments = {}
  for _, row in ipairs(MZStaffRepository.listAssignments()) do
    if manageable(actor, { level = row.role_level }) then
      local fullName = (tostring(row.firstname or '') .. ' ' .. tostring(row.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
      assignments[#assignments + 1] = {
        citizenid = tostring(row.citizenid),
        name = fullName ~= '' and fullName or tostring(row.citizenid),
        active = asBool(row.active),
        roleCode = tostring(row.role_code),
        roleName = tostring(row.role_name),
        roleLevel = tonumber(row.role_level) or 0,
        assignedAt = row.assigned_at,
        revokedAt = row.revoked_at
      }
    end
  end
  return true, {
    actor = { owner = actor.owner, level = actor.level, role = actor.role },
    roles = roles,
    assignments = assignments,
    catalog = MZStaffPermissionCatalog
  }
end

function MZStaffService.CreateRole(source, payload)
  local actor, err = actorContext(source)
  if not actor then return false, err end
  payload = type(payload) == 'table' and payload or {}
  local code = trim(payload.code, 48)
  code = code and code:lower() or nil
  local name = trim(payload.name, 80)
  local reason = trim(payload.reason, 255)
  local level = math.floor(tonumber(payload.level) or 0)
  if not code or #code < 3 or not code:match('^[a-z][a-z0-9_-]*$') then return false, 'invalid_code' end
  if not name or #name < 3 then return false, 'invalid_name' end
  if not reason or #reason < 3 then return false, 'invalid_reason' end
  if level < 1 or level > 9999 or level >= actor.level then return false, 'invalid_level' end
  local ok, id = pcall(MZStaffRepository.createRole, {
    code = code, name = name, level = level, actor_citizenid = actor.citizenid
  })
  if not ok or not id then return false, 'role_conflict' end
  local role = MZStaffRepository.getRoleById(id)
  audit(source, 'staff.role.created', { type = 'staff_role', id = code }, {}, roleDto(role), reason)
  return true, roleDto(role)
end

function MZStaffService.UpdateRole(source, code, payload)
  local actor, err = actorContext(source)
  if not actor then return false, err end
  local role = MZStaffRepository.getRoleByCode(trim(code, 48))
  if not role then return false, 'role_not_found' end
  if not manageable(actor, role) then return false, 'target_higher_or_equal' end
  payload = type(payload) == 'table' and payload or {}
  local name = trim(payload.name, 80)
  local reason = trim(payload.reason, 255)
  local level = math.floor(tonumber(payload.level) or 0)
  if type(payload.active) ~= 'boolean' then return false, 'invalid_state' end
  local active = payload.active == true
  if not name or #name < 3 then return false, 'invalid_name' end
  if not reason or #reason < 3 then return false, 'invalid_reason' end
  if level < 1 or level > 9999 or level >= actor.level then return false, 'invalid_level' end
  if not active and MZStaffRepository.countActiveAssignments(role.id) > 0 then return false, 'role_has_assignments' end
  local before = roleDto(role)
  local ok = pcall(MZStaffRepository.updateRole, role.id, { name = name, level = level, active = active })
  if not ok then return false, 'role_conflict' end
  invalidate()
  local after = roleDto(MZStaffRepository.getRoleById(role.id))
  audit(source, 'staff.role.updated', { type = 'staff_role', id = role.code }, before, after, reason)
  return true, after
end

function MZStaffService.SetRolePermissions(source, code, permissions, reason)
  local actor, err = actorContext(source)
  if not actor then return false, err end
  local role = MZStaffRepository.getRoleByCode(trim(code, 48))
  if not role then return false, 'role_not_found' end
  if not manageable(actor, role) then return false, 'target_higher_or_equal' end
  reason = trim(reason, 255)
  if not reason or #reason < 3 then return false, 'invalid_reason' end
  local selected = {}
  for _, permission in ipairs(type(permissions) == 'table' and permissions or {}) do
    permission = tostring(permission or '')
    if not MZStaffPermissionSet[permission] then return false, 'invalid_permission' end
    if not actor.owner and not MZOrgService.hasGlobalPermission(source, permission) then
      return false, 'permission_above_actor'
    end
    selected[permission] = true
  end
  local before = roleDto(role)
  local ok = pcall(MZStaffRepository.setRolePermissions, role.id, selected)
  if not ok then return false, 'database_error' end
  invalidate()
  local after = roleDto(MZStaffRepository.getRoleById(role.id))
  audit(source, 'staff.role.permissions_updated', { type = 'staff_role', id = role.code }, before, after, reason)
  return true, after
end

function MZStaffService.Assign(source, targetCitizenId, roleCode, reason)
  local actor, err = actorContext(source)
  if not actor then return false, err end
  local target = trim(targetCitizenId, 32)
  reason = trim(reason, 255)
  if not target or not reason or #reason < 3 then return false, 'invalid_request' end
  if target == actor.citizenid then return false, 'cannot_manage_self' end
  if not MZPlayerRepository.getByCitizenId(target) then return false, 'player_not_found' end
  local role = MZStaffRepository.getRoleByCode(trim(roleCode, 48))
  if not role or not asBool(role.active) then return false, 'role_not_found' end
  if not manageable(actor, role) then return false, 'target_higher_or_equal' end
  local current = MZStaffRepository.getAssignment(target)
  if current and asBool(current.active) and not manageable(actor, { level = current.role_level }) then
    return false, 'target_higher_or_equal'
  end
  MZStaffRepository.assign({
    citizenid = target, role_id = role.id,
    actor_citizenid = actor.citizenid, reason = reason
  })
  invalidate(target)
  audit(source, 'staff.assignment.set', { type = 'player', id = target, citizenid = target }, current or {}, {
    citizenid = target, roleCode = role.code, roleName = role.name, roleLevel = role.level
  }, reason)
  return true, { citizenid = target, role = roleDto(role), active = true }
end

function MZStaffService.Revoke(source, targetCitizenId, reason)
  local actor, err = actorContext(source)
  if not actor then return false, err end
  local target = trim(targetCitizenId, 32)
  reason = trim(reason, 255)
  if not target or not reason or #reason < 3 then return false, 'invalid_request' end
  if target == actor.citizenid then return false, 'cannot_manage_self' end
  local current = MZStaffRepository.getAssignment(target)
  if not current or not asBool(current.active) then return false, 'assignment_not_found' end
  if not manageable(actor, { level = current.role_level }) then return false, 'target_higher_or_equal' end
  MZStaffRepository.revoke(target, actor.citizenid, reason)
  invalidate(target)
  audit(source, 'staff.assignment.revoked', { type = 'player', id = target, citizenid = target }, current, { active = false }, reason)
  return true, { citizenid = target, active = false }
end
