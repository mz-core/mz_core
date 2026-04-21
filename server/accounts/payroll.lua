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

local function getPlayerBankBalance(citizenid)
  local row = MySQL.single.await('SELECT bank FROM mz_player_accounts WHERE citizenid = ? LIMIT 1', { citizenid })
  if not row then
    return nil
  end

  return math.floor(tonumber(row.bank) or 0)
end

local function addBankMoney(citizenid, amount)
  local row = MySQL.single.await('SELECT * FROM mz_player_accounts WHERE citizenid = ? LIMIT 1', { citizenid })
  if not row then
    return false, 'account_not_found'
  end

  local newBank = math.floor((tonumber(row.bank) or 0) + amount)

  MySQL.update.await('UPDATE mz_player_accounts SET bank = ? WHERE citizenid = ?', {
    newBank, citizenid
  })

  local online = MZPlayerService.getPlayerByCitizenId(citizenid)
  if online and online.money then
    online.money.bank = newBank
  end

  return true, newBank
end

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

        local orgAccount = MySQL.single.await(
          'SELECT balance FROM mz_org_accounts WHERE org_id = ? LIMIT 1',
          { membership.org_id }
        )

        if orgAccount then
          local balance = tonumber(orgAccount.balance) or 0

          if balance >= salary then
            MySQL.update.await(
              'UPDATE mz_org_accounts SET balance = balance - ? WHERE org_id = ?',
              { salary, membership.org_id }
            )

            if bankBefore == nil then
              bankBefore = getPlayerBankBalance(citizenid)
            end
            local ok = addBankMoney(citizenid, salary)
            if ok then
              bankAfter = getPlayerBankBalance(citizenid)
              paid[#paid + 1] = {
                org = membership.org_code,
                amount = salary,
                source = 'org_account'
              }
            end
          end
        else
          skipped[#skipped + 1] = {
            org = membership.org_code,
            amount = salary,
            reason = 'org_account_missing'
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
