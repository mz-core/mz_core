local function expect(condition, message)
  if not condition then error(message, 2) end
end

dofile('config.lua')

json = {
  decode = function(value)
    if value == '{invalid' then error('invalid json') end
    if value == '[]' then return {} end
    return nil
  end
}

dofile('server/player/state_normalizer.lua')

local function normalize(value)
  return MZPlayerStateNormalizer.normalize(value)
end

local metadata, changed = normalize(nil)
expect(changed == true and metadata.hunger == 100 and metadata.deathState == 'alive', 'nil nao recebeu defaults')

metadata, changed = normalize({})
expect(changed == true and metadata.thirst == 100 and metadata.health == 200, 'tabela vazia nao recebeu defaults')

metadata, changed = normalize({ hunger = 50 })
expect(changed == true and metadata.armor == 0, 'campos ausentes nao foram completados')

metadata = normalize({ hunger = '85', thirst = '61', stress = '4', health = '199', armor = '20' })
expect(metadata.hunger == 85 and metadata.health == 199 and type(metadata.hunger) == 'number', 'strings numericas nao foram convertidas')

metadata = normalize({ hunger = -5 })
expect(metadata.hunger == 0, 'clamp inferior falhou')

metadata = normalize({ thirst = 500 })
expect(metadata.thirst == 100, 'clamp superior falhou')

metadata = normalize({ stress = 0 / 0 })
expect(metadata.stress == 0, 'NaN nao foi rejeitado')

metadata = normalize({ armor = 1 / 0 })
expect(metadata.armor == 0, 'infinito nao foi rejeitado')

metadata = normalize({ deathState = 'unknown', isdead = false, inlaststand = false })
expect(metadata.deathState == 'alive', 'estado de morte desconhecido nao foi normalizado')

metadata = normalize({ isdead = true })
expect(metadata.deathState == 'dead' and metadata.isdead == true and metadata.inlaststand == false, 'isdead legado nao foi derivado')

metadata = normalize({ inlaststand = true })
expect(metadata.deathState == 'downed' and metadata.isdead == false and metadata.inlaststand == true, 'inlaststand legado nao foi derivado')
expect(metadata.health == 1 and metadata.armor == 0, 'downed nao normalizou vitais coerentes')

local conflicted, conflictChanged, conflictCorrections = normalize({ isdead = true, inlaststand = true })
expect(conflictChanged == true and conflicted.deathState == 'dead' and conflicted.inlaststand == false, 'precedencia de conflito legado falhou')
local foundConflict = false
for _, correction in ipairs(conflictCorrections) do
  if correction.reason == 'legacy_conflict_isdead_precedence' then foundConflict = true end
end
expect(foundConflict, 'conflito legado nao foi registrado')

metadata = normalize({ customDomain = { keep = 'yes' } })
expect(metadata.customDomain.keep == 'yes', 'metadata desconhecida foi removida')

local valid = {
  hunger = 100, thirst = 100, stress = 0, health = 200, armor = 0,
  deathState = 'alive', isdead = false, inlaststand = false,
  custom = 'preserved'
}
local first, firstChanged = normalize(valid)
expect(firstChanged == false, 'metadata valida foi marcada como alterada')
local second, secondChanged, secondCorrections = normalize(first)
expect(secondChanged == false and #secondCorrections == 0, 'normalizacao nao e idempotente')

local decoded, decodedChanged, decodedCorrections, invalid = MZPlayerStateNormalizer.decodeAndNormalize('{invalid')
expect(invalid == true and decodedChanged == true and decoded.deathState == 'alive', 'JSON invalido nao usou defaults seguros')
expect(decodedCorrections[1].reason == 'invalid_json_or_type', 'JSON invalido nao foi registrado')

metadata = normalize({
  hunger = 100, thirst = 100, stress = 0, health = 200, armor = 0,
  deathState = 'RESPAWNING', isdead = true, inlaststand = false,
  deadAt = '1700000000'
})
expect(metadata.deathState == 'respawning' and metadata.isdead == true, 'respawning nao manteve flags documentadas')
expect(metadata.health == 0 and metadata.armor == 0, 'respawning nao normalizou vitais bloqueados')
expect(metadata.deadAt == 1700000000, 'timestamp string nao foi normalizado')

metadata = normalize({
  deathState = 'downed', isdead = false, inlaststand = true,
  downedExpiresAt = '1700000300', respawnAvailableAt = 1700000600
})
expect(metadata.downedExpiresAt == 1700000300 and metadata.respawnAvailableAt == nil,
  'normalizer nao preservou somente deadline compativel com downed')
metadata = normalize({
  deathState = 'dead', isdead = true, inlaststand = false,
  downedExpiresAt = 1700000300, respawnAvailableAt = '1700000600'
})
expect(metadata.downedExpiresAt == nil and metadata.respawnAvailableAt == 1700000600,
  'normalizer nao preservou somente deadline compativel com dead')
metadata = normalize({
  deathState = 'alive', isdead = false, inlaststand = false,
  downedExpiresAt = 1700000300, respawnAvailableAt = 1700000600
})
expect(metadata.downedExpiresAt == nil and metadata.respawnAvailableAt == nil,
  'alive reteve deadlines medicos obsoletos')

print('player_state_normalizer_harness: ok')
