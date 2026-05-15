exports('ListLogs', function(source, filters)
  return MZLogService.listLogs(source, filters)
end)
