local rolesByCode, rolesByLevel, permissionsByCode = {}, {}, {}
local createCalls = 0

local function expect(condition, message)
  if not condition then error(message, 2) end
end

dofile('mz_core/shared/staff_permissions.lua')

local catalogSeen = {}
for _, definition in ipairs(MZStaffPermissionCatalog or {}) do
  expect(not catalogSeen[definition.code], 'catalogo possui permissao duplicada: ' .. tostring(definition.code))
  catalogSeen[definition.code] = true
end

MZCoreState = {}
MZStaffRepository = {
  getRoleByCode = function(code)
    return rolesByCode[code]
  end,
  getRoleByLevel = function(level)
    return rolesByLevel[level]
  end,
  createSeedRole = function(definition)
    createCalls = createCalls + 1
    local role = {
      id = createCalls,
      code = definition.code,
      name = definition.name,
      level = definition.level,
      active = 1,
      created_by_citizenid = 'system:staff_seed'
    }
    rolesByCode[role.code] = role
    rolesByLevel[role.level] = role
    permissionsByCode[role.code] = {}
    for _, permission in ipairs(definition.permissions or {}) do
      permissionsByCode[role.code][permission] = true
    end
    return true
  end
}

dofile('mz_core/server/seed/default_staff.lua')

MZStaffSeed.ensureDefaultRoles()

expect(createCalls == 4, 'seed nao criou os quatro cargos padrao')
expect(rolesByCode.suporte and rolesByCode.suporte.level == 100, 'cargo suporte invalido')
expect(rolesByCode.moderador and rolesByCode.moderador.level == 300, 'cargo moderador invalido')
expect(rolesByCode.administrador and rolesByCode.administrador.level == 700, 'cargo administrador invalido')
expect(rolesByCode.gerente_staff and rolesByCode.gerente_staff.level == 900, 'cargo gerente Staff invalido')
expect(rolesByCode.owner == nil and rolesByCode.staff_supremo == nil, 'owner foi persistido como cargo comum')
expect(permissionsByCode.suporte['staff.players.heal'] == true, 'suporte sem permissao operacional esperada')
expect(permissionsByCode.suporte['staff.players.bring'] ~= true, 'suporte recebeu bring invasivo')
expect(permissionsByCode.moderador['staff.players.bring'] == true, 'moderador nao recebeu bring protegido')
expect(permissionsByCode.moderador['staff.wall'] == true, 'moderador nao recebeu wall administrativo')
expect(permissionsByCode.moderador['staff.spectate'] ~= true, 'moderador recebeu spectate invasivo')
expect(permissionsByCode.moderador['staff.players.kick'] ~= true, 'moderador recebeu kick disruptivo')
expect(permissionsByCode.moderador['staff.players.ban'] ~= true, 'moderador recebeu ban disruptivo')
expect(permissionsByCode.moderador['staff.warns.view'] == true, 'moderador sem consulta de advertencias')
expect(permissionsByCode.moderador['staff.warns.issue'] == true, 'moderador sem emissao de advertencias')
expect(permissionsByCode.moderador['staff.warns.revoke'] ~= true, 'moderador recebeu revogacao de advertencias')
expect(permissionsByCode.administrador['staff.spectate'] == true, 'administrador nao recebeu spectate')
expect(permissionsByCode.administrador['staff.players.kick'] == true, 'administrador nao recebeu kick')
expect(permissionsByCode.administrador['staff.players.ban'] == true, 'administrador nao recebeu ban')
expect(permissionsByCode.administrador['staff.bans.view'] == true, 'administrador nao recebeu consulta de bans')
expect(permissionsByCode.administrador['staff.bans.revoke'] ~= true, 'administrador recebeu revogacao de ban')
expect(permissionsByCode.administrador['staff.whitelist.view'] == true, 'administrador nao recebeu consulta de whitelist')
expect(permissionsByCode.administrador['staff.whitelist.manage'] == true, 'administrador nao recebeu gestao de whitelist')
expect(permissionsByCode.administrador['staff.warns.revoke'] == true, 'administrador sem revogacao de advertencias')
expect(permissionsByCode.suporte['staff.roles.manage'] ~= true, 'suporte recebeu gestao de cargos')
expect(permissionsByCode.gerente_staff['staff.roles.manage'] == true, 'gerente sem gestao de cargos')
expect(permissionsByCode.gerente_staff['staff.bans.revoke'] == true, 'gerente sem revogacao de ban')
expect(permissionsByCode.gerente_staff['staff.orgs.create'] == true, 'gerente sem gestao de organizacoes')
expect(permissionsByCode.gerente_staff['staff.orgs.duty'] == true, 'gerente sem configuracao de ponto de servico')
expect(permissionsByCode.gerente_staff['staff.weapons.give'] ~= true, 'seed concedeu arma nativa')
expect(MZStaffPermissionSet['staff.staff.manage'] ~= true, 'permissao antiga permaneceu no catalogo')
expect(MZStaffPermissionSet['staff.players.manage'] ~= true, 'permissao ampla antiga permaneceu no catalogo')

Config = nil
dofile('mz_admin/shared/config.lua')
dofile('mz_admin/shared/permissions.lua')
for action, permission in pairs(MZAdminPermissions or {}) do
  expect(
    MZStaffPermissionSet[permission] == true,
    ('acao administrativa %s usa permissao fora do catalogo: %s'):format(tostring(action), tostring(permission))
  )
end

rolesByCode.suporte.name = 'Suporte Customizado'
permissionsByCode.suporte['staff.players.heal'] = nil
MZStaffSeed.ensureDefaultRoles()

expect(createCalls == 4, 'restart recriou cargos existentes')
expect(rolesByCode.suporte.name == 'Suporte Customizado', 'restart sobrescreveu nome customizado')
expect(permissionsByCode.suporte['staff.players.heal'] == nil, 'restart sobrescreveu permissoes customizadas')
expect(MZCoreState.seedStage == 'staff_roles:done', 'seed nao concluiu seu estado')

print('mz_core default Staff roles harness: PASS')
