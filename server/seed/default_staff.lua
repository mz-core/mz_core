MZStaffSeed = MZStaffSeed or {}

local function extend(base, additions)
  local result, seen = {}, {}
  for _, permission in ipairs(base or {}) do
    if not seen[permission] then
      seen[permission] = true
      result[#result + 1] = permission
    end
  end
  for _, permission in ipairs(additions or {}) do
    if not seen[permission] then
      seen[permission] = true
      result[#result + 1] = permission
    end
  end
  return result
end

local supportPermissions = {
  'staff.panel.open',
  'staff.coords.copy',
  'staff.players.list',
  'staff.players.goto',
  'staff.players.heal',
  'staff.players.revive'
}

local moderatorPermissions = extend(supportPermissions, {
  'staff.noclip',
  'staff.wall',
  'staff.teleport',
  'staff.players.bring',
  'staff.players.armor',
  'staff.vehicles.repair',
  'staff.warns.view',
  'staff.warns.issue'
})

local administratorPermissions = extend(moderatorPermissions, {
  'staff.spectate',
  'staff.players.kick',
  'staff.players.ban',
  'staff.bans.view',
  'staff.whitelist.view',
  'staff.whitelist.manage',
  'staff.warns.revoke',
  'staff.players.godmode',
  'staff.vehicles.spawn',
  'staff.vehicles.delete',
  'staff.garages.view',
  'staff.garages.create',
  'staff.garages.manage',
  'staff.orgs.view',
  'staff.orgs.set_leader',
  'staff.members.invite',
  'staff.members.remove',
  'staff.members.promote',
  'staff.members.demote',
  'staff.logs.view',
  'mz_banguard.alerts.view',
  'mz_banguard.alerts.details',
  'mz_banguard.alerts.acknowledge',
  'mz_banguard.alerts.note',
  'mz_banguard.actions.spectate',
  'mz_banguard.actions.goto'
})

local managerPermissions = extend(administratorPermissions, {
  'staff.roles.manage',
  'staff.bans.revoke',
  'staff.orgs.create',
  'staff.orgs.edit',
  'staff.orgs.manage',
  'staff.orgs.archive',
  'staff.orgs.restore',
  'staff.orgs.features',
  'staff.orgs.appearance',
  'staff.orgs.duty',
  'staff.world.view',
  'staff.world.doors.create',
  'staff.world.doors.manage',
  'staff.world.doors.archive',
  'staff.world.props.create',
  'staff.world.props.manage',
  'staff.world.props.archive',
  'staff.furniture.view',
  'staff.furniture.create',
  'staff.furniture.manage',
  'staff.furniture.archive',
  'staff.furniture.recovery',
  'mz_banguard.alerts.clear',
  'mz_banguard.alerts.identifiers'
})

local defaultRoles = {
  {
    code = 'suporte',
    name = 'Suporte',
    level = 100,
    permissions = supportPermissions
  },
  {
    code = 'moderador',
    name = 'Moderador',
    level = 300,
    permissions = moderatorPermissions
  },
  {
    code = 'administrador',
    name = 'Administrador',
    level = 700,
    permissions = administratorPermissions
  },
  {
    code = 'gerente_staff',
    name = 'Gerente Staff',
    level = 900,
    permissions = managerPermissions
  }
}

local function validateDefinition(definition)
  if type(definition) ~= 'table'
    or type(definition.code) ~= 'string'
    or not definition.code:match('^[a-z][a-z0-9_-]+$')
    or type(definition.name) ~= 'string'
    or #definition.name < 3
    or type(definition.level) ~= 'number'
    or definition.level < 1
    or definition.level > 9999 then
    return false, 'invalid_role_definition'
  end

  local seen = {}
  for _, permission in ipairs(definition.permissions or {}) do
    if not MZStaffPermissionSet or MZStaffPermissionSet[permission] ~= true then
      return false, ('unknown_permission:%s'):format(tostring(permission))
    end
    if seen[permission] then
      return false, ('duplicate_permission:%s'):format(permission)
    end
    seen[permission] = true
  end

  return true
end

function MZStaffSeed.GetDefaultRoles()
  return defaultRoles
end

function MZStaffSeed.ensureDefaultRoles()
  if MZCoreState then MZCoreState.seedStage = 'staff_roles:start' end
  print('[mz_core][staff-seed] default Staff role seed start')

  for _, definition in ipairs(defaultRoles) do
    if MZCoreState then MZCoreState.seedStage = 'staff_roles:' .. definition.code end
    local valid, validationError = validateDefinition(definition)
    if not valid then
      error(('[mz_core][staff-seed] role=%s error=%s'):format(
        tostring(definition and definition.code or 'unknown'),
        tostring(validationError)
      ), 0)
    end

    local existing = MZStaffRepository.getRoleByCode(definition.code)
    if existing then
      print(('[mz_core][staff-seed] preserved existing role code=%s level=%s'):format(
        definition.code,
        tostring(existing.level)
      ))
    else
      local blocker = MZStaffRepository.getRoleByLevel(definition.level)
      if blocker then
        print(('[mz_core][staff-seed] skipped role code=%s reason=level_conflict level=%s blocker=%s'):format(
          definition.code,
          tostring(definition.level),
          tostring(blocker.code or blocker.id)
        ))
      else
        local created = MZStaffRepository.createSeedRole(definition)
        if created ~= true then
          error(('[mz_core][staff-seed] failed role=%s'):format(definition.code), 0)
        end
        print(('[mz_core][staff-seed] created role code=%s level=%s permissions=%s'):format(
          definition.code,
          tostring(definition.level),
          tostring(#definition.permissions)
        ))
      end
    end
  end

  if MZCoreState then MZCoreState.seedStage = 'staff_roles:done' end
  print('[mz_core][staff-seed] default Staff role seed completed')
end
