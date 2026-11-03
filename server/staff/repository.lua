MZStaffRepository = MZStaffRepository or {}

function MZStaffRepository.getRoleByCode(code)
  return MySQL.single.await('SELECT * FROM mz_staff_roles WHERE code = ? LIMIT 1', { code })
end

function MZStaffRepository.getRoleById(id)
  return MySQL.single.await('SELECT * FROM mz_staff_roles WHERE id = ? LIMIT 1', { id })
end

function MZStaffRepository.getRoleByLevel(level)
  return MySQL.single.await('SELECT * FROM mz_staff_roles WHERE level = ? LIMIT 1', { level })
end

function MZStaffRepository.listRoles()
  return MySQL.query.await('SELECT * FROM mz_staff_roles ORDER BY level DESC, name ASC') or {}
end

function MZStaffRepository.getRolePermissions(roleId)
  return MySQL.query.await([[
    SELECT permission, allow
    FROM mz_staff_role_permissions
    WHERE role_id = ? AND allow = 1
    ORDER BY permission ASC
  ]], { roleId }) or {}
end

function MZStaffRepository.getAssignment(accountId)
  return MySQL.single.await([[
    SELECT a.*, r.code AS role_code, r.name AS role_name, r.level AS role_level,
           r.active AS role_active, r.revision AS role_revision
    FROM mz_staff_assignments a
    INNER JOIN mz_staff_roles r ON r.id = a.role_id
    WHERE a.account_id = ?
    LIMIT 1
  ]], { accountId })
end

function MZStaffRepository.listAssignments()
  return MySQL.query.await([[
    SELECT a.*, r.code AS role_code, r.name AS role_name, r.level AS role_level,
           r.active AS role_active, p.firstname, p.lastname
    FROM mz_staff_assignments a
    INNER JOIN mz_staff_roles r ON r.id = a.role_id
    LEFT JOIN mz_players p ON p.id = a.context_character_id
    ORDER BY a.active DESC, r.level DESC, a.account_id ASC
  ]]) or {}
end

function MZStaffRepository.countActiveAssignments(roleId)
  local row = MySQL.single.await(
    'SELECT COUNT(1) AS total FROM mz_staff_assignments WHERE role_id = ? AND active = 1',
    { roleId }
  )
  return tonumber(row and row.total) or 0
end

function MZStaffRepository.createRole(data)
  return MySQL.insert.await([[
    INSERT INTO mz_staff_roles (code, name, level, active, created_by_citizenid)
    VALUES (?, ?, ?, 1, ?)
  ]], { data.code, data.name, data.level, data.actor_citizenid })
end

function MZStaffRepository.createSeedRole(data)
  local statements = {
    {
      query = [[
        INSERT INTO mz_staff_roles (code, name, level, active, created_by_citizenid)
        VALUES (?, ?, ?, 1, 'system:staff_seed')
      ]],
      parameters = { data.code, data.name, data.level }
    }
  }

  for _, permission in ipairs(data.permissions or {}) do
    statements[#statements + 1] = {
      query = [[
        INSERT INTO mz_staff_role_permissions (role_id, permission, allow)
        SELECT id, ?, 1
        FROM mz_staff_roles
        WHERE code = ? AND created_by_citizenid = 'system:staff_seed'
      ]],
      parameters = { permission, data.code }
    }
  end

  return MySQL.transaction.await(statements) == true
end

function MZStaffRepository.updateRole(roleId, data)
  return MySQL.update.await([[
    UPDATE mz_staff_roles
    SET name = ?, level = ?, active = ?, revision = revision + 1
    WHERE id = ?
  ]], { data.name, data.level, data.active and 1 or 0, roleId })
end

function MZStaffRepository.setRolePermissions(roleId, selected)
  for permission in pairs(MZStaffPermissionSet or {}) do
    MySQL.insert.await([[
      INSERT INTO mz_staff_role_permissions (role_id, permission, allow)
      VALUES (?, ?, ?)
      ON DUPLICATE KEY UPDATE allow = VALUES(allow)
    ]], { roleId, permission, selected[permission] == true and 1 or 0 })
  end
  MySQL.update.await('UPDATE mz_staff_roles SET revision = revision + 1 WHERE id = ?', { roleId })
end

function MZStaffRepository.assign(data)
  MySQL.insert.await([[
    INSERT INTO mz_staff_assignments (
      account_id, context_character_id, role_id, active,
      assigned_by_account_id, assigned_by_character_id, reason, assigned_at, revoked_at
    ) VALUES (?, ?, ?, 1, ?, ?, ?, CURRENT_TIMESTAMP, NULL)
    ON DUPLICATE KEY UPDATE
      role_id = VALUES(role_id),
      active = 1,
      context_character_id = VALUES(context_character_id),
      assigned_by_account_id = VALUES(assigned_by_account_id),
      assigned_by_character_id = VALUES(assigned_by_character_id),
      reason = VALUES(reason),
      assigned_at = CURRENT_TIMESTAMP,
      revoked_at = NULL
  ]], {
    data.account_id, data.context_character_id, data.role_id,
    data.actor_account_id, data.actor_character_id, data.reason
  })
end

function MZStaffRepository.revoke(accountId, actorAccountId, actorCharacterId, reason)
  return MySQL.update.await([[
    UPDATE mz_staff_assignments
    SET active = 0, assigned_by_account_id = ?, assigned_by_character_id = ?, reason = ?,
        revoked_at = CURRENT_TIMESTAMP
    WHERE account_id = ? AND active = 1
  ]], { actorAccountId, actorCharacterId, reason, accountId })
end
