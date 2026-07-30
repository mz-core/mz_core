local roles, roleByCode, permissions, assignments = {}, {}, {}, {}
local nextRoleId = 0

local function expect(condition, message)
  if not condition then error(message, 2) end
end

Config = { OwnerAce = 'group.mz_owner' }

function IsPlayerAceAllowed(source, ace)
  return source == 1 and ace == 'group.mz_owner'
end

function GetPlayerName(source)
  return ({
    [1] = 'Owner',
    [2] = 'Admin',
    [3] = 'Player',
    [4] = 'Moderador',
    [5] = 'Admin Par',
    [6] = 'ACE sem cargo'
  })[source]
end

MZPlayerService = {
  getPlayer = function(source)
    local citizenid = ({
      [1] = 'OWNER001',
      [2] = 'ADMIN001',
      [3] = 'PLAYER001',
      [4] = 'MOD001',
      [5] = 'ADMIN002',
      [6] = 'ACE001'
    })[source]
    return citizenid and { citizenid = citizenid } or nil
  end
}

MZPlayerRepository = {
  getByCitizenId = function(citizenid)
    return citizenid and { citizenid = citizenid } or nil
  end
}

MZStaffRepository = {
  getRoleByCode = function(code) return roleByCode[code] end,
  getRoleById = function(id) return roles[id] end,
  listRoles = function()
    local out = {}
    for _, role in pairs(roles) do out[#out + 1] = role end
    return out
  end,
  getRolePermissions = function(roleId)
    local out = {}
    for permission, allow in pairs(permissions[roleId] or {}) do
      if allow then out[#out + 1] = { permission = permission, allow = 1 } end
    end
    return out
  end,
  getAssignment = function(citizenid)
    local assignment = assignments[citizenid]
    if not assignment then return nil end
    local role = roles[assignment.role_id]
    local out = {}
    for key, value in pairs(assignment) do out[key] = value end
    out.role_code, out.role_name, out.role_level = role.code, role.name, role.level
    out.role_active, out.role_revision = role.active, role.revision
    return out
  end,
  listAssignments = function() return {} end,
  countActiveAssignments = function(roleId)
    local total = 0
    for _, assignment in pairs(assignments) do
      if assignment.role_id == roleId and assignment.active == 1 then total = total + 1 end
    end
    return total
  end,
  createRole = function(data)
    if roleByCode[data.code] then error('duplicate') end
    nextRoleId = nextRoleId + 1
    local role = {
      id = nextRoleId, code = data.code, name = data.name, level = data.level,
      active = 1, revision = 1
    }
    roles[nextRoleId], roleByCode[data.code] = role, role
    return nextRoleId
  end,
  updateRole = function(roleId, data)
    local role = roles[roleId]
    role.name, role.level, role.active = data.name, data.level, data.active and 1 or 0
    role.revision = role.revision + 1
    return 1
  end,
  setRolePermissions = function(roleId, selected)
    permissions[roleId] = selected
    roles[roleId].revision = roles[roleId].revision + 1
  end,
  assign = function(data)
    assignments[data.citizenid] = {
      id = 1, citizenid = data.citizenid, role_id = data.role_id,
      active = 1, assigned_by_citizenid = data.actor_citizenid
    }
  end,
  revoke = function(citizenid)
    assignments[citizenid].active = 0
    return 1
  end
}

dofile('mz_core/shared/staff_permissions.lua')

MZOrgService = {
  hasGlobalPermission = function(source, permission)
    if IsPlayerAceAllowed(source, Config.OwnerAce) then return true end
    return MZStaffService and MZStaffService.HasPermission(source, permission) == true
  end
}

dofile('mz_core/server/staff/service.lua')

local ok, role = MZStaffService.CreateRole(1, {
  code = 'admin', name = 'Administrador', level = 900, reason = 'bootstrap de teste'
})
expect(ok == true and role.code == 'admin', 'owner nao criou cargo inferior')

ok, role = MZStaffService.SetRolePermissions(1, 'admin', {
  'staff.panel.open', 'staff.roles.manage', 'staff.players.heal'
}, 'permissoes iniciais')
expect(ok == true and #role.permissions == 3, 'permissoes oficiais nao foram aplicadas')

ok = MZStaffService.Assign(1, 'ADMIN001', 'admin', 'atribuicao inicial')
expect(ok == true, 'owner nao atribuiu cargo')
expect(MZStaffService.HasPermission(2, 'staff.roles.manage') == true, 'cargo nao resolveu permissao global')
expect(MZStaffService.HasPermission(2, 'staff.orgs.manage') == false, 'cargo ganhou permissao nao concedida')

local denied, reason = MZStaffService.CreateRole(2, {
  code = 'igual', name = 'Mesmo nivel', level = 900, reason = 'teste negativo'
})
expect(denied == false and reason == 'invalid_level', 'Staff criou cargo igual ao proprio nivel')

ok, role = MZStaffService.CreateRole(2, {
  code = 'mod', name = 'Moderador', level = 100, reason = 'cargo inferior'
})
expect(ok == true and role.level == 100, 'Staff gerente nao criou cargo inferior')

denied, reason = MZStaffService.SetRolePermissions(2, 'mod', {
  'staff.logs.view'
}, 'tentativa de escalada')
expect(denied == false and reason == 'permission_above_actor', 'Staff concedeu permissao que nao possui')

ok = MZStaffService.Assign(1, 'MOD001', 'mod', 'alvo Staff inferior')
expect(ok == true, 'owner nao atribuiu cargo inferior para teste')
ok = MZStaffService.Assign(1, 'ADMIN002', 'admin', 'alvo Staff de mesmo nivel')
expect(ok == true, 'owner nao atribuiu cargo par para teste')

local allowed, hierarchyReason, hierarchy = MZStaffService.CanActOnPlayer(2, 3)
expect(
  allowed == true and hierarchyReason == 'target_not_staff' and hierarchy.target.staff == false,
  'Staff nao atuou sobre player comum'
)

allowed, hierarchyReason, hierarchy = MZStaffService.CanActOnPlayer(2, 4)
expect(
  allowed == true and hierarchyReason == 'target_lower_staff'
    and hierarchy.actor.level == 900 and hierarchy.target.level == 100,
  'Staff superior nao atuou sobre Staff inferior'
)

allowed, hierarchyReason = MZStaffService.CanActOnPlayer(2, 5)
expect(allowed == false and hierarchyReason == 'target_higher_or_equal', 'Staff atuou sobre nivel igual')

allowed, hierarchyReason = MZStaffService.CanActOnPlayer(4, 2)
expect(allowed == false and hierarchyReason == 'target_higher_or_equal', 'Staff inferior atuou sobre superior')

allowed, hierarchyReason = MZStaffService.CanActOnPlayer(2, 1)
expect(allowed == false and hierarchyReason == 'target_owner', 'Staff atuou sobre Owner')

allowed, hierarchyReason = MZStaffService.CanActOnPlayer(1, 2)
expect(allowed == true and hierarchyReason == 'owner_override', 'Owner nao atuou sobre Staff')

allowed, hierarchyReason = MZStaffService.CanActOnPlayer(2, 2)
expect(allowed == true and hierarchyReason == 'self', 'autoacao Staff foi bloqueada')

allowed, hierarchyReason = MZStaffService.CanActOnPlayer(6, 4)
expect(
  allowed == false and hierarchyReason == 'actor_without_staff_level',
  'ator sem nivel Staff atuou sobre Staff persistente'
)

allowed, hierarchyReason = MZStaffService.CanActOnPlayer(2, 99)
expect(allowed == false and hierarchyReason == 'target_not_loaded', 'alvo sem contexto nao falhou fechado')

print('mz_core staff hierarchy contract harness: PASS')
