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

function MZStaffRepository.getAssignment(citizenid)
  return MySQL.single.await([[
    SELECT a.*, r.code AS role_code, r.name AS role_name, r.level AS role_level,
           r.active AS role_active, r.revision AS role_revision
    FROM mz_staff_assignments a
    INNER JOIN mz_staff_roles r ON r.id = a.role_id
    WHERE a.citizenid = ?
    LIMIT 1
  ]], { citizenid })
end

function MZStaffRepository.listAssignments()
  return MySQL.query.await([[
    SELECT a.*, r.code AS role_code, r.name AS role_name, r.level AS role_level,
           r.active AS role_active, p.firstname, p.lastname
    FROM mz_staff_assignments a
    INNER JOIN mz_staff_roles r ON r.id = a.role_id
    LEFT JOIN mz_players p ON p.citizenid = a.citizenid
    ORDER BY a.active DESC, r.level DESC, a.citizenid ASC
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
      citizenid, role_id, active, assigned_by_citizenid, reason, assigned_at, revoked_at
    ) VALUES (?, ?, 1, ?, ?, CURRENT_TIMESTAMP, NULL)
    ON DUPLICATE KEY UPDATE
      role_id = VALUES(role_id),
      active = 1,
      assigned_by_citizenid = VALUES(assigned_by_citizenid),
      reason = VALUES(reason),
      assigned_at = CURRENT_TIMESTAMP,
      revoked_at = NULL
  ]], { data.citizenid, data.role_id, data.actor_citizenid, data.reason })
end

function MZStaffRepository.revoke(citizenid, actorCitizenId, reason)
  return MySQL.update.await([[
    UPDATE mz_staff_assignments
    SET active = 0, assigned_by_citizenid = ?, reason = ?,
        revoked_at = CURRENT_TIMESTAMP
    WHERE citizenid = ? AND active = 1
  ]], { actorCitizenId, reason, citizenid })
end
