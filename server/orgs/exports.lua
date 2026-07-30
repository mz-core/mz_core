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

exports('GetStaffOrgInspection', function(source, orgCode)
  return MZOrgService.getStaffOrgInspection(source, orgCode)
end)

exports('ListLegacyStaffOrgPermissions', function(source)
  return MZOrgService.listLegacyStaffPermissions(source)
end)

exports('CreateStaffOrganization', function(source, payload)
  return MZOrgStaffMutationService.create(source, payload)
end)

exports('UpdateStaffOrganizationBasic', function(source, payload)
  return MZOrgStaffMutationService.updateBasic(source, payload)
end)

exports('ChangeStaffOrganizationType', function(source, payload)
  return MZOrgStaffMutationService.changeType(source, payload)
end)

exports('UpdateStaffOrganizationFeatures', function(source, payload)
  return MZOrgStaffMutationService.updateFeatures(source, payload)
end)

exports('UpdateStaffOrganizationAppearance', function(source, payload)
  return MZOrgStaffMutationService.updateAppearance(source, payload)
end)

exports('UpdateStaffOrganizationDutyPoint', function(source, payload)
  return MZOrgStaffMutationService.updateDutyPoint(source, payload)
end)

exports('ArchiveStaffOrganization', function(source, payload)
  return MZOrgStaffMutationService.archive(source, payload)
end)

exports('RestoreStaffOrganization', function(source, payload)
  return MZOrgStaffMutationService.restore(source, payload)
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

exports('CreateOrgRecruitment', function(source, orgCode, payload)
  return MZOrgService.createRecruitment(source, orgCode, payload)
end)

exports('ListOrgRecruitment', function(source, orgCode, filters)
  return MZOrgService.listRecruitment(source, orgCode, filters)
end)

exports('GetOrgRecruitment', function(source, recruitmentId)
  return MZOrgService.getRecruitment(source, recruitmentId)
end)

exports('ApproveOrgRecruitment', function(source, recruitmentId, options)
  return MZOrgService.approveRecruitment(source, recruitmentId, options)
end)

exports('RejectOrgRecruitment', function(source, recruitmentId, reason)
  return MZOrgService.rejectRecruitment(source, recruitmentId, reason)
end)

exports('CancelOrgRecruitment', function(source, recruitmentId, reason)
  return MZOrgService.cancelRecruitment(source, recruitmentId, reason)
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

exports('CreateOrgFromTemplate', function(source, payload)
  return MZOrgService.createOrgFromTemplate(source, payload)
end)

exports('UpdateOrgBasicInfo', function(source, orgCode, payload)
  return MZOrgService.updateOrgBasicInfo(source, orgCode, payload)
end)

exports('CreateOrgGrade', function(source, orgCode, payload)
  return MZOrgService.createOrgGrade(source, orgCode, payload)
end)

exports('UpdateOrgGradeBasic', function(source, orgCode, gradeId, payload)
  return MZOrgService.updateOrgGradeBasic(source, orgCode, gradeId, payload)
end)

exports('ArchiveOrg', function(source, orgCode, reason)
  return MZOrgService.archiveOrg(source, orgCode, reason)
end)

exports('ReactivateOrg', function(source, orgCode, reason)
  return MZOrgService.reactivateOrg(source, orgCode, reason)
end)

exports('DisableOrgGrade', function(source, orgCode, gradeId, reason)
  return MZOrgService.disableOrgGrade(source, orgCode, gradeId, reason)
end)

exports('ReactivateOrgGrade', function(source, orgCode, gradeId, reason)
  return MZOrgService.reactivateOrgGrade(source, orgCode, gradeId, reason)
end)

exports('AddOrgGradePermission', function(source, orgCode, gradeId, permission, reason)
  return MZOrgService.addOrgGradePermission(source, orgCode, gradeId, permission, reason)
end)

exports('RemoveOrgGradePermission', function(source, orgCode, gradeId, permission, reason)
  return MZOrgService.removeOrgGradePermission(source, orgCode, gradeId, permission, reason)
end)

exports('CreateOrganizationGrade', function(source, orgCode, payload)
  return MZOrgService.createOrganizationGrade(source, orgCode, payload)
end)

exports('UpdateOrganizationGradeBasic', function(source, orgCode, gradeId, payload)
  return MZOrgService.updateOrganizationGradeBasic(source, orgCode, gradeId, payload)
end)

exports('DisableOrganizationGrade', function(source, orgCode, gradeId, reason)
  return MZOrgService.disableOrganizationGrade(source, orgCode, gradeId, reason)
end)

exports('ReactivateOrganizationGrade', function(source, orgCode, gradeId, reason)
  return MZOrgService.reactivateOrganizationGrade(source, orgCode, gradeId, reason)
end)

exports('AddOrganizationGradePermission', function(source, orgCode, gradeId, permission, reason)
  return MZOrgService.addOrganizationGradePermission(source, orgCode, gradeId, permission, reason)
end)

exports('RemoveOrganizationGradePermission', function(source, orgCode, gradeId, permission, reason)
  return MZOrgService.removeOrganizationGradePermission(source, orgCode, gradeId, permission, reason)
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

exports('InviteOrgMemberByCitizenId', function(source, orgCode, targetCitizenId, options)
  return MZOrgService.inviteOrgMemberByCitizenId(source, orgCode, targetCitizenId, options)
end)

exports('RemoveMemberFromOrg', function(citizenid, orgCode, actor)
  return MZOrgService.removeMember(citizenid, orgCode, actor)
end)

exports('RemoveOrgMember', function(source, orgCode, targetCitizenId, options)
  return MZOrgService.removeOrgMemberSecure(source, orgCode, targetCitizenId, options)
end)

exports('PromoteOrgMemberSecure', function(source, orgCode, targetCitizenId, options)
  return MZOrgService.promoteOrgMemberSecure(source, orgCode, targetCitizenId, options)
end)

exports('DemoteOrgMemberSecure', function(source, orgCode, targetCitizenId, options)
  return MZOrgService.demoteOrgMemberSecure(source, orgCode, targetCitizenId, options)
end)

exports('SetOrgMemberPrimary', function(citizenid, orgCode, actor)
  return MZOrgService.setPrimary(citizenid, orgCode, actor)
end)

exports('SetOrgMemberDuty', function(citizenid, orgCode, duty, actor)
  return MZOrgService.setDuty(citizenid, orgCode, duty, actor)
end)

exports('SetSelfOrgDutyAtPoint', function(source, orgCode, duty)
  return MZOrgService.setSelfDutyAtPoint(source, orgCode, duty)
end)

exports('SetOrgMemberGrade', function(citizenid, orgCode, gradeLevel, actor)
  return MZOrgService.setGrade(citizenid, orgCode, gradeLevel, actor)
end)

exports('SetOrgLeaderByCitizenId', function(source, orgCode, targetCitizenId, options)
  return MZOrgService.setLeaderByCitizenId(source, orgCode, targetCitizenId, options)
end)

exports('TransferOrganizationLeadership', function(source, orgCode, targetCitizenId, options)
  return MZOrgService.transferOrganizationLeadership(source, orgCode, targetCitizenId, options)
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
