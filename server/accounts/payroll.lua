MZPayrollService = {}

local function asBool(value)
  if value == true then return true end
  if value == false or value == nil then return false end
  if type(value) == 'number' then return value == 1 end
  if type(value) == 'string' then
    value = value:lower()
    return value == '1' or value == 'true'
  end
  return false
end

local function getOrgMembershipsForCitizen(citizenid)
  return MySQL.query.await([[
    SELECT po.*, o.code AS org_code, o.name AS org_name, o.has_salary, o.has_shared_account,
           g.level AS grade_level, g.name AS grade_name, g.salary
    FROM mz_player_orgs po
    INNER JOIN mz_orgs o ON o.id = po.org_id
    INNER JOIN mz_org_grades g ON g.id = po.grade_id
    WHERE po.citizenid = ? AND po.active = 1
  ]], { citizenid }) or {}
end

local function buildPayrollActor(actor)
  if actor == nil then
    return {
      type = 'system',
      id = 'system'
    }
  end

  if tonumber(actor) == 0 then
    return {
      type = 'console',
      id = 'console'
    }
  end

  if type(actor) == 'number' then
    local player = MZPlayerService.getPlayer(actor)
    if player and player.citizenid then
      return {
        type = 'player',
        id = tostring(player.citizenid),
        source = actor
      }
    end

    return {
      type = 'source',
      id = tostring(actor)
    }
  end

  return {
    type = 'system',
    id = tostring(actor)
  }
end

local ledgerSequence = 0

local function nextPayrollLedgerRef(orgCode, citizenid)
  ledgerSequence = ledgerSequence + 1
  local stamp = type(GetGameTimer) == 'function' and GetGameTimer() or os.time()
  return ('payroll:%s:%s:%s:%s'):format(
    tostring(orgCode or 'unknown'),
    tostring(citizenid or 'unknown'),
    tostring(stamp),
    tostring(ledgerSequence)
  )
end

local function recordPayrollLedger(data)
  if MZAccountService and type(MZAccountService.RecordEconomyTransactionSafe) == 'function' then
    return MZAccountService.RecordEconomyTransactionSafe(data)
  end

  return false, 'ledger_service_unavailable'
end

local persistPayrollPayment
local recordLegacyPayroll

function MZPayrollService.payCitizen(citizenid, actor)
  local playerRow = MZPlayerRepository.getByCitizenId(citizenid)
  if not playerRow then
    return false, 'player_not_found'
  end

  local memberships = getOrgMembershipsForCitizen(citizenid)
  if #memberships == 0 then
    return false, 'no_memberships'
  end

  local paid = {}
  local skipped = {}
  local requireDuty = true
  local bankBefore = nil
  local bankAfter = nil

  if Config.Payroll and Config.Payroll.requireDuty == false then
    requireDuty = false
  end

  for _, membership in ipairs(memberships) do
    local salary = math.floor(tonumber(membership.salary) or 0)

    if asBool(membership.has_salary) and salary > 0 then
      if (not requireDuty) or asBool(membership.duty) then
        if not asBool(membership.has_shared_account) then
          skipped[#skipped + 1] = {
            org = membership.org_code,
            amount = salary,
            reason = 'org_has_no_shared_account'
          }
          goto continue_membership
        end

        local paidOk, detailOrErr = persistPayrollPayment(
          citizenid, membership, salary, playerRow, requireDuty
        )
        if paidOk then
          local detail = detailOrErr
          if bankBefore == nil then bankBefore = detail.bankBefore end
          bankAfter = detail.bankAfter
          if detail.outboxPersisted ~= true then
            recordLegacyPayroll(citizenid, membership, salary, detail)
          end
          paid[#paid + 1] = {
            org = membership.org_code,
            amount = salary,
            source = 'org_account',
            replayed = detail.replayed == true
          }
        else
          skipped[#skipped + 1] = {
            org = membership.org_code,
            amount = salary,
            reason = detailOrErr or 'payment_failed'
          }
        end
      end
    end

    ::continue_membership::
  end

  if MZLogService and #skipped > 0 then
    MZLogService.createDetailed('payroll', 'pay_citizen_inconsistency', {
      actor = buildPayrollActor(actor),
      target = {
        type = 'player_account',
        id = tostring(citizenid)
      },
      context = {
        citizenid = tostring(citizenid),
        require_duty = requireDuty == true,
        membership_count = #memberships
      },
      meta = {
        skipped = skipped
      }
    })
  end

  if #paid == 0 then
    return false, 'nothing_paid'
  end

  if MZLogService then
    MZLogService.createDetailed('payroll', 'pay_citizen', {
      actor = buildPayrollActor(actor),
      target = {
        type = 'player_account',
        id = tostring(citizenid)
      },
      context = {
        citizenid = tostring(citizenid),
        require_duty = requireDuty == true,
        membership_count = #memberships
      },
      before = {
        bank = math.floor(tonumber(bankBefore) or 0)
      },
      after = {
        bank = math.floor(tonumber(bankAfter ~= nil and bankAfter or bankBefore) or 0)
      },
      meta = {
        payments = paid,
        skipped = skipped
      }
    })
  end

  return true, paid
end

persistPayrollPayment = function(citizenid, membership, salary, playerRow, requireDuty)
  return MZAccountService.WithFinancialLocksInternal({
    tostring(citizenid),
    ('org:%s'):format(membership.org_id)
  }, function()
    local playerAccount = MySQL.single.await(
      'SELECT bank FROM mz_player_accounts WHERE citizenid = ? LIMIT 1',
      { citizenid }
    )
    local orgAccount = MySQL.single.await(
      'SELECT balance FROM mz_org_accounts WHERE org_id = ? LIMIT 1',
      { membership.org_id }
    )
    if not playerAccount then return false, 'account_not_found' end
    if not orgAccount then return false, 'org_account_missing' end

    local bankBefore = math.floor(tonumber(playerAccount.bank) or 0)
    local orgBefore = math.floor(tonumber(orgAccount.balance) or 0)
    local intervalMinutes = math.max(1, math.floor(tonumber(Config.Payroll and Config.Payroll.intervalMinutes) or 30))
    local payrollBucket = math.floor(os.time() / (intervalMinutes * 60))
    local idempotencyKey = ('payroll_%s_%d'):format(tostring(membership.org_id), payrollBucket)
    local requestFingerprint = ('org=%s;citizen=%s;salary=%d;bucket=%d'):format(
      tostring(membership.org_id), tostring(citizenid), salary, payrollBucket
    )
    local existing = MZAccountRepository.getIdempotentOperation('mz_core', citizenid, idempotencyKey)
    if existing then
      if tostring(existing.operation or '') ~= 'payroll_payment'
          or tostring(existing.request_fingerprint or '') ~= requestFingerprint then
        return false, 'idempotency_conflict'
      end
      return true, {
        bankBefore = bankBefore, bankAfter = bankBefore,
        orgBefore = orgBefore, orgAfter = orgBefore,
        externalRef = tostring(existing.correlation_id or ''),
        outboxPersisted = true, replayed = true,
        license = tostring(playerRow.license or '')
      }
    end
    if orgBefore < salary then return false, 'insufficient_org_funds' end
    if bankBefore > 9007199254740991 - salary then return false, 'amount_overflow' end

    local bankAfter = bankBefore + salary
    local orgAfter = orgBefore - salary
    local externalRef = nextPayrollLedgerRef(membership.org_code, citizenid)
    local commonData = {
      channel = 'payroll',
      operation = 'pay_salary',
      org_id = tonumber(membership.org_id) or membership.org_id,
      org_code = tostring(membership.org_code),
      grade_level = tonumber(membership.grade_level) or 0,
      salary = salary,
      duty = asBool(membership.duty),
      require_duty = requireDuty == true
    }
    local playerOptions = {
      reason = 'payroll_salary', category = 'salary',
      source_resource = 'mz_core', source_type = 'payroll',
      sourceType = 'payroll', related_org_code = tostring(membership.org_code),
      external_ref = externalRef, counts_as_income = true, counts_as_expense = false,
      data = commonData
    }
    local orgOptions = {
      reason = 'payroll_salary_expense', category = 'salary_expense',
      source_resource = 'mz_core', source_type = 'payroll',
      sourceType = 'payroll', related_citizenid = tostring(citizenid),
      related_org_code = tostring(membership.org_code), external_ref = externalRef,
      counts_as_income = false, counts_as_expense = true, data = commonData
    }
    local playerMetadata = MZAccountService.NormalizeFinancialLedgerOptionsInternal(playerOptions, {})
    local orgMetadata = MZAccountService.NormalizeFinancialLedgerOptionsInternal(orgOptions, {})
    local correlationId = MZAccountService.GenerateFinancialTransactionRefInternal('mzacc-payroll')
    local idempotency = {
      sourceResource = 'mz_core', actorCitizenId = tostring(citizenid),
      key = idempotencyKey, operation = 'payroll_payment',
      fingerprint = requestFingerprint, correlationId = correlationId,
      resultJson = json.encode({ ok = true, correlationId = correlationId, replayed = false })
    }
    local outbox, outboxErr = MZAccountService.BuildFinancialOutboxInternal({
      correlationId = correlationId,
      idempotency = idempotency,
      eventType = 'payroll_payment',
      sourceCitizenId = citizenid,
      account = 'multi', amount = salary, fee = 0,
      reason = playerMetadata.reason, ledgerMetadata = playerMetadata,
      options = playerOptions,
      entries = {
        MZAccountService.BuildFinancialLedgerEntryInternal(
          1, nil, 'org', 'out', salary, orgBefore, orgAfter, orgMetadata
        ),
        MZAccountService.BuildFinancialLedgerEntryInternal(
          2, citizenid, 'bank', 'in', salary, bankBefore, bankAfter, playerMetadata
        )
      }
    })
    if outbox == false then return false, outboxErr end

    if not MZAccountRepository.transferPlayerBankAndOrg(
      citizenid, bankAfter, membership.org_id, orgAfter, outbox, idempotency
    ) then
      local replay = MZAccountRepository.getIdempotentOperation('mz_core', citizenid, idempotencyKey)
      if replay and tostring(replay.operation or '') == 'payroll_payment'
          and tostring(replay.request_fingerprint or '') == requestFingerprint then
        return true, {
          bankBefore = bankBefore, bankAfter = bankBefore,
          orgBefore = orgBefore, orgAfter = orgBefore,
          externalRef = tostring(replay.correlation_id or ''),
          outboxPersisted = true, replayed = true,
          license = tostring(playerRow.license or '')
        }
      end
      return false, 'database_error'
    end

    local online = MZPlayerService.getPlayerByCitizenId(citizenid)
    if online and online.money then online.money.bank = bankAfter end
    return true, {
      bankBefore = bankBefore, bankAfter = bankAfter,
      orgBefore = orgBefore, orgAfter = orgAfter,
      externalRef = externalRef, outboxPersisted = type(outbox) == 'table',
      playerMetadata = playerMetadata, orgMetadata = orgMetadata,
      license = tostring(playerRow.license or '')
    }
  end)
end

recordLegacyPayroll = function(citizenid, membership, salary, detail)
  recordPayrollLedger({
    citizenid = tostring(citizenid), license = detail.license,
    account = 'bank', amount = salary,
    balance_before = detail.bankBefore, balance_after = detail.bankAfter,
    direction = 'in', category = 'salary', reason = 'payroll_salary',
    source_resource = 'mz_core', source_type = 'payroll',
    counts_as_income = true, counts_as_expense = false,
    related_org_code = tostring(membership.org_code), external_ref = detail.externalRef
  })
  recordPayrollLedger({
    account = 'org', amount = salary,
    balance_before = detail.orgBefore, balance_after = detail.orgAfter,
    direction = 'out', category = 'salary_expense', reason = 'payroll_salary_expense',
    source_resource = 'mz_core', source_type = 'payroll',
    counts_as_income = false, counts_as_expense = true,
    related_citizenid = tostring(citizenid), related_org_code = tostring(membership.org_code),
    external_ref = detail.externalRef
  })
end

function MZPayrollService.payOnlinePlayers()
  local count = 0

  for _, player in pairs(MZCache.playersBySource or {}) do
    if player and player.citizenid then
      local ok = MZPayrollService.payCitizen(player.citizenid, 'payroll_tick')
      if ok then
        count = count + 1
      end
    end
  end

  return count
end

CreateThread(function()
  while true do
    local minutes = (Config.Payroll and Config.Payroll.intervalMinutes) or 30
    Wait(minutes * 60000)

    if Config.Payroll and Config.Payroll.enabled == false then
      goto continue
    end

    local ok, result = pcall(function()
      return MZPayrollService.payOnlinePlayers()
    end)

    if ok then
      print(('[mz_core] payroll tick completed (%s players paid)'):format(result or 0))
    else
      print(('[mz_core] payroll tick failed: %s'):format(result))
    end

    ::continue::
  end
end)

exports('PayCitizenSalary', function(citizenid, actor)
  return MZPayrollService.payCitizen(citizenid, actor)
end)

exports('RunPayrollTick', function()
  return MZPayrollService.payOnlinePlayers()
end)
