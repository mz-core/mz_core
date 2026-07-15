exports('ListLogs', function(source, filters)
  return MZLogService.listLogs(source, filters)
end)

exports('CreateDetailedLog', function(scope, action, payload)
  return MZLogService.createDetailed(scope, action, payload)
end)
