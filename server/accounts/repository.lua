MZAccountRepository = {}

local appendFinancialOutboxStatement

function MZAccountRepository.getPlayerAccount(citizenid)
  return MySQL.single.await('SELECT * FROM mz_player_accounts WHERE citizenid = ? LIMIT 1', { citizenid })
end

function MZAccountRepository.getIdempotentOperation(sourceResource, actorCitizenId, idempotencyKey)
  return MySQL.single.await([[
    SELECT operation, request_fingerprint, correlation_id, result_json, created_at
    FROM mz_account_idempotency
    WHERE source_resource = ? AND actor_citizenid = ? AND idempotency_key = ?
    LIMIT 1
  ]], { sourceResource, actorCitizenId, idempotencyKey })
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

function MZAccountRepository.updatePlayerMoneyWithOutbox(citizenid, moneyType, amount, outbox)
  local allowed = { wallet = true, bank = true, dirty = true }
  if not allowed[moneyType] then return false end

  local statements = {
    {
      query = (([[
        UPDATE mz_player_accounts
        SET %s = ?
        WHERE citizenid = ?
      ]])):format(moneyType),
      parameters = { amount, citizenid }
    }
  }

  appendFinancialOutboxStatement(statements, outbox)
  return MySQL.transaction.await(statements) == true
end

function MZAccountRepository.updatePlayerMoneyIdempotent(
  citizenid,
  moneyType,
  amount,
  idempotency,
  outbox
)
  local allowed = { wallet = true, bank = true, dirty = true }
  if not allowed[moneyType] or type(idempotency) ~= 'table' then return false end

  local statements = {
    {
      query = [[
        INSERT INTO mz_account_idempotency (
          source_resource, actor_citizenid, idempotency_key, operation,
          request_fingerprint, correlation_id, result_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ]],
      parameters = {
        idempotency.sourceResource,
        idempotency.actorCitizenId,
        idempotency.key,
        idempotency.operation,
        idempotency.fingerprint,
        idempotency.correlationId,
        idempotency.resultJson
      }
    },
    {
      query = (([[
        UPDATE mz_player_accounts
        SET %s = ?
        WHERE citizenid = ?
      ]])):format(moneyType),
      parameters = { amount, citizenid }
    }
  }

  appendFinancialOutboxStatement(statements, outbox)
  return MySQL.transaction.await(statements) == true
end

function MZAccountRepository.updateOrgMoneyWithOutbox(orgId, amount, outbox)
  local statements = {
    {
      query = 'UPDATE mz_org_accounts SET balance = ? WHERE org_id = ?',
      parameters = { amount, orgId }
    }
  }

  appendFinancialOutboxStatement(statements, outbox)
  return MySQL.transaction.await(statements) == true
end

function MZAccountRepository.transferPlayerBankAndOrg(
  citizenid,
  playerBankAmount,
  orgId,
  orgBalanceAmount,
  outbox,
  idempotency
)
  local statements = {}
  if type(idempotency) == 'table' then
    statements[#statements + 1] = {
      query = [[
        INSERT INTO mz_account_idempotency (
          source_resource, actor_citizenid, idempotency_key, operation,
          request_fingerprint, correlation_id, result_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ]],
      parameters = {
        idempotency.sourceResource,
        idempotency.actorCitizenId,
        idempotency.key,
        idempotency.operation,
        idempotency.fingerprint,
        idempotency.correlationId,
        idempotency.resultJson
      }
    }
  end

  statements[#statements + 1] = {
      query = 'UPDATE mz_player_accounts SET bank = ? WHERE citizenid = ?',
      parameters = { playerBankAmount, citizenid }
    }
  statements[#statements + 1] = {
      query = 'UPDATE mz_org_accounts SET balance = ? WHERE org_id = ?',
      parameters = { orgBalanceAmount, orgId }
    }

  appendFinancialOutboxStatement(statements, outbox)
  return MySQL.transaction.await(statements) == true
end

appendFinancialOutboxStatement = function(statements, outbox)
  if type(outbox) ~= 'table' then return statements end

  statements[#statements + 1] = {
    query = [[
      INSERT INTO mz_financial_outbox (
        correlation_id, idempotency_key, event_type,
        source_citizenid, target_citizenid, account, amount, fee,
        reason, source_resource, source_channel, payload_version, metadata_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]],
    parameters = {
      outbox.correlationId,
      outbox.idempotencyKey,
      outbox.eventType,
      outbox.sourceCitizenId,
      outbox.targetCitizenId,
      outbox.account,
      outbox.amount,
      outbox.fee,
      outbox.reason,
      outbox.sourceResource,
      outbox.sourceChannel,
      outbox.payloadVersion,
      outbox.metadataJson
    }
  }

  return statements
end

function MZAccountRepository.transferPlayerMoney(
  citizenid,
  fromAccount,
  toAccount,
  fromAmount,
  toAmount,
  outbox
)
  local allowed = { wallet = true, bank = true, dirty = true }
  if not allowed[fromAccount] or not allowed[toAccount] or fromAccount == toAccount then
    return false
  end

  local updateQuery = ([[
    UPDATE mz_player_accounts
    SET %s = ?, %s = ?
    WHERE citizenid = ?
  ]]):format(fromAccount, toAccount)

  if type(outbox) == 'table' then
    local statements = {
      {
        query = updateQuery,
        parameters = { fromAmount, toAmount, citizenid }
      }
    }
    appendFinancialOutboxStatement(statements, outbox)
    return MySQL.transaction.await(statements) == true
  end

  local affected = MySQL.update.await(updateQuery, { fromAmount, toAmount, citizenid })

  return tonumber(affected) == 1
end

function MZAccountRepository.transferPlayerMoneyIdempotent(
  citizenid,
  fromAccount,
  toAccount,
  fromAmount,
  toAmount,
  idempotency,
  outbox
)
  local allowed = { wallet = true, bank = true, dirty = true }
  if not allowed[fromAccount] or not allowed[toAccount] or fromAccount == toAccount then
    return false
  end

  local statements = {
    {
      query = [[
        INSERT INTO mz_account_idempotency (
          source_resource, actor_citizenid, idempotency_key, operation,
          request_fingerprint, correlation_id, result_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ]],
      parameters = {
        idempotency.sourceResource,
        idempotency.actorCitizenId,
        idempotency.key,
        idempotency.operation,
        idempotency.fingerprint,
        idempotency.correlationId,
        idempotency.resultJson
      }
    },
    {
      query = ([[
        UPDATE mz_player_accounts
        SET %s = ?, %s = ?
        WHERE citizenid = ?
      ]]):format(fromAccount, toAccount),
      parameters = { fromAmount, toAmount, citizenid }
    }
  }
  appendFinancialOutboxStatement(statements, outbox)
  return MySQL.transaction.await(statements) == true
end

function MZAccountRepository.transferBankBetweenPlayers(
  senderCitizenId,
  senderAmount,
  targetCitizenId,
  targetAmount,
  outbox
)
  local statements = {
    {
      query = 'UPDATE mz_player_accounts SET bank = ? WHERE citizenid = ?',
      parameters = { senderAmount, senderCitizenId }
    },
    {
      query = 'UPDATE mz_player_accounts SET bank = ? WHERE citizenid = ?',
      parameters = { targetAmount, targetCitizenId }
    }
  }
  appendFinancialOutboxStatement(statements, outbox)
  local ok = MySQL.transaction.await(statements)

  return ok == true
end

function MZAccountRepository.transferBankBetweenPlayersIdempotent(
  senderCitizenId,
  senderAmount,
  targetCitizenId,
  targetAmount,
  idempotency,
  outbox
)
  local statements = {
    {
      query = [[
        INSERT INTO mz_account_idempotency (
          source_resource, actor_citizenid, idempotency_key, operation,
          request_fingerprint, correlation_id, result_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ]],
      parameters = {
        idempotency.sourceResource,
        idempotency.actorCitizenId,
        idempotency.key,
        idempotency.operation,
        idempotency.fingerprint,
        idempotency.correlationId,
        idempotency.resultJson
      }
    },
    {
      query = 'UPDATE mz_player_accounts SET bank = ? WHERE citizenid = ?',
      parameters = { senderAmount, senderCitizenId }
    },
    {
      query = 'UPDATE mz_player_accounts SET bank = ? WHERE citizenid = ?',
      parameters = { targetAmount, targetCitizenId }
    }
  }
  appendFinancialOutboxStatement(statements, outbox)
  return MySQL.transaction.await(statements) == true
end
