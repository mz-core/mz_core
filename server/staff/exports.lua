exports('GetStaffContext', function(source)
  return MZStaffService.GetContext(source)
end)

exports('CanStaffActOnPlayer', function(actorSource, targetSource)
  return MZStaffService.CanActOnPlayer(actorSource, targetSource)
end)

exports('ListStaffManagement', function(source)
  return MZStaffService.ListManagement(source)
end)

exports('CreateStaffRole', function(source, payload)
  return MZStaffService.CreateRole(source, payload)
end)

exports('UpdateStaffRole', function(source, code, payload)
  return MZStaffService.UpdateRole(source, code, payload)
end)

exports('SetStaffRolePermissions', function(source, code, permissions, reason)
  return MZStaffService.SetRolePermissions(source, code, permissions, reason)
end)

exports('AssignStaffRole', function(source, citizenid, roleCode, reason)
  return MZStaffService.Assign(source, citizenid, roleCode, reason)
end)

exports('RevokeStaffRole', function(source, citizenid, reason)
  return MZStaffService.Revoke(source, citizenid, reason)
end)
