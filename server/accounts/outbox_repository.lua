-- Ownership do mz_core: persistencia do dispatcher da outbox financeira.

MZFinancialOutboxRepository = MZFinancialOutboxRepository or {}

local EVENT_COLUMNS = [[
  id, correlation_id, event_type, source_citizenid, target_citizenid,
  account, amount, fee, reason, source_resource, source_channel,
  payload_version, metadata_json, status, attempts, next_retry_at,
  claim_token, claimed_at, lease_expires_at, created_at
]]

function MZFinancialOutboxRepository.newClaimToken()
  local row = MySQL.single.await([[SELECT LOWER(REPLACE(UUID(), '-', '')) AS claim_token]])
  local token = row and tostring(row.claim_token or '') or ''
  if not token:match('^[0-9a-f]+$') or #token ~= 32 then return nil end
  return token
end

function MZFinancialOutboxRepository.recoverExpiredLeases()
  local affected = MySQL.update.await([[
    UPDATE mz_financial_outbox
    SET status = 'pending',
        claim_token = NULL,
        claimed_at = NULL,
        lease_expires_at = NULL,
        next_retry_at = CURRENT_TIMESTAMP,
        last_error = 'lease_expired'
    WHERE status = 'processing'
      AND lease_expires_at IS NOT NULL
      AND lease_expires_at <= CURRENT_TIMESTAMP
  ]])
  return tonumber(affected) or 0
end

function MZFinancialOutboxRepository.claimEligible(token, batchSize, leaseSeconds)
  batchSize = math.max(1, math.min(100, math.floor(tonumber(batchSize) or 1)))
  leaseSeconds = math.max(5, math.min(3600, math.floor(tonumber(leaseSeconds) or 30)))

  local query = ([=[
    UPDATE mz_financial_outbox
    SET status = 'processing',
        attempts = attempts + 1,
        claim_token = ?,
        claimed_at = CURRENT_TIMESTAMP,
        lease_expires_at = TIMESTAMPADD(SECOND, %d, CURRENT_TIMESTAMP),
        last_error = NULL
    WHERE status = 'pending'
      AND next_retry_at <= CURRENT_TIMESTAMP
    ORDER BY id ASC
    LIMIT %d
  ]=]):format(leaseSeconds, batchSize)

  local affected = MySQL.update.await(query, { token })
  return tonumber(affected) or 0
end

function MZFinancialOutboxRepository.getClaimed(token)
  return MySQL.query.await(([[
    SELECT %s
    FROM mz_financial_outbox
    WHERE status = 'processing' AND claim_token = ?
    ORDER BY id ASC
  ]]):format(EVENT_COLUMNS), { token }) or {}
end

function MZFinancialOutboxRepository.acknowledge(id, token)
  local affected = MySQL.update.await([[
    UPDATE mz_financial_outbox
    SET status = 'processed',
        processed_at = CURRENT_TIMESTAMP,
        claim_token = NULL,
        claimed_at = NULL,
        lease_expires_at = NULL,
        last_error = NULL
    WHERE id = ? AND status = 'processing' AND claim_token = ?
  ]], { id, token })
  return tonumber(affected) == 1
end

function MZFinancialOutboxRepository.reschedule(id, token, delaySeconds, errorCode)
  delaySeconds = math.max(1, math.min(86400, math.floor(tonumber(delaySeconds) or 5)))
  local query = ([=[
    UPDATE mz_financial_outbox
    SET status = 'pending',
        next_retry_at = TIMESTAMPADD(SECOND, %d, CURRENT_TIMESTAMP),
        claim_token = NULL,
        claimed_at = NULL,
        lease_expires_at = NULL,
        last_error = ?
    WHERE id = ? AND status = 'processing' AND claim_token = ?
  ]=]):format(delaySeconds)
  local affected = MySQL.update.await(query, { errorCode, id, token })
  return tonumber(affected) == 1
end

function MZFinancialOutboxRepository.moveToDeadLetter(id, token, errorCode)
  local affected = MySQL.update.await([[
    UPDATE mz_financial_outbox
    SET status = 'dead_letter',
        claim_token = NULL,
        claimed_at = NULL,
        lease_expires_at = NULL,
        last_error = ?
    WHERE id = ? AND status = 'processing' AND claim_token = ?
  ]], { errorCode, id, token })
  return tonumber(affected) == 1
end

function MZFinancialOutboxRepository.getHealthSnapshot()
  return MySQL.single.await([[
    SELECT
      COALESCE(SUM(status = 'pending'), 0) AS pending_count,
      COALESCE(SUM(status = 'processing'), 0) AS processing_count,
      COALESCE(SUM(status = 'processed'), 0) AS processed_count,
      COALESCE(SUM(status = 'dead_letter'), 0) AS dead_letter_count,
      COALESCE(MAX(CASE WHEN status = 'pending'
        THEN TIMESTAMPDIFF(SECOND, created_at, CURRENT_TIMESTAMP) ELSE 0 END), 0)
        AS oldest_pending_seconds
    FROM mz_financial_outbox
  ]]) or {}
end

function MZFinancialOutboxRepository.getDeadLetterById(id)
  return MySQL.single.await(([[
    SELECT %s, last_error
    FROM mz_financial_outbox
    WHERE id = ? AND status = 'dead_letter'
    LIMIT 1
  ]]):format(EVENT_COLUMNS), { id })
end

function MZFinancialOutboxRepository.getDeadLetterByCorrelation(correlationId)
  return MySQL.single.await(([[
    SELECT %s, last_error
    FROM mz_financial_outbox
    WHERE correlation_id = ? AND status = 'dead_letter'
    LIMIT 1
  ]]):format(EVENT_COLUMNS), { correlationId })
end

function MZFinancialOutboxRepository.reprocessDeadLetter(snapshot)
  local affected = MySQL.update.await([[
    UPDATE mz_financial_outbox
    SET status = 'pending',
        attempts = 0,
        next_retry_at = CURRENT_TIMESTAMP,
        claim_token = NULL,
        claimed_at = NULL,
        lease_expires_at = NULL,
        processed_at = NULL,
        last_error = NULL
    WHERE id = ?
      AND status = 'dead_letter'
      AND correlation_id = ?
      AND payload_version = ?
      AND metadata_json = ?
  ]], {
    snapshot.id,
    snapshot.correlation_id,
    snapshot.payload_version,
    snapshot.metadata_json
  })
  return tonumber(affected) == 1
end

function MZFinancialOutboxRepository.getReconciliationReport(pendingSlaSeconds, retentionDays, limit)
  pendingSlaSeconds = math.max(60, math.min(86400, math.floor(tonumber(pendingSlaSeconds) or 300)))
  retentionDays = math.max(1, math.min(3650, math.floor(tonumber(retentionDays) or 90)))
  limit = math.max(1, math.min(100, math.floor(tonumber(limit) or 50)))

  local summary = MySQL.single.await(([[
    SELECT
      (SELECT COUNT(*)
       FROM mz_financial_outbox o
       LEFT JOIN mz_economy_outbox_receipts r ON r.outbox_id = o.id
       WHERE o.status = 'processed' AND r.id IS NULL) AS processed_without_receipt,
      (SELECT COUNT(*)
       FROM mz_financial_outbox
       WHERE status = 'pending'
         AND created_at < TIMESTAMPADD(SECOND, -%d, CURRENT_TIMESTAMP)) AS overdue_pending,
      (SELECT COUNT(*) FROM mz_financial_outbox WHERE status = 'dead_letter') AS dead_letter_count,
      (SELECT COUNT(*)
       FROM mz_financial_outbox
       WHERE status = 'processed'
         AND processed_at < TIMESTAMPADD(DAY, -%d, CURRENT_TIMESTAMP)) AS retention_eligible,
      (SELECT COUNT(*) FROM (
         SELECT correlation_id
         FROM mz_financial_outbox
         GROUP BY correlation_id HAVING COUNT(*) > 1
       ) duplicate_outbox) AS duplicate_outbox_correlations,
      (SELECT COUNT(*) FROM (
         SELECT correlation_id
         FROM mz_economy_outbox_receipts
         GROUP BY correlation_id HAVING COUNT(*) > 1
       ) duplicate_receipts) AS duplicate_receipt_correlations
  ]]):format(pendingSlaSeconds, retentionDays)) or {}

  local receiptMismatch = MySQL.single.await([[
    SELECT COUNT(*) AS total
    FROM (
      SELECT r.id
      FROM mz_economy_outbox_receipts r
      LEFT JOIN mz_economy_transactions t
        ON t.transaction_id LIKE CONCAT('mzoutbox:', r.outbox_id, ':%')
      GROUP BY r.id, r.entry_count
      HAVING COUNT(t.id) <> r.entry_count
    ) mismatches
  ]]) or {}

  local ledgerWithoutReceipt = MySQL.single.await([[
    SELECT COUNT(*) AS total
    FROM mz_economy_transactions t
    WHERE t.transaction_id LIKE 'mzoutbox:%'
      AND NOT EXISTS (
        SELECT 1
        FROM mz_economy_outbox_receipts r
        WHERE t.transaction_id LIKE CONCAT('mzoutbox:', r.outbox_id, ':%')
      )
  ]]) or {}

  local groups = MySQL.query.await(([[
    SELECT event_type, source_resource, status,
           COUNT(*) AS total, COALESCE(SUM(attempts), 0) AS attempts
    FROM mz_financial_outbox
    GROUP BY event_type, source_resource, status
    ORDER BY status ASC, total DESC, event_type ASC
    LIMIT %d
  ]]):format(limit)) or {}

  return {
    processedWithoutReceipt = tonumber(summary.processed_without_receipt) or 0,
    receiptLegMismatch = tonumber(receiptMismatch.total) or 0,
    ledgerWithoutReceipt = tonumber(ledgerWithoutReceipt.total) or 0,
    overduePending = tonumber(summary.overdue_pending) or 0,
    deadLetterCount = tonumber(summary.dead_letter_count) or 0,
    retentionEligible = tonumber(summary.retention_eligible) or 0,
    duplicateOutboxCorrelations = tonumber(summary.duplicate_outbox_correlations) or 0,
    duplicateReceiptCorrelations = tonumber(summary.duplicate_receipt_correlations) or 0,
    groups = groups
  }
end
