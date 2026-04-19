exports('GetMoney', function(source)
  return MZAccountService.getMoney(source)
end)

exports('SetMoney', function(source, moneyType, amount)
  return MZAccountService.setMoney(source, moneyType, amount)
end)

exports('AddMoney', function(source, moneyType, amount)
  return MZAccountService.addMoney(source, moneyType, amount)
end)

exports('RemoveMoney', function(source, moneyType, amount)
  return MZAccountService.removeMoney(source, moneyType, amount)
end)
