exports('GetPlayerOrgs', function(source)
  return MZOrgService.getPlayerOrgs(source)
end)

exports('HasPermission', function(source, permission)
  return MZOrgService.hasPermission(source, permission)
end)

exports('HasGlobalPermission', function(source, permission)
  return MZOrgService.hasGlobalPermission(source, permission)
end)

exports('CanOrg', function(source, orgCode, capability)
  return MZOrgService.canOrg(source, orgCode, capability)
end)

exports('GetPlayerOrgContext', function(source)
  return MZOrgService.getPlayerOrgContext(source)
end)

exports('ListOrgMembers', function(source, orgCode)
  return MZOrgService.listOrgMembers(source, orgCode)
end)

exports('GetOrgAccessModel', function(source, orgCode)
  return MZOrgService.getOrgAccessModel(source, orgCode)
end)

exports('ListOrgGoals', function(source, filters)
  return MZOrgService.listOrgGoals(source, filters)
end)

exports('GetOrgGoal', function(source, goalId)
  return MZOrgService.getOrgGoal(source, goalId)
end)

exports('CreateOrgGoal', function(source, orgCode, payload)
  return MZOrgService.createOrgGoal(source, orgCode, payload)
end)

exports('HasGradeOrAbove', function(source, orgCode, minLevel)
  return MZOrgService.hasGradeOrAbove(source, orgCode, minLevel)
end)

exports('GetOrgByCode', function(orgCode)
  return MZOrgService.getOrgByCode(orgCode)
end)

exports('ListOrgs', function(orgTypeCode)
  return MZOrgService.listOrgs(orgTypeCode)
end)

exports('CreateOrg', function(data, actor)
  return MZOrgService.createOrg(data, actor)
end)

exports('CreateGrade', function(orgCode, data, actor)
  return MZOrgService.createGrade(orgCode, data, actor)
end)

exports('SetOrgPermission', function(orgCode, permission, allow, actor)
  return MZOrgService.setOrgPermission(orgCode, permission, allow, actor)
end)

exports('SetGradePermission', function(orgCode, gradeLevel, permission, allow, actor)
  return MZOrgService.setGradePermission(orgCode, gradeLevel, permission, allow, actor)
end)

exports('AddMemberToOrg', function(citizenid, orgCode, gradeLevel, options, actor)
  return MZOrgService.addMember(citizenid, orgCode, gradeLevel, options, actor)
end)

exports('InviteOrgMember', function(source, orgCode, targetSource, options)
  return MZOrgService.inviteOrgMember(source, orgCode, targetSource, options)
end)

exports('RemoveMemberFromOrg', function(citizenid, orgCode, actor)
  return MZOrgService.removeMember(citizenid, orgCode, actor)
end)

exports('RemoveOrgMember', function(source, orgCode, targetCitizenId)
  return MZOrgService.removeOrgMemberSecure(source, orgCode, targetCitizenId)
end)

exports('PromoteOrgMemberSecure', function(source, orgCode, targetCitizenId)
  return MZOrgService.promoteOrgMemberSecure(source, orgCode, targetCitizenId)
end)

exports('DemoteOrgMemberSecure', function(source, orgCode, targetCitizenId)
  return MZOrgService.demoteOrgMemberSecure(source, orgCode, targetCitizenId)
end)

exports('SetOrgMemberPrimary', function(citizenid, orgCode, actor)
  return MZOrgService.setPrimary(citizenid, orgCode, actor)
end)

exports('SetOrgMemberDuty', function(citizenid, orgCode, duty, actor)
  return MZOrgService.setDuty(citizenid, orgCode, duty, actor)
end)

exports('SetOrgMemberGrade', function(citizenid, orgCode, gradeLevel, actor)
  return MZOrgService.setGrade(citizenid, orgCode, gradeLevel, actor)
end)

exports('PromoteOrgMember', function(citizenid, orgCode, actor)
  return MZOrgService.promote(citizenid, orgCode, actor)
end)

exports('DemoteOrgMember', function(citizenid, orgCode, actor)
  return MZOrgService.demote(citizenid, orgCode, actor)
end)

exports('SetPlayerPermission', function(citizenid, permission, allow, expiresAt, actor)
  return MZOrgService.setPlayerPermission(citizenid, permission, allow, expiresAt, actor)
end)

exports('RemovePlayerPermission', function(citizenid, permission, actor)
  return MZOrgService.removePlayerPermission(citizenid, permission, actor)
end)
