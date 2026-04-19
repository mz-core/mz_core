MZAccountRepository = {}

function MZAccountRepository.getPlayerAccount(citizenid)
  return MySQL.single.await('SELECT * FROM mz_player_accounts WHERE citizenid = ? LIMIT 1', { citizenid })
end

function MZAccountRepository.updatePlayerMoney(citizenid, moneyType, amount)
  local allowed = { wallet = true, bank = true, dirty = true }
  if not allowed[moneyType] then return false end

  MySQL.update.await(([[UPDATE mz_player_accounts SET %s = ? WHERE citizenid = ?]]):format(moneyType), {
    amount,
    citizenid
  })

  return true
end
