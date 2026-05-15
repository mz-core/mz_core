MZSeed = MZSeed or {}

local function setSeedStage(stage)
  if MZCoreState then
    MZCoreState.seedStage = tostring(stage or 'unknown')
  end
end

local function runSeedQuery(kind, query, params)
  local stage = MZCoreState and MZCoreState.seedStage or 'unknown'
  local ok, result = xpcall(function()
    if kind == 'single' then
      return MySQL.single.await(query, params or {})
    end

    if kind == 'all' then
      return MySQL.query.await(query, params or {}) or {}
    end

    return MySQL.query.await(query, params or {})
  end, debug.traceback)

  if not ok then
    error(('[mz_core][seed] query failed stage=%s error=%s'):format(tostring(stage), tostring(result)), 0)
  end

  return result
end

local function querySingle(query, params)
  return runSeedQuery('single', query, params)
end

local function queryAll(query, params)
  return runSeedQuery('all', query, params)
end

local function exec(query, params)
  return runSeedQuery('exec', query, params)
end

local function getOrgTypeId(typeCode)
  local row = querySingle('SELECT id FROM mz_org_types WHERE code = ? LIMIT 1', { typeCode })
  return row and row.id or nil
end

local function getOrgByCode(code)
  return querySingle('SELECT * FROM mz_orgs WHERE code = ? LIMIT 1', { code })
end

local function getGradeByLevel(orgId, level)
  return querySingle('SELECT * FROM mz_org_grades WHERE org_id = ? AND level = ? LIMIT 1', { orgId, level })
end

local function getGradeByCode(orgId, code)
  return querySingle('SELECT * FROM mz_org_grades WHERE org_id = ? AND code = ? LIMIT 1', { orgId, code })
end

local function getFreeTemporaryGradeLevel(orgId, gradeId)
  local base = -100000000 - tonumber(gradeId or 0)

  for offset = 0, 1000 do
    local candidate = base - offset
    if not getGradeByLevel(orgId, candidate) then
      return candidate
    end
  end

  error(('[mz_core][seed] unable to allocate temporary grade level orgId=%s gradeId=%s'):format(
    tostring(orgId),
    tostring(gradeId)
  ), 0)
end

local function reserveExistingSeedGradeLevels(orgId, gradeDefs)
  setSeedStage(('grade_reserve_levels:orgId=%s'):format(tostring(orgId)))

  for _, gradeDef in ipairs(gradeDefs or {}) do
    local existing = getGradeByCode(orgId, gradeDef.code)
    if existing then
      local temporaryLevel = getFreeTemporaryGradeLevel(orgId, existing.id)
      exec('UPDATE mz_org_grades SET level = ? WHERE id = ?', {
        temporaryLevel,
        existing.id
      })
      print(('[mz_core][seed] grade temporary level orgId=%s code=%s oldLevel=%s tempLevel=%s'):format(
        tostring(orgId),
        tostring(gradeDef.code),
        tostring(existing.level),
        tostring(temporaryLevel)
      ))
    end
  end
end

local function ensureOrg(def)
  setSeedStage(('org:%s'):format(tostring(def and def.code or 'unknown')))

  local existing = getOrgByCode(def.code)
  if existing then
    return existing
  end

  local typeId = getOrgTypeId(def.type)
  if not typeId then
    print(('[mz_core] seed warning: org type not found for %s (%s)'):format(def.code, def.type))
    return nil
  end

  exec([[
    INSERT INTO mz_orgs (
      type_id, code, name, is_public, requires_whitelist, has_salary,
      has_shared_account, has_storage, active, config_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    typeId,
    def.code,
    def.name,
    def.is_public and 1 or 0,
    def.requires_whitelist == false and 0 or 1,
    def.has_salary == false and 0 or 1,
    def.has_shared_account and 1 or 0,
    def.has_storage and 1 or 0,
    def.active == false and 0 or 1,
    json.encode(def.config or {})
  })

  return getOrgByCode(def.code)
end

local function ensureGrade(orgId, gradeDef)
  setSeedStage(('grade:orgId=%s level=%s code=%s'):format(
    tostring(orgId),
    tostring(gradeDef and gradeDef.level or 'unknown'),
    tostring(gradeDef and gradeDef.code or 'unknown')
  ))

  local existing = getGradeByCode(orgId, gradeDef.code)
  if existing then
    local blocker = getGradeByLevel(orgId, gradeDef.level)
    if blocker and tonumber(blocker.id) ~= tonumber(existing.id) then
      error(('[mz_core][seed] grade level conflict orgId=%s code=%s level=%s blockerId=%s blockerCode=%s'):format(
        tostring(orgId),
        tostring(gradeDef.code),
        tostring(gradeDef.level),
        tostring(blocker.id),
        tostring(blocker.code)
      ), 0)
    end

    exec([[
      UPDATE mz_org_grades
      SET level = ?, name = ?, salary = ?, priority = ?, config_json = ?
      WHERE id = ?
    ]], {
      gradeDef.level,
      gradeDef.name,
      gradeDef.salary or 0,
      gradeDef.priority or gradeDef.level,
      json.encode(gradeDef.config or {}),
      existing.id
    })

    print(('[mz_core][seed] grade updated orgId=%s code=%s level=%s'):format(
      tostring(orgId),
      tostring(gradeDef.code),
      tostring(gradeDef.level)
    ))

    return getGradeByCode(orgId, gradeDef.code)
  end

  local blocker = getGradeByLevel(orgId, gradeDef.level)
  if blocker then
    error(('[mz_core][seed] grade level conflict orgId=%s code=%s level=%s blockerId=%s blockerCode=%s'):format(
      tostring(orgId),
      tostring(gradeDef.code),
      tostring(gradeDef.level),
      tostring(blocker.id),
      tostring(blocker.code)
    ), 0)
  end

  exec([[
    INSERT INTO mz_org_grades (
      org_id, level, code, name, salary, inherits_grade_id, priority, config_json
    ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)
  ]], {
    orgId,
    gradeDef.level,
    gradeDef.code,
    gradeDef.name,
    gradeDef.salary or 0,
    gradeDef.priority or gradeDef.level,
    json.encode(gradeDef.config or {})
  })

  print(('[mz_core][seed] grade created orgId=%s code=%s level=%s'):format(
    tostring(orgId),
    tostring(gradeDef.code),
    tostring(gradeDef.level)
  ))

  return getGradeByCode(orgId, gradeDef.code)
end

local function ensureGradeInheritance(orgId, gradeDef)
  setSeedStage(('grade_inheritance:orgId=%s level=%s inherits=%s'):format(
    tostring(orgId),
    tostring(gradeDef and gradeDef.level or 'unknown'),
    tostring(gradeDef and gradeDef.inherits_level or 'none')
  ))

  local grade = getGradeByLevel(orgId, gradeDef.level)

  if not grade then
    return
  end

  if not gradeDef.inherits_level then
    if grade.inherits_grade_id ~= nil then
      exec('UPDATE mz_org_grades SET inherits_grade_id = NULL WHERE id = ?', { grade.id })
    end

    return
  end

  local parent = getGradeByLevel(orgId, gradeDef.inherits_level)

  if not parent then
    return
  end

  if tonumber(grade.inherits_grade_id) == tonumber(parent.id) then
    return
  end

  exec('UPDATE mz_org_grades SET inherits_grade_id = ? WHERE id = ?', {
    parent.id, grade.id
  })
end

local function ensurePermission(orgId, gradeId, permission, allow)
  setSeedStage(('permission:orgId=%s gradeId=%s permission=%s'):format(
    tostring(orgId),
    tostring(gradeId),
    tostring(permission)
  ))

  local row = querySingle([[
    SELECT id, allow
    FROM mz_org_permissions
    WHERE org_id <=> ? AND grade_id <=> ? AND permission = ?
    LIMIT 1
  ]], { orgId, gradeId, permission })

  if row then
    if tonumber(row.allow) ~= (allow and 1 or 0) then
      exec('UPDATE mz_org_permissions SET allow = ? WHERE id = ?', {
        allow and 1 or 0, row.id
      })
    end
    return
  end

  exec([[
    INSERT INTO mz_org_permissions (org_id, grade_id, permission, allow)
    VALUES (?, ?, ?, ?)
  ]], {
    orgId, gradeId, permission, allow and 1 or 0
  })
end

local defaultOrgs = {
  {
    type = 'job',
    code = 'police',
    name = 'Polícia Militar',
    is_public = false,
    requires_whitelist = true,
    has_salary = true,
    has_shared_account = true,
    has_storage = true,

    grades = {
      { level = 1, code = 'recruta', name = 'Recruta', salary = 1200 },
      { level = 2, code = 'soldado', name = 'Soldado', salary = 1500, inherits_level = 1 },
      { level = 3, code = 'cabo', name = 'Cabo', salary = 1800, inherits_level = 2 },
      { level = 4, code = 'sargento', name = 'Sargento', salary = 2200, inherits_level = 3 },
      { level = 5, code = 'subtenente', name = 'Subtenente', salary = 2800, inherits_level = 4 },
      { level = 6, code = 'tenente', name = 'Tenente', salary = 3500, inherits_level = 5 },
      { level = 7, code = 'capitao', name = 'Capitão', salary = 4500, inherits_level = 6 },
      { level = 8, code = 'major', name = 'Major', salary = 6000, inherits_level = 7 },
      { level = 9, code = 'coronel', name = 'Coronel', salary = 8000, inherits_level = 8 },
      { level = 10, code = 'comandante', name = 'Comandante-Geral', salary = 10000, inherits_level = 9 }
    },

    base_permissions = {
      'org.view',
      'radio.use',
      'tablet.open',
      'mdt.open',
      'storage.open'
    },

    grade_permissions = {
      [1] = {
        'armory.basic',
        'vehicle.basic'
      },

      [2] = {
        'patrol.basic',
        'vehicle.basic'
      },

      [3] = {
        'patrol.lead',
        'vehicle.medium',
        'members.view'
      },

      [4] = {
        'vehicle.medium',
        'goals.view',
        'recruitment.view',
        'logs.view'
      },

      [5] = {
        'vehicle.advanced',
        'members.invite',
        'members.remove',
        'goals.manage'
      },

      [6] = {
        'members.promote',
        'members.demote',
        'manage.members',
        'reports.approve'
      },

      [7] = {
        'account.view',
        'recruitment.manage',
        'manage.goals',
        'manage.team'
      },

      [8] = {
        'manage.members',
        'manage.account',
        'logs.view',
        'boss.actions'
      },

      [9] = {
        'manage.permissions',
        'org.settings',
        'manage.account',
        'highcommand'
      },

      [10] = {
        'manage.permissions',
        'manage.account',
        'org.settings',
        'boss.actions',
        'command.full'
      }
    }
  },
  {
    type = 'job',
    code = 'ambulance',
    name = 'Hospital',
    has_salary = true,
    has_shared_account = true,
    has_storage = true,
    grades = {
      { level = 1, code = 'trainee', name = 'Trainee', salary = 1400 },
      { level = 2, code = 'socorrista', name = 'Socorrista', salary = 1700, inherits_level = 1 },
      { level = 3, code = 'medico', name = 'Médico', salary = 2200, inherits_level = 2 }
    },
    base_permissions = {
      'ambulance.radio.use',
      'ambulance.tablet.open'
    },
    grade_permissions = {
      [1] = {
        'ambulance.medkit.basic'
      },
      [2] = {
        'ambulance.revive.basic',
        'ambulance.vehicle.basic'
      },
      [3] = {
        'ambulance.manage.team',
        'ambulance.revive.advanced'
      }
    }
  },
  {
    type = 'job',
    code = 'mechanic',
    name = 'Mecânica',
    has_salary = true,
    has_shared_account = true,
    has_storage = true,
    grades = {
      { level = 1, code = 'aprendiz', name = 'Aprendiz', salary = 1200 },
      { level = 2, code = 'mecanico', name = 'Mecânico', salary = 1600, inherits_level = 1 },
      { level = 3, code = 'chefe', name = 'Chefe', salary = 2200, inherits_level = 2 }
    },
    base_permissions = {
      'mechanic.tablet.open'
    },
    grade_permissions = {
      [1] = {
        'mechanic.repair.basic'
      },
      [2] = {
        'mechanic.repair.advanced',
        'mechanic.tow.use'
      },
      [3] = {
        'mechanic.manage.team',
        'mechanic.boss.actions'
      }
    }
  },
  {
    type = 'gang',
    code = 'mafia',
    name = 'Máfia',

    is_public = false,
    requires_whitelist = true,
    has_salary = false,
    has_shared_account = true,
    has_storage = true,

    grades = {
      { level = 1, code = 'recruta', name = 'Recruta', salary = 0 },
      { level = 2, code = 'membro', name = 'Membro', salary = 0, inherits_level = 1 },
      { level = 3, code = 'gerente', name = 'Gerente', salary = 0, inherits_level = 2 },
      { level = 4, code = 'lider', name = 'Líder', salary = 0, inherits_level = 3 }
    },

    base_capabilities = {
      'radio.use',
      'storage.open'
    },

    grade_capabilities = {
      [1] = {
        'vehicle.basic'
      },
      [2] = {
        'vehicle.medium',
        'storage.deposit'
      },
      [3] = {
        'storage.withdraw',
        'members.invite',
        'vehicle.advanced'
      },
      [4] = {
        'manage.members',
        'manage.account',
        'boss.actions'
      }
    }
  },
  {
    type = 'staff',
    code = 'staff',
    name = 'Staff',
    has_salary = false,
    has_shared_account = false,
    has_storage = false,
    grades = {
      { level = 1, code = 'helper', name = 'Helper', salary = 0 },
      { level = 2, code = 'moderador', name = 'Moderador', salary = 0, inherits_level = 1 },
      { level = 3, code = 'admin', name = 'Admin', salary = 0, inherits_level = 2 }
    },
    base_permissions = {
      'staff.panel.open'
    },
    grade_permissions = {
      [1] = {
        'staff.report.view'
      },
      [2] = {
        'staff.kick',
        'staff.spectate'
      },
      [3] = {
        'staff.ban',
        'staff.teleport',
        'staff.orgs.manage'
      }
    }
  },
  {
    type = 'vip',
    code = 'vip',
    name = 'VIP',
    has_salary = false,
    has_shared_account = false,
    has_storage = false,
    grades = {
      { level = 1, code = 'bronze', name = 'Bronze', salary = 0 },
      { level = 2, code = 'silver', name = 'Silver', salary = 0, inherits_level = 1 },
      { level = 3, code = 'gold', name = 'Gold', salary = 0, inherits_level = 2 }
    },
    base_permissions = {
      'vip.chat.tag'
    },
    grade_permissions = {
      [1] = {
        'vip.kit.bronze'
      },
      [2] = {
        'vip.kit.silver'
      },
      [3] = {
        'vip.kit.gold'
      }
    }
  }
}

function MZSeed.ensureDefaultOrgs()
  setSeedStage('start')
  print('[mz_core][seed] default org seed start')

  for _, orgDef in ipairs(defaultOrgs) do
    print(('[mz_core][seed] org=%s type=%s'):format(
      tostring(orgDef.code),
      tostring(orgDef.type)
    ))

    local org = ensureOrg(orgDef)
    if org then
      reserveExistingSeedGradeLevels(org.id, orgDef.grades or {})

      for _, gradeDef in ipairs(orgDef.grades or {}) do
        ensureGrade(org.id, gradeDef)
      end

      for _, gradeDef in ipairs(orgDef.grades or {}) do
        ensureGradeInheritance(org.id, gradeDef)
      end

      for _, permission in ipairs(orgDef.base_permissions or {}) do
        ensurePermission(org.id, nil, permission, true)
      end

      for level, permissions in pairs(orgDef.grade_permissions or {}) do
        local grade = getGradeByLevel(org.id, tonumber(level))
        if grade then
          for _, permission in ipairs(permissions) do
            ensurePermission(org.id, grade.id, permission, true)
          end
        end
      end
    end
  end

  print('[mz_core] default org seed completed')
end
