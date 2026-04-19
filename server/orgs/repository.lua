MZOrgRepository = {}

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

function MZOrgRepository.getOrgTypeByCode(code)
  return MySQL.single.await('SELECT * FROM mz_org_types WHERE code = ? LIMIT 1', { code })
end

function MZOrgRepository.getOrgById(orgId)
  return MySQL.single.await([[
    SELECT o.*, t.code AS type_code, t.name AS type_name
    FROM mz_orgs o
    INNER JOIN mz_org_types t ON t.id = o.type_id
    WHERE o.id = ?
    LIMIT 1
  ]], { orgId })
end

function MZOrgRepository.getOrgByCode(code)
  return MySQL.single.await([[
    SELECT o.*, t.code AS type_code, t.name AS type_name
    FROM mz_orgs o
    INNER JOIN mz_org_types t ON t.id = o.type_id
    WHERE o.code = ?
    LIMIT 1
  ]], { code })
end

function MZOrgRepository.listOrgs(orgTypeCode)
  if orgTypeCode then
    return MySQL.query.await([[
      SELECT o.*, t.code AS type_code, t.name AS type_name
      FROM mz_orgs o
      INNER JOIN mz_org_types t ON t.id = o.type_id
      WHERE t.code = ?
      ORDER BY o.name ASC
    ]], { orgTypeCode }) or {}
  end

  return MySQL.query.await([[
    SELECT o.*, t.code AS type_code, t.name AS type_name
    FROM mz_orgs o
    INNER JOIN mz_org_types t ON t.id = o.type_id
    ORDER BY t.code ASC, o.name ASC
  ]]) or {}
end

function MZOrgRepository.createOrg(data)
  local insertId = MySQL.insert.await([[
    INSERT INTO mz_orgs (
      type_id, code, name, is_public, requires_whitelist, has_salary,
      has_shared_account, has_storage, active, config_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    data.type_id,
    data.code,
    data.name,
    data.is_public and 1 or 0,
    data.requires_whitelist ~= false and 1 or 0,
    data.has_salary ~= false and 1 or 0,
    data.has_shared_account and 1 or 0,
    data.has_storage and 1 or 0,
    data.active ~= false and 1 or 0,
    MZUtils.jsonEncode(data.config or {})
  })

  return insertId and MZOrgRepository.getOrgById(insertId) or nil
end

function MZOrgRepository.createGrade(orgId, data)
  local insertId = MySQL.insert.await([[
    INSERT INTO mz_org_grades (
      org_id, level, code, name, salary, inherits_grade_id, priority, config_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    orgId,
    data.level,
    data.code,
    data.name,
    data.salary or 0,
    data.inherits_grade_id,
    data.priority or data.level or 0,
    MZUtils.jsonEncode(data.config or {})
  })

  return insertId and MZOrgRepository.getGradeById(insertId) or nil
end

function MZOrgRepository.getGradeById(gradeId)
  return MySQL.single.await('SELECT * FROM mz_org_grades WHERE id = ? LIMIT 1', { gradeId })
end

function MZOrgRepository.getGradeByLevel(orgId, level)
  return MySQL.single.await('SELECT * FROM mz_org_grades WHERE org_id = ? AND level = ? LIMIT 1', { orgId, level })
end

function MZOrgRepository.getGradeByCode(orgId, code)
  return MySQL.single.await('SELECT * FROM mz_org_grades WHERE org_id = ? AND code = ? LIMIT 1', { orgId, code })
end

function MZOrgRepository.getPlayerMembership(citizenid, orgId)
  return MySQL.single.await([[
    SELECT *
    FROM mz_player_orgs
    WHERE citizenid = ? AND org_id = ?
    LIMIT 1
  ]], { citizenid, orgId })
end

function MZOrgRepository.getPlayerMemberships(citizenid)
  return MySQL.query.await([[
    SELECT po.*, o.code AS org_code, o.name AS org_name, t.code AS type_code,
           g.level AS grade_level, g.code AS grade_code, g.name AS grade_name, g.salary
    FROM mz_player_orgs po
    INNER JOIN mz_orgs o ON o.id = po.org_id
    INNER JOIN mz_org_types t ON t.id = o.type_id
    INNER JOIN mz_org_grades g ON g.id = po.grade_id
    WHERE po.citizenid = ? AND po.active = 1
    ORDER BY po.is_primary DESC, g.level DESC
  ]], { citizenid }) or {}
end

function MZOrgRepository.getPermissionsForOrg(orgId)
  return MySQL.query.await('SELECT * FROM mz_org_permissions WHERE org_id = ? ORDER BY id ASC', { orgId }) or {}
end

function MZOrgRepository.setPermission(orgId, gradeId, permission, allow)
  MySQL.insert.await([[
    INSERT INTO mz_org_permissions (org_id, grade_id, permission, allow)
    VALUES (?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE allow = VALUES(allow)
  ]], { orgId, gradeId, permission, allow and 1 or 0 })
end

function MZOrgRepository.removePermission(orgId, gradeId, permission)
  MySQL.query.await([[
    DELETE FROM mz_org_permissions
    WHERE org_id = ? AND ((grade_id IS NULL AND ? IS NULL) OR grade_id = ?) AND permission = ?
  ]], { orgId, gradeId, gradeId, permission })
end

function MZOrgRepository.getGradesForOrg(orgId)
  return MySQL.query.await('SELECT * FROM mz_org_grades WHERE org_id = ? ORDER BY level ASC', { orgId }) or {}
end

function MZOrgRepository.setMembership(citizenid, orgId, gradeId, isPrimary, duty, expiresAt)
  MySQL.insert.await([[
    INSERT INTO mz_player_orgs (citizenid, org_id, grade_id, is_primary, active, duty, expires_at)
    VALUES (?, ?, ?, ?, 1, ?, ?)
    ON DUPLICATE KEY UPDATE
      grade_id = VALUES(grade_id),
      is_primary = VALUES(is_primary),
      active = 1,
      duty = VALUES(duty),
      expires_at = VALUES(expires_at),
      updated_at = CURRENT_TIMESTAMP
  ]], {
    citizenid,
    orgId,
    gradeId,
    isPrimary and 1 or 0,
    duty and 1 or 0,
    expiresAt
  })
end

function MZOrgRepository.updateMembershipGrade(citizenid, orgId, gradeId)
  MySQL.update.await([[
    UPDATE mz_player_orgs
    SET grade_id = ?, updated_at = CURRENT_TIMESTAMP
    WHERE citizenid = ? AND org_id = ?
  ]], { gradeId, citizenid, orgId })
end

function MZOrgRepository.setMembershipDuty(citizenid, orgId, duty)
  MySQL.update.await([[
    UPDATE mz_player_orgs
    SET duty = ?, updated_at = CURRENT_TIMESTAMP
    WHERE citizenid = ? AND org_id = ?
  ]], { duty and 1 or 0, citizenid, orgId })
end

function MZOrgRepository.setPrimaryMembership(citizenid, orgTypeCode, orgId)
  MySQL.update.await([[
    UPDATE mz_player_orgs po
    INNER JOIN mz_orgs o ON o.id = po.org_id
    INNER JOIN mz_org_types t ON t.id = o.type_id
    SET po.is_primary = CASE WHEN po.org_id = ? THEN 1 ELSE 0 END,
        po.updated_at = CURRENT_TIMESTAMP
    WHERE po.citizenid = ? AND t.code = ?
  ]], { orgId, citizenid, orgTypeCode })
end

function MZOrgRepository.removeMembership(citizenid, orgId)
  MySQL.update.await([[
    UPDATE mz_player_orgs
    SET active = 0, updated_at = CURRENT_TIMESTAMP
    WHERE citizenid = ? AND org_id = ?
  ]], { citizenid, orgId })
end

function MZOrgRepository.getPlayerOverrides(citizenid)
  return MySQL.query.await([[
    SELECT * FROM mz_player_permissions
    WHERE citizenid = ? AND (expires_at IS NULL OR expires_at > NOW())
  ]], { citizenid }) or {}
end

function MZOrgRepository.setPlayerOverride(citizenid, permission, allow, expiresAt)
  MySQL.insert.await([[
    INSERT INTO mz_player_permissions (citizenid, permission, allow, expires_at)
    VALUES (?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE allow = VALUES(allow), expires_at = VALUES(expires_at)
  ]], { citizenid, permission, allow and 1 or 0, expiresAt })
end

function MZOrgRepository.removePlayerOverride(citizenid, permission)
  MySQL.query.await('DELETE FROM mz_player_permissions WHERE citizenid = ? AND permission = ?', { citizenid, permission })
end
