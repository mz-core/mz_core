exports('ListLogs', function(source, filters)
  return MZLogService.listLogs(source, filters)
end)

exports('ListOrganizationLogs', function(orgCode, filters)
  if GetInvokingResource() ~= 'mz_org' then return false, 'forbidden_caller' end
  return MZLogService.listOrganizationLogs(orgCode, filters)
end)

exports('ListGlobalLogsSecure', function(source, filters)
  return MZLogService.listGlobalLogsSecure(source, filters)
end)

exports('CreateDetailedLog', function(scope, action, payload)
  return MZLogService.createDetailed(scope, action, payload)
end)
