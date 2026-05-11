-- Funções de deduplicação adicionadas para corrigir duplicação de veículos persistentes
-- Este arquivo contém as correções para o problema onde múltiplos veículos com a mesma placa
-- apareciam quando o jogador saia e reentrava no servidor.

local function normalizePlate(plate)
  return tostring(plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
end

local function safeDoesEntityExist(entity)
  if not entity or entity == 0 then
    return false
  end

  if type(DoesEntityExist) ~= 'function' then
    return true
  end

  local ok, exists = pcall(DoesEntityExist, entity)
  if not ok then
    return false
  end

  return exists == true
end

local function readEntityPlate(entity)
  if not safeDoesEntityExist(entity) then
    return ''
  end

  local state = Entity(entity).state
  if state and state.mz_plate then
    local statePlate = normalizePlate(state.mz_plate)
    if statePlate ~= '' then
      return statePlate
    end
  end

  local ok, plate = pcall(GetVehicleNumberPlateText, entity)
  if ok then
    return normalizePlate(plate)
  end

  return ''
end

-- CORREÇÃO 1: Buscar TODOS os veículos com a mesma placa (não apenas o primeiro)
local function findAllVehiclesByPlate(plate)
  plate = normalizePlate(plate)
  if plate == '' or type(GetAllVehicles) ~= 'function' then
    return {}
  end

  local ok, vehicles = pcall(GetAllVehicles)
  if not ok or type(vehicles) ~= 'table' then
    return {}
  end

  local found = {}
  for _, entity in ipairs(vehicles) do
    if safeDoesEntityExist(entity) and readEntityPlate(entity) == plate then
      found[#found + 1] = entity
    end
  end

  return found
end

-- CORREÇÃO 2: Verificar se veículo tem jogador dentro
local function hasDriverOrPassengers(entity)
  if not safeDoesEntityExist(entity) then
    return false
  end

  if type(GetVehicleNumberOfPassengers) == 'function' then
    local ok, passengers = pcall(GetVehicleNumberOfPassengers, entity)
    if ok and passengers and passengers > 0 then
      return true
    end
  end

  if type(GetPedInVehicleSeat) == 'function' then
    local ok, driver = pcall(GetPedInVehicleSeat, entity, -1)
    if ok and driver and driver ~= 0 then
      return true
    end
  end

  return false
end

-- CORREÇÃO 3: Deduplicar múltiplos veículos com mesma placa
local function deduplicateVehiclesByPlate(plate, keepEntity)
  plate = normalizePlate(plate)
  if plate == '' then
    return 0
  end

  local allEntities = findAllVehiclesByPlate(plate)
  if #allEntities <= 1 then
    return 0
  end

  local entityToKeep = nil
  if keepEntity and safeDoesEntityExist(keepEntity) and readEntityPlate(keepEntity) == plate then
    entityToKeep = keepEntity
  else
    -- Preferir veículo com jogador
    for _, entity in ipairs(allEntities) do
      if hasDriverOrPassengers(entity) then
        entityToKeep = entity
        break
      end
    end

    -- Se nenhum tem jogador, preferir o que tem mz_persistent no statebag
    if not entityToKeep then
      for _, entity in ipairs(allEntities) do
        local state = Entity(entity).state
        if state and state.mz_persistent == true then
          entityToKeep = entity
          break
        end
      end
    end

    -- Fallback: primeiro da lista
    if not entityToKeep then
      entityToKeep = allEntities[1]
    end
  end

  local deleted = 0
  for _, entity in ipairs(allEntities) do
    if entity ~= entityToKeep then
      if hasDriverOrPassengers(entity) then
        print(('[mz_vehicle_world_dedup] skip delete duplicate plate=%s reason=has_driver'):format(plate))
      else
        if type(DeleteEntity) == 'function' then
          pcall(DeleteEntity, entity)
          deleted = deleted + 1
          print(('[mz_vehicle_world_dedup] delete duplicate plate=%s count=%d'):format(plate, deleted))
        end
      end
    end
  end

  if deleted > 0 then
    print(('[mz_vehicle_world_dedup] deduplicate plate=%s kept=%s deleted=%d total=%d'):format(plate, tostring(entityToKeep), deleted, #allEntities))
  end

  return deleted
end

return {
  findAllVehiclesByPlate = findAllVehiclesByPlate,
  hasDriverOrPassengers = hasDriverOrPassengers,
  deduplicateVehiclesByPlate = deduplicateVehiclesByPlate,
  normalizePlate = normalizePlate,
  safeDoesEntityExist = safeDoesEntityExist,
  readEntityPlate = readEntityPlate
}
