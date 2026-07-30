MZOrgStaffMutationRepository = MZOrgStaffMutationRepository or {}

local function statement(query, parameters)
  return { query = query, parameters = parameters }
end

function MZOrgStaffMutationRepository.getAuditById(auditId)
  return MySQL.single.await([[
    SELECT id, scope, action, actor, target, org_code, audit_id, data_json, created_at
    FROM mz_logs
    WHERE audit_id = ?
    LIMIT 1
  ]], { auditId })
end

function MZOrgStaffMutationRepository.createWithAudit(data, template)
  local statements = {
    statement([[
      INSERT INTO mz_orgs (
        type_id, code, name, is_public, requires_whitelist, has_salary,
        has_shared_account, has_storage, active, revision, config_json
      ) VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, 1, ?)
    ]], {
      data.type_id, data.code, data.name, data.is_public and 1 or 0,
      data.has_salary and 1 or 0, data.has_shared_account and 1 or 0,
      data.has_storage and 1 or 0, data.active and 1 or 0, data.config_json
    })
  }

  if data.has_shared_account then
    statements[#statements + 1] = statement([[
      INSERT INTO mz_org_accounts (org_id, balance)
      SELECT o.id, 0 FROM mz_orgs o WHERE o.code = ?
    ]], { data.code })
  end

  local previousLevel = nil
  for _, grade in ipairs(type(template) == 'table' and template.grades or {}) do
    statements[#statements + 1] = statement([[
      INSERT INTO mz_org_grades (
        org_id, level, code, name, salary, inherits_grade_id, priority, active, config_json
      )
      SELECT o.id, ?, ?, ?, ?, (
        SELECT parent.id FROM mz_org_grades parent
        WHERE parent.org_id = o.id AND parent.level = ? LIMIT 1
      ), ?, 1, ?
      FROM mz_orgs o
      WHERE o.code = ?
    ]], {
      grade.level, grade.code, grade.name,
      data.has_salary and (tonumber(grade.salary) or 0) or 0,
      previousLevel, grade.priority or grade.level,
      MZUtils.jsonEncode({ template = data.type_code }), data.code
    })
    previousLevel = grade.level
  end

  for _, permission in ipairs(type(template) == 'table' and template.base_permissions or {}) do
    statements[#statements + 1] = statement([[
      INSERT INTO mz_org_permissions (org_id, grade_id, permission, allow)
      SELECT o.id, NULL, ?, 1 FROM mz_orgs o WHERE o.code = ?
    ]], { permission, data.code })
  end

  for level, permissions in pairs(type(template) == 'table' and template.grade_permissions or {}) do
    for _, permission in ipairs(permissions or {}) do
      statements[#statements + 1] = statement([[
        INSERT INTO mz_org_permissions (org_id, grade_id, permission, allow)
        SELECT o.id, g.id, ?, 1
        FROM mz_orgs o
        INNER JOIN mz_org_grades g ON g.org_id = o.id AND g.level = ?
        WHERE o.code = ?
      ]], { permission, tonumber(level), data.code })
    end
  end

  statements[#statements + 1] = statement([[
    INSERT INTO mz_logs (scope, action, actor, target, org_code, audit_id, data_json)
    SELECT 'orgs', ?, ?, o.code, o.code, ?, ?
    FROM mz_orgs o
    WHERE o.code = ? AND o.revision = 1
  ]], { data.action, data.actor, data.audit_id, data.audit_json, data.code })

  return MySQL.transaction.await(statements) == true
end

function MZOrgStaffMutationRepository.updateWithAudit(kind, data)
  local updateQuery
  local updateParameters

  if kind == 'basic' then
    updateQuery = [[
      UPDATE mz_orgs
      SET name = ?, config_json = ?, revision = revision + 1, updated_at = CURRENT_TIMESTAMP
      WHERE code = ? AND revision = ? AND active = 1
    ]]
    updateParameters = { data.name, data.config_json, data.code, data.expected_revision }
  elseif kind == 'type' then
    updateQuery = [[
      UPDATE mz_orgs
      SET type_id = ?, config_json = ?, revision = revision + 1, updated_at = CURRENT_TIMESTAMP
      WHERE code = ? AND revision = ? AND active = 1
    ]]
    updateParameters = { data.type_id, data.config_json, data.code, data.expected_revision }
  elseif kind == 'features' or kind == 'appearance' or kind == 'duty' then
    updateQuery = [[
      UPDATE mz_orgs
      SET config_json = ?, revision = revision + 1, updated_at = CURRENT_TIMESTAMP
      WHERE code = ? AND revision = ? AND active = 1
    ]]
    updateParameters = { data.config_json, data.code, data.expected_revision }
  elseif kind == 'archive' then
    updateQuery = [[
      UPDATE mz_orgs
      SET active = 0, config_json = ?, revision = revision + 1, updated_at = CURRENT_TIMESTAMP
      WHERE code = ? AND revision = ? AND active = 1
    ]]
    updateParameters = { data.config_json, data.code, data.expected_revision }
  elseif kind == 'restore' then
    updateQuery = [[
      UPDATE mz_orgs
      SET active = 1, config_json = ?, revision = revision + 1, updated_at = CURRENT_TIMESTAMP
      WHERE code = ? AND revision = ? AND active = 0
    ]]
    updateParameters = { data.config_json, data.code, data.expected_revision }
  else
    return false
  end

  local nextRevision = tonumber(data.expected_revision) + 1
  local committed = MySQL.transaction.await({
    statement(updateQuery, updateParameters),
    statement([[
      INSERT INTO mz_logs (scope, action, actor, target, org_code, audit_id, data_json)
      SELECT 'orgs', ?, ?, o.code, o.code, ?, ?
      FROM mz_orgs o
      WHERE o.code = ? AND o.revision = ?
    ]], { data.action, data.actor, data.audit_id, data.audit_json, data.code, nextRevision })
  }) == true

  if not committed then return false end
  local audit = MZOrgStaffMutationRepository.getAuditById(data.audit_id)
  local org = MZOrgRepository.getOrgByCode(data.code)
  return audit ~= nil and org ~= nil and tonumber(org.revision) == nextRevision
end
