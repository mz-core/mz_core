-- Phase 0 staging probe. This file exposes no event or command and is inert unless
-- the explicit staging convars are enabled. It can only mutate isolated mztest_ fixtures.

local function convarEnabled(name)
  return GetConvarInt(name, 0) == 1
end

local function isStagingEnabled()
  local backupReference = tostring(GetConvar('mz_org_phase0_backup_confirmed', ''))
  return convarEnabled('mz_org_phase0_runtime_runner')
    and tostring(GetConvar('mz_org_phase0_environment', '')):lower() == 'staging'
    and backupReference ~= ''
    and backupReference ~= '0'
end

local function startsWith(value, prefix)
  value = type(value) == 'string' and value or ''
  return value:sub(1, #prefix) == prefix
end

exports('Phase0RuntimeAuditProbe', function(payload)
  if type(GetInvokingResource) == 'function' and GetInvokingResource() ~= 'mz_org' then
    return false, 'runtime_probe_caller_forbidden'
  end
  if not isStagingEnabled() then return false, 'runtime_probe_disabled' end
  payload = type(payload) == 'table' and payload or {}

  local citizenid = tostring(payload.citizenid or '')
  local orgCode = tostring(payload.orgCode or payload.org_code or '')
  local auditId = tostring(payload.auditId or payload.audit_id or '')
  local action = tostring(payload.action or '')
  local orgId = tonumber(payload.orgId or payload.org_id)
  local gradeId = tonumber(payload.gradeId or payload.grade_id)

  if not startsWith(citizenid, 'mztest_')
    or not startsWith(orgCode, 'mztest_')
    or not startsWith(auditId, 'mztest_phase0_')
    or not action:match('^phase0%.runtime%.')
    or not orgId
    or not gradeId then
    return false, 'fixture_scope_required'
  end

  local fixture = MySQL.single.await([[
    SELECT o.id AS org_id, o.code AS org_code, g.id AS grade_id, po.id AS membership_id
    FROM mz_orgs o
    JOIN mz_org_grades g ON g.org_id = o.id AND g.id = ?
    JOIN mz_player_orgs po ON po.org_id = o.id AND po.citizenid = ? AND po.active = 1
    WHERE o.id = ? AND o.code = ?
    LIMIT 1
  ]], { gradeId, citizenid, orgId, orgCode })
  if not fixture then return false, 'fixture_not_found' end

  local committed = MZOrgRepository.updateMembershipGradeWithAudit({
    citizenid = citizenid,
    org_id = orgId,
    grade_id = gradeId,
    scope = 'orgs',
    action = action,
    actor = 'phase0-runtime-runner',
    target = citizenid,
    org_code = orgCode,
    audit_id = auditId,
    data_json = json.encode({
      actor = { type = 'runtime_runner', id = 'console' },
      target = { type = 'player', citizenid = citizenid },
      context = { org_id = orgId, org_code = orgCode },
      meta = { audit_id = auditId, runtime_fixture = true }
    })
  })

  if committed ~= true then return false, 'audit_transaction_failed' end
  return true, { auditId = auditId, orgCode = orgCode, gradeId = gradeId }
end)
