# Integração com Player State

Este é o contrato curto para novos resources. A autoridade é sempre o servidor do `mz_core`; client, NUI e state bags são projeções e candidatos, nunca a verdade.

## Ler estado no servidor

```lua
local ok, result = exports['mz_core']:GetPlayerState(source)
if not ok then return false, result.code end
local deathState = result.state.deathState
local health = result.state.status.health
local revision = result.revision
```

Para identidade/cache, use `GetPlayerSnapshot(source)` ou `GetPlayerByCitizenIdSnapshot(citizenid)`. Os legados `GetPlayer` e `GetPlayerByCitizenId` devolvem objeto mutável, permanecem apenas por compatibilidade e emitem warning uma vez por resource.

Schedulers server-side allowlisted que precisam invalidar runtime por reconnect usam `GetPlayerStateRuntimeIdentity(source)`. Esse export retorna somente `sessionId` e revision, sem tokens, e não é API client.

## Autorizar uma ação

Todo endpoint server-side que produz efeito deve verificar a ação específica:

```lua
local ok, decision = exports['mz_core']:CanPlayerPerformAction(source, 'inventory.use')
if not ok or decision.allowed ~= true then
  return false, 'player_state_blocked'
end
```

Ações registradas: `inventory.open/use/move/drop/pickup`, `storage.use`, `weapon.use/fire`, `vehicle.enter/drive`, `bank.use`, `garage.use`, `phone.use`, `property.use`, `emote.use`, `command.use`, `shop.use`, `craft.use` e `trade.use`. Cleanup, cancelamento e rollback devem ter endpoint separado e estreito; não reutilize um bypass para iniciar efeitos.

## Alterar status, dano e cura

O resource precisa estar na allowlist da operação em `Config.PlayerStates.authorization`.

```lua
exports['mz_core']:SetStatus(source, 'stress', 25, { reason = 'server_rule' })
exports['mz_core']:ApplyStatusPatch(source, { hunger = 80, thirst = 70 }, { reason = 'server_rule' })
exports['mz_core']:ApplyPlayerHealthDamage(source, 5, { reason = 'hazard' })
exports['mz_core']:ApplyPlayerHealing(source, 15, { reason = 'bandage' })
```

Valores, amount, target e efeito devem ser calculados no servidor. Nunca aceite do client um patch de metadata, dano, cura, fee ou estado de morte.

## Transições médicas

Downed/dead/revive/respawn são solicitados por APIs oficiais (`MarkPlayerDowned`, `MarkPlayerDead`, `RevivePlayer`, `BeginPlayerRespawn`, `CompletePlayerRespawn`, `AbortPlayerRespawn`). Para atendimento normal, use o fluxo fechado do `mz_medical`; o client envia somente a intenção, token de operação e revision exigidos pelo contrato. Não existe evento público genérico de revive.

## Client e state bags

```lua
local snapshot = exports['mz_core']:GetLocalPlayerState()
local canUse = exports['mz_core']:CanLocalPlayerPerformAction('phone.use')

AddStateBagChangeHandler('mz:stateRevision', nil, function(bagName, _, revision)
  -- Leia os demais bags depois do commit marker revision.
end)
```

Bags canônicos: `mz:loaded`, `mz:stateRevision`, `mz:deathState`, `mz:isDead`, `mz:isDowned`, `mz:isRespawning`, `mz:inventoryBlocked`, `mz:weaponBlocked` e `mz:interactionBlocked`. Não escreva esses bags no client. A decisão final continua server-side.

## APIs proibidas fora do core físico

- `SetEntityHealth`, `SetPedArmour` e `NetworkResurrectLocalPlayer` para sincronizar vitais;
- escrita direta em `player.metadata` sensível;
- SQL de player state fora do repositório do core;
- confiar em death booleans, target, distância, revision ou token vindos do client sem validação;
- mutar o retorno legado de `GetPlayer`;
- criar loop server-side por jogador ou flush por tick.

## Erros comuns

`player_not_loaded`, `invalid_state`, `player_state_blocked`, `not_authorized`, `invalid_value`, `revision_mismatch`, `session_mismatch`, `stale_session`, `rate_limited`, `persistence_pending`, `operation_in_progress`, `operation_not_found`, `target_too_far`, `inventory_consequence_failed`.

`persistence_pending` significa efeito aplicado na memória com persistência pendente: não repita cegamente. Consulte a operação/idempotency key ou acione recovery.

## Checklist de novo resource

1. Defina uma ação semântica e registre-a no core.
2. Valide `source` implícito, schema fechado, tipos, limites e rate limit no servidor.
3. Valide estado, sessão/revision, target, bucket e distância quando aplicáveis.
4. Use snapshot read-only e APIs canônicas de mutation.
5. Separe start/complete de cancel/rollback.
6. Use operationId idempotente para consequência econômica/inventário.
7. Registre eventos estruturados sem tokens ou metadata.
8. Adicione harness de autorização, replay, source reutilizado e falha intermediária.
