-- Fase 3 / P3-E: administracao server-side e reconciliacao read-only.
-- Nao altera saldo, payload ou ledger. Nao oferece evento/export/callback ao client.

MZFinancialOutboxAdmin = MZFinancialOutboxAdmin or {}

local rootPolicy = Config and Config.FinancialOutbox or {}
local policy = type(rootPolicy.administration) == 'table' and rootPolicy.administration or {}
local previews = {}

local function trim(value)
  if type(value) ~= 'string' then return '' end
  return value:match('^%s*(.-)%s*$') or ''
end

local function stableCode(value, fallback)
  local text = trim(tostring(value or '')):lower()
  text = text:gsub('[^%w_:%-%.]', '_')
  if text == '' then text = fallback or 'unknown' end
  if #text > 100 then text = text:sub(1, 100) end
  return text
end

local function integer(value, minimum, maximum)
  local number = tonumber(value)
  if not number or number % 1 ~= 0 or number < minimum or number > maximum then return nil end
  return math.floor(number)
end

local function actorFor(source)
  source = tonumber(source) or 0
  return source == 0 and 'console' or ('source:%d'):format(source)
end

local function hasRequiredAce(source)
  local ace = trim(policy.ace)
  if ace == '' then return false, 'admin_ace_missing' end
  local check, principal = IsPlayerAceAllowed, tonumber(source)
  if tonumber(source) == 0 then
    check = IsPrincipalAceAllowed
    principal = 'system.console'
  end
  if type(check) ~= 'function' then return false, 'admin_ace_unavailable' end
  local ok, allowed = pcall(check, principal, ace)
  local normalized = tostring(allowed):lower()
  if ok and (allowed == true or allowed == 1 or normalized == 'true' or normalized == '1') then
    return true
  end
  return false, 'admin_forbidden'
end

local function policyValid()
  if policy.enabled ~= true then return false, 'admin_disabled' end
  if trim(policy.ace) == '' then return false, 'invalid_admin_ace' end
  if not trim(policy.command):match('^[%w_]+$') then return false, 'invalid_admin_command' end
  if trim(policy.applyEnableConvar) == '' then return false, 'invalid_apply_convar' end
  if trim(policy.confirmationPhrase) ~= 'REPROCESS_DEAD_LETTER' then
    return false, 'invalid_confirmation_phrase'
  end
  if not integer(policy.previewTtlSeconds, 30, 1800) then return false, 'invalid_preview_ttl' end
  if not integer(policy.pendingSlaSeconds, 60, 86400) then return false, 'invalid_pending_sla' end
  if not integer(policy.processedRetentionDays, 1, 3650) then return false, 'invalid_retention_days' end
  if not integer(policy.reportLimit, 1, 100) then return false, 'invalid_report_limit' end
  return true
end

local policyOk, policyError = policyValid()

local function applyEnabled()
  if policy.allowApply == true then return true end
  return GetConvarInt(trim(policy.applyEnableConvar), 0) == 1
end

local function cleanupPreviews()
  local now = os.time()
  local ttl = tonumber(policy.previewTtlSeconds) or 120
  for ref, preview in pairs(previews) do
    if preview.used == true or now - preview.createdAt > ttl then previews[ref] = nil end
  end
end

local function previewCount()
  local total = 0
  for _ in pairs(previews) do total = total + 1 end
  return total
end

local function audit(action, actor, outboxId, data)
  if not MZLogService or type(MZLogService.create) ~= 'function' then return false end
  local ok = pcall(function()
    MZLogService.create(
      'financial_outbox',
      action,
      actor,
      ('outbox:%s'):format(tostring(outboxId or 'report')),
      data or {}
    )
  end)
  return ok
end

local function eventFromRow(row)
  return {
    id = tonumber(row.id),
    correlationId = tostring(row.correlation_id or ''),
    eventType = tostring(row.event_type or ''),
    sourceCitizenId = tostring(row.source_citizenid or ''),
    targetCitizenId = row.target_citizenid and tostring(row.target_citizenid) or '',
    account = tostring(row.account or ''),
    amount = tonumber(row.amount),
    fee = tonumber(row.fee),
    reason = tostring(row.reason or ''),
    sourceResource = tostring(row.source_resource or ''),
    sourceChannel = tostring(row.source_channel or ''),
    payloadVersion = tonumber(row.payload_version),
    metadataJson = tostring(row.metadata_json or '')
  }
end

local function validateWithConsumer(row)
  if GetResourceState('mz_economy') ~= 'started' then return false, 'economy_not_started' end
  local called, result = pcall(function()
    return exports['mz_economy']:ValidateFinancialOutbox(eventFromRow(row))
  end)
  if not called or type(result) ~= 'table' then return false, 'validator_unavailable' end
  if result.ok ~= true then return false, stableCode(result.error, 'event_invalid') end
  return true, nil, tonumber(result.entryCount) or 0
end

local function sameSnapshot(left, right)
  return left and right
    and tonumber(left.id) == tonumber(right.id)
    and tostring(left.correlation_id or '') == tostring(right.correlation_id or '')
    and tonumber(left.payload_version) == tonumber(right.payload_version)
    and tostring(left.metadata_json or '') == tostring(right.metadata_json or '')
end

function MZFinancialOutboxAdmin.Preview(selectorType, selectorValue, reasonCode, actor)
  if not policyOk then return { ok = false, error = policyError } end
  cleanupPreviews()
  if previewCount() >= 32 then return { ok = false, error = 'preview_capacity' } end

  selectorType = trim(selectorType):lower()
  reasonCode = trim(reasonCode):lower()
  if #reasonCode < 8 or #reasonCode > 64 or not reasonCode:match('^[%w_%-]+$') then
    return { ok = false, error = 'invalid_reason_code' }
  end

  local queryOk, row = pcall(function()
    if selectorType == 'id' then
      local id = integer(selectorValue, 1, 9007199254740991)
      if not id then return nil end
      return MZFinancialOutboxRepository.getDeadLetterById(id)
    end
    if selectorType == 'correlation' then
      local correlation = trim(selectorValue)
      if correlation == '' or #correlation > 128 then return nil end
      return MZFinancialOutboxRepository.getDeadLetterByCorrelation(correlation)
    end
    return nil
  end)
  if not queryOk then return { ok = false, error = 'dead_letter_lookup_failed' } end
  if type(row) ~= 'table' then return { ok = false, error = 'dead_letter_not_found' } end

  local valid, validationErr, entryCount = validateWithConsumer(row)
  if not valid then return { ok = false, error = validationErr } end

  local refOk, runRef = pcall(MZFinancialOutboxRepository.newClaimToken)
  if not refOk or type(runRef) ~= 'string' or #runRef ~= 32 then
    return { ok = false, error = 'preview_ref_failed' }
  end

  local preview = {
    ref = runRef,
    actor = tostring(actor),
    reasonCode = reasonCode,
    createdAt = os.time(),
    used = false,
    row = row,
    entryCount = entryCount
  }
  if not audit('dead_letter_preview', preview.actor, row.id, {
    outbox_id = tonumber(row.id),
    event_type = stableCode(row.event_type),
    source_resource = stableCode(row.source_resource),
    attempts = tonumber(row.attempts) or 0,
    entry_count = entryCount,
    reason_code = reasonCode,
    status = 'dead_letter',
    balance_changes = false,
    payload_changes = false
  }) then
    return { ok = false, error = 'audit_unavailable' }
  end
  previews[runRef] = preview

  return {
    ok = true,
    runRef = runRef,
    outboxId = tonumber(row.id),
    eventType = stableCode(row.event_type),
    sourceResource = stableCode(row.source_resource),
    attempts = tonumber(row.attempts) or 0,
    lastError = stableCode(row.last_error, 'none'),
    entryCount = entryCount,
    expiresIn = tonumber(policy.previewTtlSeconds),
    confirmation = trim(policy.confirmationPhrase)
  }
end

function MZFinancialOutboxAdmin.Reprocess(runRef, confirmation, actor)
  if not policyOk then return { ok = false, error = policyError } end
  if not applyEnabled() then return { ok = false, error = 'reprocess_apply_disabled' } end
  cleanupPreviews()

  runRef = trim(runRef):lower()
  if not runRef:match('^[0-9a-f]+$') or #runRef ~= 32 then
    return { ok = false, error = 'invalid_preview_ref' }
  end
  if trim(confirmation) ~= trim(policy.confirmationPhrase) then
    return { ok = false, error = 'confirmation_mismatch' }
  end

  local preview = previews[runRef]
  if not preview then return { ok = false, error = 'preview_missing_or_expired' } end
  if preview.used == true then return { ok = false, error = 'preview_already_used' } end
  if tostring(preview.actor) ~= tostring(actor) then return { ok = false, error = 'preview_actor_mismatch' } end
  preview.used = true
  previews[runRef] = nil

  local lookupOk, current = pcall(MZFinancialOutboxRepository.getDeadLetterById, preview.row.id)
  if not lookupOk or not sameSnapshot(preview.row, current) then
    return { ok = false, error = 'dead_letter_changed' }
  end
  local valid, validationErr = validateWithConsumer(current)
  if not valid then return { ok = false, error = validationErr } end

  local beforeAudit = audit('dead_letter_reprocess_requested', actor, current.id, {
    outbox_id = tonumber(current.id),
    event_type = stableCode(current.event_type),
    source_resource = stableCode(current.source_resource),
    reason_code = preview.reasonCode,
    attempts_before = tonumber(current.attempts) or 0,
    status_before = 'dead_letter',
    balance_changes = false,
    payload_changes = false
  })
  if not beforeAudit then return { ok = false, error = 'audit_unavailable' } end

  local updateOk, updated = pcall(MZFinancialOutboxRepository.reprocessDeadLetter, current)
  if not updateOk or updated ~= true then
    audit('dead_letter_reprocess_failed', actor, current.id, {
      outbox_id = tonumber(current.id),
      reason_code = preview.reasonCode,
      error = 'conditional_update_failed',
      balance_changes = false,
      payload_changes = false
    })
    return { ok = false, error = 'reprocess_failed' }
  end

  local afterAudit = audit('dead_letter_reprocess_completed', actor, current.id, {
    outbox_id = tonumber(current.id),
    event_type = stableCode(current.event_type),
    source_resource = stableCode(current.source_resource),
    reason_code = preview.reasonCode,
    attempts_after = 0,
    transition = 'dead_letter_to_pending',
    balance_changes = false,
    payload_changes = false
  })

  local afterError = nil
  if afterAudit ~= true then
    afterError = 'audit_after_failed'
  end

  return {
    ok = afterAudit == true,
    error = afterError,
    stateChanged = true,
    outboxId = tonumber(current.id),
    status = 'requeued'
  }
end

function MZFinancialOutboxAdmin.Reconcile(actor)
  if not policyOk then return { ok = false, error = policyError } end
  local ok, report = pcall(
    MZFinancialOutboxRepository.getReconciliationReport,
    policy.pendingSlaSeconds,
    policy.processedRetentionDays,
    policy.reportLimit
  )
  if not ok or type(report) ~= 'table' then
    return { ok = false, error = 'reconciliation_failed' }
  end

  report.ok = true
  report.readOnly = true
  report.retentionDays = tonumber(policy.processedRetentionDays)
  report.pendingSlaSeconds = tonumber(policy.pendingSlaSeconds)
  audit('reconciliation_read_only', actor, 'report', {
    processed_without_receipt = report.processedWithoutReceipt,
    receipt_leg_mismatch = report.receiptLegMismatch,
    ledger_without_receipt = report.ledgerWithoutReceipt,
    overdue_pending = report.overduePending,
    dead_letter_count = report.deadLetterCount,
    retention_eligible = report.retentionEligible,
    duplicate_outbox_correlations = report.duplicateOutboxCorrelations,
    duplicate_receipt_correlations = report.duplicateReceiptCorrelations,
    read_only = true,
    balance_changes = false
  })
  return report
end

local function printResult(label, result)
  print(('[mz_core][outbox-admin] %s ok=%s outbox_id=%s run_ref=%s type=%s source_resource=%s attempts=%s entry_count=%s expires=%s status=%s state_changed=%s error=%s balance_changes=false payload_changes=false'):format(
    label,
    tostring(result.ok == true),
    tostring(result.outboxId or 'none'),
    tostring(result.runRef or 'none'),
    tostring(result.eventType or 'none'),
    tostring(result.sourceResource or 'none'),
    tostring(result.attempts or 0),
    tostring(result.entryCount or 0),
    tostring(result.expiresIn or 0),
    tostring(result.status or 'none'),
    tostring(result.stateChanged == true),
    tostring(result.error or 'none')
  ))
end

if policyOk then
  RegisterCommand(trim(policy.command), function(source, args)
    local allowed, aceErr = hasRequiredAce(source)
    if not allowed then
      print(('[mz_core][outbox-admin] denied source=%s error=%s'):format(tostring(source), aceErr))
      return
    end

    local action = trim(args and args[1] or ''):lower()
    local actor = actorFor(source)
    if action == 'preview' then
      printResult('PREVIEW', MZFinancialOutboxAdmin.Preview(args[2], args[3], args[4], actor))
      return
    end
    if action == 'reprocess' then
      printResult('REPROCESS', MZFinancialOutboxAdmin.Reprocess(args[2], args[3], actor))
      return
    end
    if action == 'reconcile' then
      local result = MZFinancialOutboxAdmin.Reconcile(actor)
      print(('[mz_core][outbox-admin] RECONCILE ok=%s processed_without_receipt=%s receipt_leg_mismatch=%s ledger_without_receipt=%s overdue_pending=%s dead_letter=%s retention_eligible=%s duplicate_outbox=%s duplicate_receipts=%s groups=%s read_only=true balance_changes=false error=%s'):format(
        tostring(result.ok == true),
        tostring(result.processedWithoutReceipt or 0),
        tostring(result.receiptLegMismatch or 0),
        tostring(result.ledgerWithoutReceipt or 0),
        tostring(result.overduePending or 0),
        tostring(result.deadLetterCount or 0),
        tostring(result.retentionEligible or 0),
        tostring(result.duplicateOutboxCorrelations or 0),
        tostring(result.duplicateReceiptCorrelations or 0),
        tostring(type(result.groups) == 'table' and #result.groups or 0),
        tostring(result.error or 'none')
      ))
      return
    end

    print(('[mz_core][outbox-admin] usage: %s reconcile'):format(trim(policy.command)))
    print(('[mz_core][outbox-admin] usage: %s preview <id|correlation> <value> <reason_code>'):format(trim(policy.command)))
    print(('[mz_core][outbox-admin] usage: %s reprocess <run_ref> %s'):format(
      trim(policy.command), trim(policy.confirmationPhrase)
    ))
  end, true)

  print(('[mz_core][outbox-admin] registered command=%s apply=%s ace=%s retention_days=%s purge=false'):format(
    trim(policy.command),
    tostring(applyEnabled()),
    trim(policy.ace),
    tostring(policy.processedRetentionDays)
  ))
elseif policy.enabled == true then
  print(('[mz_core][outbox-admin] unavailable error=%s'):format(tostring(policyError)))
end
