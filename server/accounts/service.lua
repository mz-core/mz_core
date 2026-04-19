MZAccountService = {}

local function normalizeMoneyType(moneyType)
  return tostring(moneyType or ''):lower()
end

local function normalizeAccountActor(source)
  if source == nil then
    return {
      type = 'system',
      id = 'system'
    }
  end

  if tonumber(source) == 0 then
    return {
      type = 'console',
      id = 'console'
    }
  end

  local player = MZPlayerService.getPlayer(source)
  if player and player.citizenid then
    return {
      type = 'player',
      id = tostring(player.citizenid),
      source = source
    }
  end

  return {
    type = 'source',
    id = tostring(source)
  }
end

local function logMoneyChange(action, player, moneyType, beforeAmount, afterAmount, delta, options)
  if not MZLogService or not player then
    return
  end

  options = options or {}

  MZLogService.createDetailed('accounts', action, {
    actor = options.actor or normalizeAccountActor(options.actorSource),
    target = {
      type = 'player_account',
      id = tostring(player.citizenid)
    },
    context = {
      citizenid = tostring(player.citizenid),
      money_type = moneyType
    },
    before = {
      amount = math.floor(tonumber(beforeAmount) or 0)
    },
    after = {
      amount = math.floor(tonumber(afterAmount) or 0)
    },
    meta = {
      delta = math.floor(tonumber(delta) or 0),
      reason = options.reason,
      source_type = options.sourceType,
      source_ref = options.sourceRef,
      extra = options.meta or {}
    }
  })
end

function MZAccountService.getMoney(source)
  local player = MZPlayerService.getPlayer(source)
  if not player then return nil end
  return player.money
end

function MZAccountService.setMoney(source, moneyType, amount, options)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, 'player_not_loaded' end

  moneyType = normalizeMoneyType(moneyType)
  if moneyType == '' then
    return false, 'invalid_money_type'
  end

  if type(amount) ~= 'number' or amount < 0 then
    return false, 'invalid_amount'
  end

  local nextAmount = math.floor(amount)
  local currentAmount = math.floor(tonumber((player.money or {})[moneyType]) or 0)

  local ok = MZAccountRepository.updatePlayerMoney(player.citizenid, moneyType, nextAmount)
  if not ok then return false, 'invalid_money_type' end

  player.money[moneyType] = nextAmount

  logMoneyChange('set_money', player, moneyType, currentAmount, nextAmount, nextAmount - currentAmount, options)

  return true
end

function MZAccountService.addMoney(source, moneyType, amount, options)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, 'player_not_loaded' end

  moneyType = normalizeMoneyType(moneyType)
  if moneyType == '' then
    return false, 'invalid_money_type'
  end

  if type(amount) ~= 'number' or amount <= 0 then return false, 'invalid_amount' end

  local value = math.floor(amount)
  local current = math.floor(tonumber((player.money or {})[moneyType]) or 0)

  options = options or {}
  options.reason = options.reason or 'add_money'

  local ok, err = MZAccountService.setMoney(source, moneyType, current + value, options)
  if not ok then
    return false, err
  end

  return true
end

function MZAccountService.removeMoney(source, moneyType, amount, options)
  local player = MZPlayerService.getPlayer(source)
  if not player then return false, 'player_not_loaded' end

  moneyType = normalizeMoneyType(moneyType)
  if moneyType == '' then
    return false, 'invalid_money_type'
  end

  if type(amount) ~= 'number' or amount <= 0 then return false, 'invalid_amount' end

  local value = math.floor(amount)
  local current = math.floor(tonumber((player.money or {})[moneyType]) or 0)

  if current < value then return false, 'not_enough_money' end

  options = options or {}
  options.reason = options.reason or 'remove_money'

  local ok, err = MZAccountService.setMoney(source, moneyType, current - value, options)
  if not ok then
    return false, err
  end

  return true
end