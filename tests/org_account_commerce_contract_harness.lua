local function read(path)
  local file = assert(io.open(path, 'rb'))
  local content = file:read('*a')
  file:close()
  return content
end
local function expect(condition, message) if not condition then error(message, 2) end end

local prepare = read('mz_core/server/prepare.lua')
local repository = read('mz_core/server/accounts/repository.lua')
local service = read('mz_core/server/accounts/org_accounts.lua')

expect(prepare:find('CREATE TABLE IF NOT EXISTS mz_org_account_operations', 1, true),
  'commerce operation schema missing')
expect(prepare:find('uq_mz_org_acc_op_scope', 1, true), 'operation idempotency scope missing')
expect(prepare:find('uq_mz_org_acc_op_reversal', 1, true), 'single-refund constraint missing')
expect(repository:find('applyOrgAccountOperation', 1, true), 'atomic commerce repository method missing')
expect(repository:find("account_operation.status = 'applied'", 1, true),
  'receipt state not persisted atomically')
expect(service:find("resources = { mz_org_activities = true }", 1, true),
  'facility purchase caller allowlist missing')
expect(service:find("capability = 'facility.purchase'", 1, true),
  'facility purchase capability missing')
expect(service:find("exports('SpendOrgAccount'", 1, true), 'spend export missing')
expect(service:find("exports('RefundOrgAccount'", 1, true), 'refund export missing')
expect(not service:find("MZOrgAccountService.removeBalance(orgCode, amount, source", 1, true),
  'commerce must not reuse administrative removal')

print('[mz_core][test] org account commerce contract harness passed')
