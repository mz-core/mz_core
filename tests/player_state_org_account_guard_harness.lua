local function expect(condition, message)
  if not condition then error('[player_state_org_account_guard_harness] ' .. message, 2) end
end

local currentState = 'alive'
local unavailable = false

MZPlayerStateService = {
  canPerformAction = function(_, action)
    expect(action == 'bank.use', 'acao canonica incorreta')
    if unavailable then return false, { code = 'state_unavailable' } end
    return true, { allowed = currentState == 'alive', deathState = currentState }
  end
}
MZPlayerService = { getPlayer = function() return nil end }
MZLogService = nil
exports = function() end

dofile('server/accounts/org_accounts.lua')

local function exercise(state, expected)
  currentState = state
  local okDeposit, depositReason = MZOrgAccountService.deposit(17, 'police', 100, 'harness')
  local okWithdraw, withdrawReason = MZOrgAccountService.withdraw(17, 'police', 100, 'harness')
  expect(okDeposit == false and depositReason == expected, state .. ' deposit retornou ' .. tostring(depositReason))
  expect(okWithdraw == false and withdrawReason == expected, state .. ' withdraw retornou ' .. tostring(withdrawReason))
end

exercise('alive', 'player_not_loaded')
exercise('downed', 'player_state_blocked')
exercise('dead', 'player_state_blocked')
exercise('respawning', 'player_state_blocked')
exercise('alive', 'player_not_loaded')

unavailable = true
exercise('alive', 'player_state_blocked')

print('[player_state_org_account_guard_harness] PASS cases=12 fail_closed=2')
