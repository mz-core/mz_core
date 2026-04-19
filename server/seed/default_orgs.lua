MZSeed = MZSeed or {}

local function querySingle(query, params)
  return MySQL.single.await(query, params or {})
end

local function queryAll(query, params)
  return MySQL.query.await(query, params or {}) or {}
end

local function exec(query, params)
  return MySQL.query.await(query, params or {})
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

local function ensureOrg(def)
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
  local existing = getGradeByLevel(orgId, gradeDef.level)
  if existing then
    return existing
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

  return getGradeByLevel(orgId, gradeDef.level)
end

local function ensureGradeInheritance(orgId, gradeDef)
  if not gradeDef.inherits_level then
    return
  end

  local grade = getGradeByLevel(orgId, gradeDef.level)
  local parent = getGradeByLevel(orgId, gradeDef.inherits_level)

  if not grade or not parent then
    return
  end

  if grade.inherits_grade_id == parent.id then
    return
  end

  exec('UPDATE mz_org_grades SET inherits_grade_id = ? WHERE id = ?', {
    parent.id, grade.id
  })
end

local function ensurePermission(orgId, gradeId, permission, allow)
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
    name = 'Polícia',
    has_salary = true,
    has_shared_account = true,
    has_storage = true,
    grades = {
      { level = 1, code = 'soldado', name = 'Soldado', salary = 1500 },
      { level = 2, code = 'cabo', name = 'Cabo', salary = 1800, inherits_level = 1 },
      { level = 3, code = 'sargento', name = 'Sargento', salary = 2200, inherits_level = 2 }
    },
    base_permissions = {
      'police.radio.use',
      'police.tablet.open'
    },
    grade_permissions = {
      [1] = {
        'police.armory.basic',
        'police.vehicle.basic'
      },
      [2] = {
        'police.patrol.lead',
        'police.vehicle.medium'
      },
      [3] = {
        'police.manage.team',
        'police.reports.approve'
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
  for _, orgDef in ipairs(defaultOrgs) do
    local org = ensureOrg(orgDef)
    if org then
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