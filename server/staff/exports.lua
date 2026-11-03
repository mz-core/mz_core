exports('GetStaffContext', function(source)
  return MZStaffService.GetContext(source)
end)

exports('HasGlobalPermission', function(source, permission)
  return MZStaffService.HasGlobalPermission(source, permission)
end)

exports('CanStaffActOnPlayer', function(actorSource, targetSource)
  return MZStaffService.CanActOnPlayer(actorSource, targetSource)
end)

local function managementCallerAllowed()
  return GetInvokingResource() == 'mz_admin'
end

exports('ListStaffManagement', function(source)
  if not managementCallerAllowed() then return false, { code = 'not_authorized' } end
  return MZStaffService.ListManagement(source)
end)

exports('CreateStaffRole', function(source, payload)
  if not managementCallerAllowed() then return false, { code = 'not_authorized' } end
  return MZStaffService.CreateRole(source, payload)
end)

exports('UpdateStaffRole', function(source, code, payload)
  if not managementCallerAllowed() then return false, { code = 'not_authorized' } end
  return MZStaffService.UpdateRole(source, code, payload)
end)

exports('SetStaffRolePermissions', function(source, code, permissions, reason)
  if not managementCallerAllowed() then return false, { code = 'not_authorized' } end
  return MZStaffService.SetRolePermissions(source, code, permissions, reason)
end)

exports('AssignStaffRole', function(source, accountId, roleCode, reason)
  if not managementCallerAllowed() then return false, { code = 'not_authorized' } end
  return MZStaffService.Assign(source, accountId, roleCode, reason)
end)

exports('RevokeStaffRole', function(source, accountId, reason)
  if not managementCallerAllowed() then return false, { code = 'not_authorized' } end
  return MZStaffService.Revoke(source, accountId, reason)
end)
