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

function MZOrgRepository.updateOrgBasicInfo(orgCode, data)
  orgCode = tostring(orgCode or '')
  if orgCode == '' or type(data) ~= 'table' then return nil end

  MySQL.update.await([[
    UPDATE mz_orgs
    SET name = ?,
        is_public = ?,
        has_salary = ?,
        has_shared_account = ?,
        has_storage = ?,
        active = ?,
        revision = revision + 1,
        updated_at = CURRENT_TIMESTAMP
    WHERE code = ?
  ]], {
    data.name,
    data.is_public and 1 or 0,
    data.has_salary and 1 or 0,
    data.has_shared_account and 1 or 0,
    data.has_storage and 1 or 0,
    data.active ~= false and 1 or 0,
    orgCode
  })

  return MZOrgRepository.getOrgByCode(orgCode)
end

function MZOrgRepository.createGrade(orgId, data)
  local insertId = MySQL.insert.await([[
    INSERT INTO mz_org_grades (
      org_id, level, code, name, salary, inherits_grade_id, priority, active, config_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    orgId,
    data.level,
    data.code,
    data.name,
    data.salary or 0,
    data.inherits_grade_id,
    data.priority or data.level or 0,
    data.active == false and 0 or 1,
    MZUtils.jsonEncode(data.config or {})
  })

  return insertId and MZOrgRepository.getGradeById(insertId) or nil
end

function MZOrgRepository.getGradeById(gradeId)
  return MySQL.single.await('SELECT * FROM mz_org_grades WHERE id = ? LIMIT 1', { gradeId })
end

function MZOrgRepository.getOrgGradeById(orgId, gradeId)
  return MySQL.single.await('SELECT * FROM mz_org_grades WHERE org_id = ? AND id = ? LIMIT 1', { orgId, gradeId })
end

function MZOrgRepository.getGradeByLevel(orgId, level, includeInactive)
  local sql = 'SELECT * FROM mz_org_grades WHERE org_id = ? AND level = ?'
  if not includeInactive then sql = sql .. ' AND active = 1' end
  return MySQL.single.await(sql .. ' LIMIT 1', { orgId, level })
end

function MZOrgRepository.getGradeByCode(orgId, code, includeInactive)
  local sql = 'SELECT * FROM mz_org_grades WHERE org_id = ? AND code = ?'
  if not includeInactive then sql = sql .. ' AND active = 1' end
  return MySQL.single.await(sql .. ' LIMIT 1', { orgId, code })
end

function MZOrgRepository.updateOrgGradeBasic(orgId, gradeId, data)
  MySQL.update.await([[
    UPDATE mz_org_grades
    SET level = ?,
        name = ?,
        salary = ?,
        inherits_grade_id = ?,
        priority = ?,
        updated_at = CURRENT_TIMESTAMP
    WHERE org_id = ? AND id = ?
  ]], {
    data.level,
    data.name,
    data.salary or 0,
    data.inherits_grade_id,
    data.priority or data.level or 0,
    orgId,
    gradeId
  })

  return MZOrgRepository.getOrgGradeById(orgId, gradeId)
end

function MZOrgRepository.countMembersByGrade(orgId, gradeId)
  local row = MySQL.single.await([[
    SELECT COUNT(1) AS total
    FROM mz_player_orgs
    WHERE org_id = ? AND grade_id = ? AND active = 1
  ]], { orgId, gradeId })

  return tonumber(row and row.total) or 0
end

function MZOrgRepository.countActiveMembersByGrade(orgId, gradeId)
  local row = MySQL.single.await([[
    SELECT COUNT(1) AS total
    FROM mz_player_orgs po
    INNER JOIN mz_org_grades g ON g.id = po.grade_id AND g.org_id = po.org_id
    WHERE po.org_id = ?
      AND po.grade_id = ?
      AND po.active = 1
      AND g.active = 1
      AND (po.expires_at IS NULL OR po.expires_at > CURRENT_TIMESTAMP)
  ]], { orgId, gradeId })

  return tonumber(row and row.total) or 0
end

function MZOrgRepository.setOrgActive(orgCode, active)
  MySQL.update.await([[
    UPDATE mz_orgs
    SET active = ?, revision = revision + 1, updated_at = CURRENT_TIMESTAMP
    WHERE code = ?
  ]], { active and 1 or 0, orgCode })

  return MZOrgRepository.getOrgByCode(orgCode)
end

function MZOrgRepository.setOrgGradeActive(orgId, gradeId, active)
  MySQL.update.await([[
    UPDATE mz_org_grades
    SET active = ?, updated_at = CURRENT_TIMESTAMP
    WHERE org_id = ? AND id = ?
  ]], { active and 1 or 0, orgId, gradeId })

  return MZOrgRepository.getOrgGradeById(orgId, gradeId)
end

function MZOrgRepository.getPlayerMembership(citizenid, orgId)
  return MySQL.single.await([[
    SELECT *
    FROM mz_player_orgs
    WHERE citizenid = ? AND org_id = ?
    LIMIT 1
  ]], { citizenid, orgId })
end

function MZOrgRepository.getActivePlayerMembership(citizenid, orgId)
  return MySQL.single.await([[
    SELECT *
    FROM mz_player_orgs
    WHERE citizenid = ?
      AND org_id = ?
      AND active = 1
      AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
    LIMIT 1
  ]], { citizenid, orgId })
end

function MZOrgRepository.getPlayerMemberships(citizenid)
  return MySQL.query.await([[
    SELECT po.*, o.code AS org_code, o.name AS org_name, o.active AS org_active,
           o.has_salary, o.has_shared_account, o.has_storage, o.config_json AS org_config_json,
           t.code AS type_code,
           g.level AS grade_level, g.code AS grade_code, g.name AS grade_name, g.salary
    FROM mz_player_orgs po
    INNER JOIN mz_orgs o ON o.id = po.org_id
    INNER JOIN mz_org_types t ON t.id = o.type_id
    INNER JOIN mz_org_grades g ON g.id = po.grade_id
    WHERE po.citizenid = ? AND po.active = 1 AND o.active = 1 AND g.active = 1
    ORDER BY po.is_primary DESC, g.level DESC
  ]], { citizenid }) or {}
end

local GoalTableHasOrgIdColumn = nil

local function goalTableHasOrgIdColumn()
  if GoalTableHasOrgIdColumn ~= nil then
    return GoalTableHasOrgIdColumn
  end

  local row = MySQL.single.await([[
    SELECT COUNT(1) AS total
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'mz_org_goals'
      AND column_name = 'org_id'
  ]])

  GoalTableHasOrgIdColumn = row and tonumber(row.total) and tonumber(row.total) > 0 or false
  return GoalTableHasOrgIdColumn
end

function MZOrgRepository.listMembersForOrg(orgId)
  return MySQL.query.await([[
    SELECT
      po.citizenid,
      po.org_id,
      po.grade_id,
      po.is_primary,
      po.active,
      po.duty,
      po.joined_at,
      po.updated_at,
      o.code AS org_code,
      o.name AS org_name,
      t.code AS type_code,
      g.level AS grade_level,
      g.code AS grade_code,
      g.name AS grade_name,
      p.firstname,
      p.lastname,
      sessions.last_seen_at,
      CASE
        WHEN t.code IN ('job', 'gang', 'business', 'government', 'event')
          AND g.level = (
          SELECT MAX(g2.level)
          FROM mz_org_grades g2
          WHERE g2.org_id = po.org_id AND g2.active = 1
        ) THEN 1
        ELSE 0
      END AS is_leader
    FROM mz_player_orgs po
    INNER JOIN mz_orgs o ON o.id = po.org_id
    INNER JOIN mz_org_types t ON t.id = o.type_id
    INNER JOIN mz_org_grades g ON g.id = po.grade_id
    LEFT JOIN mz_players p ON p.citizenid = po.citizenid
    LEFT JOIN (
      SELECT citizenid, MAX(last_seen_at) AS last_seen_at
      FROM mz_player_sessions
      GROUP BY citizenid
    ) sessions ON sessions.citizenid = po.citizenid
    WHERE po.org_id = ? AND po.active = 1
    ORDER BY g.level DESC, p.firstname ASC, p.lastname ASC, po.citizenid ASC
  ]], { orgId }) or {}
end

function MZOrgRepository.getPermissionsForOrg(orgId)
  return MySQL.query.await('SELECT * FROM mz_org_permissions WHERE org_id = ? ORDER BY id ASC', { orgId }) or {}
end

function MZOrgRepository.listLegacyStaffPermissions()
  return MySQL.query.await([[
    SELECT
      p.id,
      p.org_id,
      p.grade_id,
      p.permission,
      p.allow,
      o.code AS org_code,
      o.name AS org_name,
      o.active AS org_active,
      t.code AS type_code,
      g.code AS grade_code,
      g.name AS grade_name,
      g.level AS grade_level
    FROM mz_org_permissions p
    INNER JOIN mz_orgs o ON o.id = p.org_id
    INNER JOIN mz_org_types t ON t.id = o.type_id
    LEFT JOIN mz_org_grades g ON g.id = p.grade_id
    WHERE LOWER(p.permission) LIKE 'staff.%'
    ORDER BY o.code ASC, g.level ASC, p.permission ASC
  ]]) or {}
end

function MZOrgRepository.getOrgGradePermission(orgId, gradeId, permission)
  return MySQL.single.await([[
    SELECT *
    FROM mz_org_permissions
    WHERE org_id = ? AND grade_id = ? AND permission = ?
    LIMIT 1
  ]], { orgId, gradeId, permission })
end

function MZOrgRepository.listOrgGradePermissions(orgId, gradeId)
  return MySQL.query.await([[
    SELECT *
    FROM mz_org_permissions
    WHERE org_id = ? AND grade_id = ? AND allow = 1
    ORDER BY permission ASC
  ]], { orgId, gradeId }) or {}
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

function MZOrgRepository.getGradesForOrg(orgId, includeInactive)
  local sql = 'SELECT * FROM mz_org_grades WHERE org_id = ?'
  if not includeInactive then sql = sql .. ' AND active = 1' end
  return MySQL.query.await(sql .. ' ORDER BY level ASC', { orgId }) or {}
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

function MZOrgRepository.setMembershipDutyWithAudit(data)
  data = type(data) == 'table' and data or {}
  if not data.citizenid or not data.org_id or not data.org_code
    or not data.action or not data.audit_id or not data.data_json then
    return false
  end

  local desiredDuty = data.duty == true and 1 or 0
  local expectedDuty = data.expected_duty == true and 1 or 0
  local committed = MySQL.transaction.await({
    {
      query = [[
        INSERT INTO mz_logs (
          scope, action, actor, target, org_code, audit_id, data_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ]],
      values = {
        data.scope or 'orgs',
        data.action,
        data.actor,
        data.target or data.citizenid,
        data.org_code,
        data.audit_id,
        data.data_json
      }
    },
    {
      query = [[
        INSERT INTO mz_logs (
          scope, action, actor, target, org_code, audit_id, data_json
        )
        SELECT ?, ?, ?, ?, ?, ?, ?
        WHERE NOT EXISTS (
          SELECT 1
          FROM mz_player_orgs
          WHERE citizenid = ?
            AND org_id = ?
            AND active = 1
            AND duty = ?
            AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
        )
      ]],
      values = {
        data.scope or 'orgs',
        data.action .. '.precondition_failed',
        data.actor,
        data.target or data.citizenid,
        data.org_code,
        data.audit_id,
        data.data_json,
        data.citizenid,
        data.org_id,
        expectedDuty
      }
    },
    {
      query = [[
        UPDATE mz_player_orgs
        SET duty = ?, updated_at = CURRENT_TIMESTAMP
        WHERE citizenid = ?
          AND org_id = ?
          AND active = 1
          AND duty = ?
          AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
      ]],
      values = { desiredDuty, data.citizenid, data.org_id, expectedDuty }
    },
    {
      query = [[
        INSERT INTO mz_logs (
          scope, action, actor, target, org_code, audit_id, data_json
        )
        SELECT ?, ?, ?, ?, ?, ?, ?
        WHERE NOT EXISTS (
          SELECT 1
          FROM mz_player_orgs
          WHERE citizenid = ?
            AND org_id = ?
            AND active = 1
            AND duty = ?
            AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
        )
      ]],
      values = {
        data.scope or 'orgs',
        data.action .. '.assertion_failed',
        data.actor,
        data.target or data.citizenid,
        data.org_code,
        data.audit_id,
        data.data_json,
        data.citizenid,
        data.org_id,
        desiredDuty
      }
    }
  }) == true
  if not committed then return false end

  local membership = MZOrgRepository.getActivePlayerMembership(data.citizenid, data.org_id)
  local audit = MySQL.single.await(
    'SELECT id FROM mz_logs WHERE audit_id = ? LIMIT 1',
    { data.audit_id }
  )
  return membership ~= nil
    and (membership.duty == true or tonumber(membership.duty) == 1) == (desiredDuty == 1)
    and audit ~= nil
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

function MZOrgRepository.updateMembershipGradeWithAudit(data)
  data = type(data) == 'table' and data or {}
  if not data.citizenid or not data.org_id or not data.grade_id then return false end
  if not data.audit_id or not data.org_code or not data.action then return false end

  local committed = MySQL.transaction.await({
    {
      query = [[
        UPDATE mz_player_orgs
        SET grade_id = ?, updated_at = CURRENT_TIMESTAMP
        WHERE citizenid = ? AND org_id = ? AND active = 1
      ]],
      values = { data.grade_id, data.citizenid, data.org_id }
    },
    {
      query = [[
        INSERT INTO mz_logs (
          scope, action, actor, target, org_code, audit_id, data_json
        )
        SELECT ?, ?, ?, ?, ?, ?, ?
        FROM mz_player_orgs
        WHERE citizenid = ? AND org_id = ? AND grade_id = ? AND active = 1
      ]],
      values = {
        data.scope or 'orgs',
        data.action,
        data.actor,
        data.target,
        data.org_code,
        data.audit_id,
        data.data_json,
        data.citizenid,
        data.org_id,
        data.grade_id
      }
    }
  }) == true
  if not committed then return false end

  local membership = MZOrgRepository.getPlayerMembership(data.citizenid, data.org_id)
  local audit = MySQL.single.await('SELECT id FROM mz_logs WHERE audit_id = ? LIMIT 1', { data.audit_id })
  return membership ~= nil
    and tonumber(membership.grade_id) == tonumber(data.grade_id)
    and audit ~= nil
end

function MZOrgRepository.transferOrganizationLeadershipWithAudit(data)
  data = type(data) == 'table' and data or {}
  if not data.actor_citizenid or not data.target_citizenid or not data.org_id or not data.org_code then
    return false
  end
  if not data.top_grade_id or not data.successor_grade_id or not data.target_grade_id then
    return false
  end
  if not data.expected_revision or not data.audit_id or not data.action or not data.data_json then
    return false
  end

  local nextRevision = tonumber(data.expected_revision) + 1
  local committed = MySQL.transaction.await({
    {
      query = [[
        INSERT INTO mz_logs (
          scope, action, actor, target, org_code, audit_id, data_json
        )
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ]],
      values = {
        data.scope or 'orgs',
        data.action,
        data.actor_citizenid,
        data.target_citizenid,
        data.org_code,
        data.audit_id,
        data.data_json
      }
    },
    {
      query = [[
        INSERT INTO mz_logs (
          scope, action, actor, target, org_code, audit_id, data_json
        )
        SELECT ?, ?, ?, ?, ?, ?, ?
        WHERE NOT EXISTS (
          SELECT 1
          FROM mz_orgs o
          INNER JOIN mz_org_grades top_grade
            ON top_grade.id = ? AND top_grade.org_id = o.id AND top_grade.active = 1
          INNER JOIN mz_org_grades successor_grade
            ON successor_grade.id = ? AND successor_grade.org_id = o.id AND successor_grade.active = 1
          INNER JOIN mz_org_grades target_grade
            ON target_grade.id = ? AND target_grade.org_id = o.id AND target_grade.active = 1
          INNER JOIN mz_player_orgs actor_membership
            ON actor_membership.org_id = o.id
            AND actor_membership.citizenid = ?
            AND actor_membership.grade_id = top_grade.id
            AND actor_membership.active = 1
            AND (actor_membership.expires_at IS NULL OR actor_membership.expires_at > CURRENT_TIMESTAMP)
          INNER JOIN mz_player_orgs target_membership
            ON target_membership.org_id = o.id
            AND target_membership.citizenid = ?
            AND target_membership.grade_id = target_grade.id
            AND target_membership.active = 1
            AND (target_membership.expires_at IS NULL OR target_membership.expires_at > CURRENT_TIMESTAMP)
          WHERE o.id = ?
            AND o.code = ?
            AND o.active = 1
            AND o.revision = ?
            AND actor_membership.citizenid <> target_membership.citizenid
            AND target_grade.level < top_grade.level
            AND top_grade.level = (
              SELECT MAX(candidate_top.level)
              FROM mz_org_grades candidate_top
              WHERE candidate_top.org_id = o.id AND candidate_top.active = 1
            )
            AND successor_grade.level = (
              SELECT MAX(candidate_successor.level)
              FROM mz_org_grades candidate_successor
              WHERE candidate_successor.org_id = o.id
                AND candidate_successor.active = 1
                AND candidate_successor.level < top_grade.level
            )
            AND (
              SELECT COUNT(1)
              FROM mz_player_orgs current_leader
              INNER JOIN mz_org_grades current_leader_grade
                ON current_leader_grade.id = current_leader.grade_id
                AND current_leader_grade.org_id = current_leader.org_id
                AND current_leader_grade.active = 1
              WHERE current_leader.org_id = o.id
                AND current_leader.grade_id = top_grade.id
                AND current_leader.active = 1
                AND (current_leader.expires_at IS NULL OR current_leader.expires_at > CURRENT_TIMESTAMP)
            ) = 1
        )
      ]],
      values = {
        data.scope or 'orgs',
        data.action .. '.precondition_failed',
        data.actor_citizenid,
        data.target_citizenid,
        data.org_code,
        data.audit_id,
        data.data_json,
        data.top_grade_id,
        data.successor_grade_id,
        data.target_grade_id,
        data.actor_citizenid,
        data.target_citizenid,
        data.org_id,
        data.org_code,
        data.expected_revision
      }
    },
    {
      query = [[
        UPDATE mz_player_orgs actor_membership
        INNER JOIN mz_player_orgs target_membership
          ON target_membership.org_id = actor_membership.org_id
          AND target_membership.citizenid = ?
        INNER JOIN mz_orgs o
          ON o.id = actor_membership.org_id
          AND o.active = 1
          AND o.revision = ?
        SET actor_membership.grade_id = ?,
            actor_membership.updated_at = CURRENT_TIMESTAMP,
            target_membership.grade_id = ?,
            target_membership.updated_at = CURRENT_TIMESTAMP
        WHERE actor_membership.org_id = ?
          AND actor_membership.citizenid = ?
          AND actor_membership.grade_id = ?
          AND actor_membership.active = 1
          AND (actor_membership.expires_at IS NULL OR actor_membership.expires_at > CURRENT_TIMESTAMP)
          AND target_membership.grade_id = ?
          AND target_membership.active = 1
          AND (target_membership.expires_at IS NULL OR target_membership.expires_at > CURRENT_TIMESTAMP)
      ]],
      values = {
        data.target_citizenid,
        data.expected_revision,
        data.successor_grade_id,
        data.top_grade_id,
        data.org_id,
        data.actor_citizenid,
        data.top_grade_id,
        data.target_grade_id
      }
    },
    {
      query = [[
        UPDATE mz_orgs
        SET revision = revision + 1, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND code = ? AND active = 1 AND revision = ?
      ]],
      values = { data.org_id, data.org_code, data.expected_revision }
    },
    {
      query = [[
        INSERT INTO mz_logs (
          scope, action, actor, target, org_code, audit_id, data_json
        )
        SELECT ?, ?, ?, ?, ?, ?, ?
        WHERE NOT EXISTS (
          SELECT 1
          FROM mz_orgs o
          INNER JOIN mz_player_orgs previous_leader
            ON previous_leader.org_id = o.id
            AND previous_leader.citizenid = ?
            AND previous_leader.grade_id = ?
            AND previous_leader.active = 1
            AND (previous_leader.expires_at IS NULL OR previous_leader.expires_at > CURRENT_TIMESTAMP)
          INNER JOIN mz_player_orgs new_leader
            ON new_leader.org_id = o.id
            AND new_leader.citizenid = ?
            AND new_leader.grade_id = ?
            AND new_leader.active = 1
            AND (new_leader.expires_at IS NULL OR new_leader.expires_at > CURRENT_TIMESTAMP)
          WHERE o.id = ?
            AND o.code = ?
            AND o.active = 1
            AND o.revision = ?
            AND (
              SELECT COUNT(1)
              FROM mz_player_orgs leader_check
              WHERE leader_check.org_id = o.id
                AND leader_check.grade_id = ?
                AND leader_check.active = 1
                AND (leader_check.expires_at IS NULL OR leader_check.expires_at > CURRENT_TIMESTAMP)
            ) = 1
        )
      ]],
      values = {
        data.scope or 'orgs',
        data.action .. '.assertion_failed',
        data.actor_citizenid,
        data.target_citizenid,
        data.org_code,
        data.audit_id,
        data.data_json,
        data.actor_citizenid,
        data.successor_grade_id,
        data.target_citizenid,
        data.top_grade_id,
        data.org_id,
        data.org_code,
        nextRevision,
        data.top_grade_id
      }
    }
  }) == true
  if not committed then return false end

  local actorMembership = MZOrgRepository.getActivePlayerMembership(data.actor_citizenid, data.org_id)
  local targetMembership = MZOrgRepository.getActivePlayerMembership(data.target_citizenid, data.org_id)
  local org = MZOrgRepository.getOrgById(data.org_id)
  local audit = MySQL.single.await(
    'SELECT id FROM mz_logs WHERE audit_id = ? AND org_code = ? AND action = ? LIMIT 1',
    { data.audit_id, data.org_code, data.action }
  )
  return actorMembership ~= nil
    and tonumber(actorMembership.grade_id) == tonumber(data.successor_grade_id)
    and targetMembership ~= nil
    and tonumber(targetMembership.grade_id) == tonumber(data.top_grade_id)
    and org ~= nil
    and tonumber(org.revision) == nextRevision
    and audit ~= nil
end

function MZOrgRepository.createGoal(org, data)
  local insertId

  if goalTableHasOrgIdColumn() then
    insertId = MySQL.insert.await([[
      INSERT INTO mz_org_goals (
        org_id, org_code, title, description, type, status, target, progress,
        starts_at, ends_at, created_by_citizenid, created_by_name
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
      org.id,
      org.code,
      data.title,
      data.description,
      data.type,
      data.status or 'active',
      data.target or 1,
      data.progress or 0,
      data.starts_at,
      data.ends_at,
      data.created_by_citizenid,
      data.created_by_name
    })
  else
    insertId = MySQL.insert.await([[
      INSERT INTO mz_org_goals (
        org_code, title, description, type, status, target, progress,
        starts_at, ends_at, created_by_citizenid, created_by_name
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
      org.code,
      data.title,
      data.description,
      data.type,
      data.status or 'active',
      data.target or 1,
      data.progress or 0,
      data.starts_at,
      data.ends_at,
      data.created_by_citizenid,
      data.created_by_name
    })
  end

  return insertId and MZOrgRepository.getGoalById(insertId) or nil
end

function MZOrgRepository.getGoalById(goalId)
  return MySQL.single.await([[
    SELECT *
    FROM mz_org_goals
    WHERE id = ?
    LIMIT 1
  ]], { goalId })
end

function MZOrgRepository.listGoals(filters)
  filters = type(filters) == 'table' and filters or {}
  local sql = 'SELECT * FROM mz_org_goals WHERE 1 = 1'
  local params = {}

  if filters.orgCode then
    sql = sql .. ' AND org_code = ?'
    params[#params + 1] = filters.orgCode
  end

  if filters.status then
    sql = sql .. ' AND status = ?'
    params[#params + 1] = filters.status
  end

  if filters.type then
    sql = sql .. ' AND type = ?'
    params[#params + 1] = filters.type
  end

  if filters.search then
    sql = sql .. ' AND (title LIKE ? OR description LIKE ?)'
    local like = '%' .. filters.search .. '%'
    params[#params + 1] = like
    params[#params + 1] = like
  end

  sql = sql .. ' ORDER BY created_at DESC LIMIT ? OFFSET ?'
  params[#params + 1] = tonumber(filters.limit) or 50
  params[#params + 1] = tonumber(filters.offset) or 0

  return MySQL.query.await(sql, params) or {}
end

function MZOrgRepository.createRecruitmentApplication(data)
  local insertId = MySQL.insert.await([[
    INSERT INTO mz_org_recruitment (
      org_code, target_citizenid, target_name, status,
      desired_grade_level, desired_grade_code, note,
      created_by_citizenid, created_by_name, metadata_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    data.org_code,
    data.target_citizenid,
    data.target_name,
    data.status or 'pending',
    data.desired_grade_level,
    data.desired_grade_code,
    data.note,
    data.created_by_citizenid,
    data.created_by_name,
    MZUtils.jsonEncode(data.metadata or {})
  })

  return insertId and MZOrgRepository.getRecruitmentById(insertId) or nil
end

function MZOrgRepository.getRecruitmentById(id)
  return MySQL.single.await([[
    SELECT *
    FROM mz_org_recruitment
    WHERE id = ?
    LIMIT 1
  ]], { id })
end

function MZOrgRepository.findPendingRecruitment(orgCode, targetCitizenId)
  return MySQL.single.await([[
    SELECT *
    FROM mz_org_recruitment
    WHERE org_code = ? AND target_citizenid = ? AND status = 'pending'
    ORDER BY id DESC
    LIMIT 1
  ]], { orgCode, targetCitizenId })
end

function MZOrgRepository.listRecruitment(filters)
  filters = type(filters) == 'table' and filters or {}
  local sql = 'SELECT * FROM mz_org_recruitment WHERE 1 = 1'
  local params = {}

  if filters.orgCode then
    sql = sql .. ' AND org_code = ?'
    params[#params + 1] = filters.orgCode
  end

  if filters.status then
    sql = sql .. ' AND status = ?'
    params[#params + 1] = filters.status
  end

  if filters.search then
    sql = sql .. ' AND (target_citizenid LIKE ? OR target_name LIKE ? OR note LIKE ?)'
    local like = '%' .. filters.search .. '%'
    params[#params + 1] = like
    params[#params + 1] = like
    params[#params + 1] = like
  end

  sql = sql .. ' ORDER BY created_at DESC LIMIT ? OFFSET ?'
  params[#params + 1] = tonumber(filters.limit) or 50
  params[#params + 1] = tonumber(filters.offset) or 0

  return MySQL.query.await(sql, params) or {}
end

function MZOrgRepository.updateRecruitmentStatus(id, status, data)
  data = type(data) == 'table' and data or {}

  MySQL.update.await([[
    UPDATE mz_org_recruitment
    SET status = ?,
        reviewed_by_citizenid = ?,
        reviewed_by_name = ?,
        reviewed_at = NOW(),
        decision_note = ?,
        metadata_json = ?,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = ?
  ]], {
    status,
    data.reviewed_by_citizenid,
    data.reviewed_by_name,
    data.decision_note,
    MZUtils.jsonEncode(data.metadata or {}),
    id
  })

  return MZOrgRepository.getRecruitmentById(id)
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
