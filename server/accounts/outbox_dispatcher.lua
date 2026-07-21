-- Fase 3 / P3-D: dispatcher do mz_core.
-- Nao altera saldo e nao oferece endpoint ao client.

MZFinancialOutboxDispatcher = MZFinancialOutboxDispatcher or {}

local lastEconomyState = nil
local lastHealthAt = 0

local function clampInteger(value, minimum, maximum, fallback)
  value = tonumber(value)
  if not value or value % 1 ~= 0 then value = fallback end
  value = math.floor(value)
  if value < minimum then value = minimum end
  if value > maximum then value = maximum end
  return value
end

local function dispatcherConfig()
  local root = Config and Config.FinancialOutbox or {}
  local cfg = type(root.dispatcher) == 'table' and root.dispatcher or {}
  return {
    enabled = root.enabled == true and cfg.enabled == true,
    pollMs = clampInteger(cfg.pollMs, 250, 60000, 1000),
    batchSize = clampInteger(cfg.batchSize, 1, 100, 25),
    leaseSeconds = clampInteger(cfg.leaseSeconds, 5, 3600, 30),
    maxAttempts = clampInteger(cfg.maxAttempts, 1, 100, 10),
    backoffBaseSeconds = clampInteger(cfg.backoffBaseSeconds, 1, 3600, 5),
    backoffMaxSeconds = clampInteger(cfg.backoffMaxSeconds, 1, 86400, 900),
    jitterPercent = clampInteger(cfg.jitterPercent, 0, 50, 20)
  }
end

local function stateReady(cfg)
  local state = MZCoreState and MZCoreState.financialOutbox
  return MZCoreState
    and MZCoreState.ready == true
    and type(state) == 'table'
    and state.schemaReady == true
    and state.enabled == true
    and state.dispatcherEnabled == true
    and cfg.enabled == true
end

local function sanitizeError(value)
  local text = tostring(value or 'unknown_error'):lower()
  text = text:gsub('[^%w_:%-%. ]', '_')
  if #text > 255 then text = text:sub(1, 255) end
  if text == '' then text = 'unknown_error' end
  return text
end

local function safeLogValue(value, maximum)
  local text = tostring(value or 'unknown'):lower()
  text = text:gsub('[^%w_:%-%.= ]', '_')
  maximum = tonumber(maximum) or 100
  if #text > maximum then text = text:sub(1, maximum) end
  return text
end

local function maskedEventLog(prefix, row, detail)
  print(('[mz_core][outbox-dispatcher] %s id=%s type=%s source_resource=%s detail=%s'):format(
    safeLogValue(prefix, 32),
    tostring(row and row.id or 'none'),
    safeLogValue(row and row.event_type or 'unknown', 64),
    safeLogValue(row and row.source_resource or 'unknown', 100),
    safeLogValue(detail or 'none', 180)
  ))
end

local function economyConsumerReady()
  if type(GetResourceState) ~= 'function' or GetResourceState('mz_economy') ~= 'started' then
    return false, 'economy_not_started'
  end

  local called, result = pcall(function()
    return exports['mz_economy']:GetFinancialOutboxConsumerReadiness()
  end)
  if not called or type(result) ~= 'table' then
    return false, 'economy_readiness_unavailable'
  end
  if result.ok ~= true or result.ready ~= true then
    return false, sanitizeError(result.error or 'economy_consumer_not_ready')
  end
  return true
end

local function publishEconomyState(ready, reason)
  local nextState = ready and 'ready' or tostring(reason or 'unavailable')
  if nextState == lastEconomyState then return end
  lastEconomyState = nextState
  print(('[mz_core][outbox-dispatcher] economy=%s reason=%s'):format(
    ready and 'ready' or 'unavailable',
    ready and 'none' or sanitizeError(reason)
  ))
end

local function backoffSeconds(attempts, cfg)
  attempts = math.max(1, math.floor(tonumber(attempts) or 1))
  local exponent = math.min(attempts - 1, 20)
  local capped = math.min(cfg.backoffMaxSeconds, cfg.backoffBaseSeconds * (2 ^ exponent))
  local spread = capped * (cfg.jitterPercent / 100)
  local jittered = capped
  if spread > 0 then
    jittered = capped - spread + (math.random() * spread * 2)
  end
  return math.max(1, math.min(cfg.backoffMaxSeconds, math.floor(jittered + 0.5)))
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

local function metricsState()
  MZCoreState.financialOutbox.dispatcher = MZCoreState.financialOutbox.dispatcher or {
    cycles = 0,
    claimed = 0,
    processed = 0,
    replayed = 0,
    retried = 0,
    deadLetter = 0,
    recoveredLeases = 0,
    ackFailures = 0,
    lastError = nil,
    lastCycleAt = nil,
    health = {}
  }
  return MZCoreState.financialOutbox.dispatcher
end

local function refreshHealth(force)
  local now = type(GetGameTimer) == 'function' and GetGameTimer() or 0
  if force ~= true and now - lastHealthAt < 30000 then return end
  lastHealthAt = now
  local ok, snapshot = pcall(MZFinancialOutboxRepository.getHealthSnapshot)
  if ok and type(snapshot) == 'table' then
    metricsState().health = {
      pending = tonumber(snapshot.pending_count) or 0,
      processing = tonumber(snapshot.processing_count) or 0,
      processed = tonumber(snapshot.processed_count) or 0,
      deadLetter = tonumber(snapshot.dead_letter_count) or 0,
      oldestPendingSeconds = tonumber(snapshot.oldest_pending_seconds) or 0
    }
  end
end

local function finishFailure(row, token, result, cfg, metrics)
  local errorCode = sanitizeError(type(result) == 'table' and result.error or 'consumer_call_failed')
  local retryable = type(result) == 'table' and result.retryable ~= false
  local attempts = tonumber(row.attempts) or 1
  local shouldDeadLetter = retryable ~= true or attempts >= cfg.maxAttempts

  local updated = false
  if shouldDeadLetter then
    local ok, value = pcall(MZFinancialOutboxRepository.moveToDeadLetter, row.id, token, errorCode)
    updated = ok and value == true
    if updated then metrics.deadLetter = metrics.deadLetter + 1 end
    maskedEventLog(updated and 'DEAD_LETTER' or 'FAIL_STATE_UPDATE', row, errorCode)
  else
    local delay = backoffSeconds(attempts, cfg)
    local ok, value = pcall(
      MZFinancialOutboxRepository.reschedule,
      row.id,
      token,
      delay,
      errorCode
    )
    updated = ok and value == true
    if updated then metrics.retried = metrics.retried + 1 end
    maskedEventLog(updated and 'RETRY' or 'FAIL_STATE_UPDATE', row, ('%s delay=%ss'):format(errorCode, delay))
  end

  if not updated then
    metrics.lastError = 'claim_state_update_failed'
  else
    metrics.lastError = errorCode
  end
end

function MZFinancialOutboxDispatcher.RunOnce()
  local cfg = dispatcherConfig()
  if not stateReady(cfg) then return { ok = false, error = 'dispatcher_not_ready' } end

  local metrics = metricsState()
  metrics.cycles = metrics.cycles + 1
  metrics.lastCycleAt = os.time()

  local recoveredOk, recovered = pcall(MZFinancialOutboxRepository.recoverExpiredLeases)
  if not recoveredOk then
    metrics.lastError = 'lease_recovery_failed'
    return { ok = false, error = 'lease_recovery_failed' }
  end
  recovered = tonumber(recovered) or 0
  if recovered > 0 then
    metrics.recoveredLeases = metrics.recoveredLeases + recovered
    print(('[mz_core][outbox-dispatcher] leases_recovered=%d'):format(recovered))
  end

  local economyReady, economyErr = economyConsumerReady()
  publishEconomyState(economyReady, economyErr)
  if not economyReady then
    refreshHealth(false)
    return { ok = true, skipped = true, reason = economyErr, claimed = 0 }
  end

  local tokenOk, token = pcall(MZFinancialOutboxRepository.newClaimToken)
  if not tokenOk or type(token) ~= 'string' or token == '' then
    metrics.lastError = 'claim_token_failed'
    return { ok = false, error = 'claim_token_failed' }
  end
  local claimedOk, claimed = pcall(
    MZFinancialOutboxRepository.claimEligible,
    token,
    cfg.batchSize,
    cfg.leaseSeconds
  )
  if not claimedOk then
    metrics.lastError = 'claim_failed'
    return { ok = false, error = 'claim_failed' }
  end
  claimed = tonumber(claimed) or 0
  if claimed == 0 then
    refreshHealth(false)
    return { ok = true, claimed = 0, processed = 0 }
  end
  metrics.claimed = metrics.claimed + claimed

  local rowsOk, rows = pcall(MZFinancialOutboxRepository.getClaimed, token)
  if not rowsOk or type(rows) ~= 'table' then
    metrics.lastError = 'claimed_select_failed'
    return { ok = false, error = 'claimed_select_failed', claimed = claimed }
  end

  local processed, replayed, failed = 0, 0, 0
  for _, row in ipairs(rows) do
    local called, result = pcall(function()
      return exports['mz_economy']:ConsumeFinancialOutbox(eventFromRow(row))
    end)
    if called and type(result) == 'table' and result.ok == true then
      local ackOk, acked = pcall(MZFinancialOutboxRepository.acknowledge, row.id, token)
      if ackOk and acked == true then
        processed = processed + 1
        metrics.processed = metrics.processed + 1
        if result.replayed == true then
          replayed = replayed + 1
          metrics.replayed = metrics.replayed + 1
        end
        maskedEventLog('ACK', row, result.replayed and 'consumer_replay=true' or 'consumer_replay=false')
      else
        failed = failed + 1
        metrics.ackFailures = metrics.ackFailures + 1
        metrics.lastError = 'ack_failed'
        maskedEventLog('ACK_FAILED', row, 'lease_will_recover')
      end
    else
      failed = failed + 1
      if not called then result = { error = 'consumer_call_failed', retryable = true } end
      finishFailure(row, token, result, cfg, metrics)
    end
  end

  refreshHealth(true)
  return {
    ok = true,
    claimed = claimed,
    selected = #rows,
    processed = processed,
    replayed = replayed,
    failed = failed,
    recoveredLeases = recovered
  }
end

function MZFinancialOutboxDispatcher.GetStatus()
  local cfg = dispatcherConfig()
  if MZCoreState and MZCoreState.financialOutbox and MZCoreState.financialOutbox.schemaReady == true then
    refreshHealth(true)
  end
  return {
    enabled = cfg.enabled,
    ready = stateReady(cfg),
    config = cfg,
    metrics = MZCoreState
      and MZCoreState.financialOutbox
      and MZCoreState.financialOutbox.dispatcher
      or nil
  }
end

CreateThread(function()
  while not (MZCoreState and MZCoreState.ready == true) do Wait(250) end

  local cfg = dispatcherConfig()
  if not stateReady(cfg) then
    print('[mz_core][outbox-dispatcher] disabled')
    return
  end

  print(('[mz_core][outbox-dispatcher] started poll=%dms batch=%d lease=%ds max_attempts=%d'):format(
    cfg.pollMs,
    cfg.batchSize,
    cfg.leaseSeconds,
    cfg.maxAttempts
  ))

  while stateReady(cfg) do
    local ok, result = pcall(MZFinancialOutboxDispatcher.RunOnce)
    if not ok then
      metricsState().lastError = 'dispatcher_cycle_exception'
      print('[mz_core][outbox-dispatcher] cycle_failed error=dispatcher_cycle_exception')
    elseif type(result) == 'table' and result.ok ~= true then
      print(('[mz_core][outbox-dispatcher] cycle_failed error=%s'):format(sanitizeError(result.error)))
    end
    Wait(cfg.pollMs)
  end
end)
