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

function MZAccountRepository.getOrgAccountOperation(sourceResource, operationKey)
  return MySQL.single.await([[
    SELECT *
    FROM mz_org_account_operations
    WHERE source_resource = ? AND operation_key = ?
    LIMIT 1
  ]], { sourceResource, operationKey })
end

function MZAccountRepository.getOrgAccountOperationByReceipt(receiptId)
  return MySQL.single.await([[
    SELECT *
    FROM mz_org_account_operations
    WHERE receipt_id = ?
    LIMIT 1
  ]], { receiptId })
end

function MZAccountRepository.getOrgAccountReversal(operationId)
  return MySQL.single.await([[
    SELECT *
    FROM mz_org_account_operations
    WHERE reversal_of_operation_id = ?
    LIMIT 1
  ]], { operationId })
end

function MZAccountRepository.createOrgAccountOperation(data)
  if type(data) ~= 'table' then return nil end

  return MySQL.insert.await([[
    INSERT INTO mz_org_account_operations (
      source_resource, operation_key, operation_type, purpose,
      org_id, org_code, actor_citizenid, amount, related_ref,
      request_fingerprint, status, error_code, reversal_of_operation_id,
      metadata_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    data.sourceResource,
    data.operationKey,
    data.operationType,
    data.purpose,
    data.orgId,
    data.orgCode,
    data.actorCitizenId,
    data.amount,
    data.relatedRef,
    data.fingerprint,
    data.status or 'pending',
    data.errorCode,
    data.reversalOfOperationId,
    data.metadataJson
  })
end

function MZAccountRepository.rejectOrgAccountOperation(operationId, errorCode)
  local affected = MySQL.update.await([[
    UPDATE mz_org_account_operations
    SET status = 'rejected', error_code = ?
    WHERE id = ? AND status = 'pending'
  ]], { errorCode, operationId })
  return tonumber(affected) == 1
end

-- O saldo, o recibo, o extrato e o outbox financeiro sao confirmados na
-- mesma transacao. A operacao precisa estar pendente e o saldo observado
-- precisa continuar igual ao informado pelo servico protegido pelo lock.
function MZAccountRepository.applyOrgAccountOperation(data, outbox)
  if type(data) ~= 'table' then return false end

  local statements = {
    {
      query = [[
        UPDATE mz_org_accounts org_account
        INNER JOIN mz_org_account_operations account_operation
          ON account_operation.org_id = org_account.org_id
        SET org_account.balance = ?,
            account_operation.status = 'applied',
            account_operation.error_code = NULL,
            account_operation.balance_before = ?,
            account_operation.balance_after = ?,
            account_operation.receipt_id = ?,
            account_operation.correlation_id = ?
        WHERE account_operation.id = ?
          AND account_operation.status = 'pending'
          AND org_account.balance = ?
      ]],
      parameters = {
        data.balanceAfter,
        data.balanceBefore,
        data.balanceAfter,
        data.receiptId,
        data.correlationId,
        data.operationId,
        data.balanceBefore
      }
    },
    {
      query = [[
        INSERT INTO mz_org_account_transactions (
          org_id, org_code, type, amount, balance_before, balance_after,
          actor_citizenid, actor_name, reason, metadata_json, operation_id
        )
        SELECT
          account_operation.org_id, account_operation.org_code, account_operation.operation_type,
          account_operation.amount, account_operation.balance_before, account_operation.balance_after,
          account_operation.actor_citizenid, ?, ?, account_operation.metadata_json, account_operation.id
        FROM mz_org_account_operations account_operation
        WHERE account_operation.id = ? AND account_operation.status = 'applied'
        ON DUPLICATE KEY UPDATE operation_id = VALUES(operation_id)
      ]],
      parameters = {
        data.actorName,
        data.reason,
        data.operationId
      }
    }
  }

  if type(outbox) == 'table' then
    statements[#statements + 1] = {
      query = [[
        INSERT INTO mz_financial_outbox (
          correlation_id, idempotency_key, event_type,
          source_citizenid, target_citizenid, account, amount, fee,
          reason, source_resource, source_channel, payload_version, metadata_json
        )
        SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
        FROM mz_org_account_operations account_operation
        WHERE account_operation.id = ? AND account_operation.status = 'applied'
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
        outbox.metadataJson,
        data.operationId
      }
    }
  end

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
