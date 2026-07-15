MZAccountRepository = {}

function MZAccountRepository.getPlayerAccount(citizenid)
  return MySQL.single.await('SELECT * FROM mz_player_accounts WHERE citizenid = ? LIMIT 1', { citizenid })
end

function MZAccountRepository.updatePlayerMoney(citizenid, moneyType, amount)
  local allowed = { wallet = true, bank = true, dirty = true }
  if not allowed[moneyType] then return false end

  local affected = MySQL.update.await(([[UPDATE mz_player_accounts SET %s = ? WHERE citizenid = ?]]):format(moneyType), {
    amount,
    citizenid
  })

  return affected ~= nil
end

function MZAccountRepository.transferPlayerMoney(citizenid, fromAccount, toAccount, fromAmount, toAmount)
  local allowed = { wallet = true, bank = true, dirty = true }
  if not allowed[fromAccount] or not allowed[toAccount] or fromAccount == toAccount then
    return false
  end

  local affected = MySQL.update.await(([[
    UPDATE mz_player_accounts
    SET %s = ?, %s = ?
    WHERE citizenid = ?
  ]]):format(fromAccount, toAccount), {
    fromAmount,
    toAmount,
    citizenid
  })

  return tonumber(affected) == 1
end

function MZAccountRepository.transferBankBetweenPlayers(senderCitizenId, senderAmount, targetCitizenId, targetAmount)
  local ok = MySQL.transaction.await({
    {
      query = 'UPDATE mz_player_accounts SET bank = ? WHERE citizenid = ?',
      parameters = { senderAmount, senderCitizenId }
    },
    {
      query = 'UPDATE mz_player_accounts SET bank = ? WHERE citizenid = ?',
      parameters = { targetAmount, targetCitizenId }
    }
  })

  return ok == true
end
