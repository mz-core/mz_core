# Contrato server-side de estados do jogador

Status: **Lote 2 implementado em 2026-08-04**  
Escopo: autoridade, normalização, leitura, mutação, transições, concorrência e persistência no servidor.  
Não inclui: state bags, detecção de dano/morte, aplicação física no ped, HUD novo, decay de status ou fluxo médico visual.

## 1. Arquitetura

`mz_core` continua com uma única cópia funcional do jogador: `MZCache.playersBySource[source].metadata`. O módulo `MZPlayerStateService` não duplica metadata; seu runtime guarda somente coordenação:

```lua
{
  citizenid = '...',
  sessionId = 123,
  revision = 0,
  dirty = {},
  dirtySince = nil,
  lastFlushAt = 0,
  unloading = false,
  lock = nil,
  lockedAt = nil,
  lockOperation = nil,
  lastCriticalTransitionId = nil,
  lastCriticalTransitionAt = nil
}
```

O runtime é criado depois que o player normalizado entra no cache. `citizenid` e `sessionId` impedem que um `source` reutilizado herde runtime de outra sessão. O repository existente continua sendo o único escritor de `mz_players.metadata`.

Fluxo de load:

```text
row do repository
-> decode explícito
-> normalização pura
-> cache com metadata válida
-> runtime da sessão
-> persistência imediata das correções, quando houver
-> conclusão do load
```

## 2. Configuração

Toda a política fica em `Config.PlayerStates`:

```lua
enabled = true

persistence = {
  flushIntervalMs = 30000,
  debounceMs = 5000,
  lockTimeoutMs = 5000,
  criticalImmediateSave = true
}

status = {
  hunger = { default = 100, min = 0, max = 100, writer = 'status' },
  thirst = { default = 100, min = 0, max = 100, writer = 'status' },
  stress = { default = 0, min = 0, max = 100, writer = 'status' },
  health = { default = 200, min = 0, max = 200, writer = 'medical' },
  armor = { default = 0, min = 0, max = 100, writer = 'armor' }
}

death = {
  default = 'alive',
  allowImmediateDeath = true,
  allowAdministrativeReviveFromDead = true,
  persistCriticalTransitions = true
}

authorization = {
  statusWriters = {},
    medicalWriters = { 'mz_admin' },
    armorWriters = { 'mz_admin' },
  administrativeWriters = { 'mz_admin' }
}
```

Listas vazias negam writers externos. O core chama funções internas com contexto privado e não depende das listas. `Config.Player.defaultMetadata` permanece por compatibilidade, mas é derivado dos defaults canônicos.

## 3. Modelo, invariantes e timestamps

Estado canônico persistido:

```text
alive | downed | dead | respawning
```

Derivações obrigatórias:

| `deathState` | `isdead` | `inlaststand` |
| --- | ---: | ---: |
| `alive` | false | false |
| `downed` | false | true |
| `dead` | true | false |
| `respawning` | true | false |

`respawning` continua aparecendo como morto para consumers legados até `CompletePlayerRespawn`. As flags legadas nunca são gravadas de forma independente.

Os campos `downedAt`, `deadAt`, `reviveAt`, `respawnStartedAt` e `respawnCompletedAt` são persistidos na metadata quando sua transição ocorre. São inteiros em epoch Unix, segundos, gerados pelo servidor; epoch não depende de timezone. Eles descrevem o episódio atual/mais recente e sobrevivem a reconnect. Não são aceitos do client nem pelo setter genérico.

`MarkPlayerDead` fixa health no mínimo configurado. `RevivePlayer` e `CompletePlayerRespawn` restauram o default configurado. `SetStatus('health', valor > 0)` é recusado em `dead`/`respawning`; reviver exige a transição própria.

Transições:

```text
alive -> downed
alive -> dead
downed -> dead
downed -> alive
dead -> respawning
respawning -> alive
dead -> alive (somente revive administrativo allowlisted)
```

Uma chamada cujo alvo já está no estado pedido retorna sucesso com `changed=false` e `code='already_in_state'`. Transições inválidas não alteram metadata nem revision.

## 4. Normalização

`MZPlayerStateNormalizer.normalize(metadata)` retorna:

```lua
normalizedMetadata, changed, corrections
```

`decodeAndNormalize(value)` acrescenta um quarto retorno, `decodeInvalid`. O normalizador:

- aceita `nil`, tabela vazia e tabela parcial;
- copia a entrada e preserva chaves desconhecidas;
- converte strings numéricas finitas;
- rejeita `NaN` e infinito;
- arredonda para baixo e aplica limites centrais;
- aceita booleanos legados boolean, `0/1` e strings conhecidas;
- deriva `deathState` dos legados quando ausente;
- dá precedência conservadora a `isdead=true` se ambos os legados forem true;
- sempre regenera os dois booleanos a partir do canônico;
- valida timestamps conhecidos;
- é idempotente.

JSON inválido ou valor decodificado que não seja tabela usa defaults seguros, gera log sem o conteúdo bruto e é marcado para persistência.

## 5. Retornos

Todas as APIs canônicas retornam dois valores:

```lua
true, {
  revision = 17,
  state = snapshot,
  changed = true,
  code = 'opcional'
}
```

ou:

```lua
false, {
  code = 'invalid_transition',
  message = 'The requested death-state transition is not allowed.'
}
```

Leituras especializadas retornam payload mínimo no segundo valor. Snapshots são cópias; não expõem metadata completa nem referência mutável.

Códigos implementados:

```text
player_not_found
player_not_loaded
invalid_status
invalid_value
invalid_transition
already_in_state
not_authorized
unloading
lock_timeout
persistence_failed
persistence_pending
feature_disabled
internal_error
protected_metadata
invalid_action
```

## 6. APIs internas

| Função | Parâmetros | Retorno/efeito |
| --- | --- | --- |
| `getState` | `source` | snapshot sanitizado e revision |
| `getStatus` | `source, statusName` | valor de status registrado |
| `getDeathState` | `source` | estado e flags derivadas |
| `setStatus` | `source, name, value, context` | set com clamp |
| `addStatus` | `source, name, amount, context` | soma amount não negativo e aplica clamp |
| `removeStatus` | `source, name, amount, context` | subtrai amount não negativo e aplica clamp |
| `markDowned` | `source, context` | transição para downed |
| `markDead` | `source, context` | transição para dead |
| `revive` | `source, context` | downed→alive; dead→alive somente admin |
| `beginRespawn` | `source, context` | dead→respawning |
| `completeRespawn` | `source, context` | respawning→alive |
| `canPerformAction` | `source, action` | `{ allowed, deathState, revision }` |
| `flush` | `source, reason, force, context` | flush dirty com debounce opcional |
| `initializePlayer` | `source, corrections` | cria runtime e salva correções |
| `beginUnload` | `source, reason` | bloqueia mutações e força flush |
| `finalizeUnload` | `source` | remove runtime |

`applyBridgeMetadataPatch` e `setGenericMetadata` são adapters internos de compatibilidade. Não são exports canônicos.

## 7. Exports server-side

Exports de leitura não exigem allowlist:

```text
GetPlayerState
GetStatus
GetDeathState
CanPlayerPerformAction
```

Exports de escrita:

| Export | Categoria de autorização | Idempotência | Persistência |
| --- | --- | --- | --- |
| `SetStatus` | conforme status: status/medical/armor | valor igual não incrementa revision | agrupada |
| `AddStatus` | conforme status | clamp sem mudança não incrementa | agrupada |
| `RemoveStatus` | conforme status | clamp sem mudança não incrementa | agrupada |
| `MarkPlayerDowned` | medical | sim | crítica |
| `MarkPlayerDead` | medical | sim | crítica |
| `RevivePlayer` | medical ou administrative | sim | crítica |
| `BeginPlayerRespawn` | medical | sim | crítica |
| `CompletePlayerRespawn` | medical | sim | crítica |
| `FlushPlayerState` | qualquer categoria writer explícita | dirty vazio é no-op | imediata quando executada |

Exemplo:

```lua
local ok, result = exports['mz_core']:RemoveStatus(playerSource, 'thirst', 20, {
  reason = 'item_consumed',
  actorSource = playerSource,
  item = 'water'
})

if not ok then
  print(result.code, result.message)
end
```

O serviço substitui a origem declarada pelo caller por `GetInvokingResource()` no wrapper do export. `internal=true`, timestamps ou nomes de resource enviados pelo caller não concedem privilégio.

## 8. Autorização

`IsResourceAuthorized` é central e usa correspondência exata nas listas. Não existe wildcard nem confiança por prefixo `mz_`. Categorias:

- `status`: hunger, thirst, stress;
- `medical`: health e transições médicas;
- `armor`: armor;
- `administrative`: revive privilegiado dead→alive;
- `persistence`: união das quatro listas para flush externo.

Eventos client→server públicos para mutação de estado não foram criados neste lote. Assim, uma allowlist de resource nunca autoriza automaticamente um client.

## 9. Revision, dirty tracking e persistência

Revision começa em zero a cada sessão. Cada mutação válida do estado canônico incrementa uma vez, depois que a metadata já está coerente. No-op e rejeição não incrementam. Revision é runtime e não cria coluna no banco.

Status alterado marca seu campo em `dirty` e define `dirtySince`. Uma thread global acorda a cada `flushIntervalMs`, seleciona somente runtimes dirty, não unloading, e respeita `debounceMs`. Não há thread por player. Dirty só é limpo depois que `MZPlayerRepository.updateMetadata` confirma sucesso.

Transições de morte e correções de load usam persistência crítica quando habilitada. Se o banco falha, a decisão é manter o estado canônico em memória, manter dirty para retry e retornar `persistence_pending`; a transição não é revertida. Isso evita desfazer uma transição médica/de morte já observada em memória, sem comunicar falso sucesso permanente.

O setter genérico não sensível preserva seu comportamento write-through, agora sob o mesmo lock. A bridge aplica uma tabela de metadata em uma mutação/flush, em vez de N gravações.

## 10. Concorrência, unload e resource stop

Existe um mutex cooperativo por player. O lock é adquirido antes de ler e escrever metadata e permanece até a persistência associada terminar. Espera excedendo `lockTimeoutMs` retorna `lock_timeout`; o serviço não rouba um lock ainda ativo. `xpcall` e liberação central garantem release em erro.

No unload:

1. `unloading=true` é definido;
2. novas mutações são recusadas;
3. o fluxo espera o lock corrente com timeout;
4. força flush;
5. registra falha sem apagar dirty antes da remoção final;
6. fecha sessão/remove cache no fluxo existente;
7. remove runtime.

No stop do próprio core, `beginShutdown` recusa novas operações, todos os sources carregados passam por flush/unload, um resultado agregado é emitido e runtimes são limpos. Não há espera adicional longa nem promessa contra encerramento abrupto do processo.

## 11. Consulta de ações

As ações registradas são:

```text
inventory.open, inventory.use, inventory.move, weapon.use, vehicle.drive,
bank.use, garage.use, phone.use, property.use, emote.use
```

Neste lote, todas são permitidas em `alive` e bloqueadas em `downed`, `dead` e `respawning`. A API existe para os consumers; a integração deles pertence aos lotes seguintes. Ações arbitrárias retornam `invalid_action`.

## 12. Segurança e compatibilidade

`SetMetadataValue` continua disponível para chaves não sensíveis. Estas chaves são bloqueadas no caminho genérico:

```text
hunger, thirst, stress, health, armor, deathState, isdead, inlaststand,
downedAt, deadAt, reviveAt, respawnStartedAt, respawnCompletedAt
```

O erro `protected_metadata` informa a API específica. Tentativas são auditadas. Não existe bypass público.

A bridge QB mantém `GetMetaData`, `SetMetaData` e `SetPlayerData`:

- status registrado é traduzido para `SetStatus`, com clamp e allowlist;
- metadata comum usa setter serializado;
- `SetPlayerData('metadata', table)` usa patch único;
- flags/timestamps de morte são negados;
- `SetMetaData('isdead', false)` nunca revive.

Consumers atuais de metadata não sensível, como `mz_creator` (`appearance`, `appearance_updated_at`, `character_created`), continuam no contrato legado. No Lote 3, heal, revive e armor de `mz_admin` passam pelo estado canônico e a aplicação física ocorre exclusivamente no sincronizador client do core; os eventos físicos legados do admin foram removidos. Nenhum consumer local legítimo escrevia as chaves sensíveis pelo setter; o `qb_probe` usa chaves de diagnóstico não sensíveis.

## 13. Logs

Eventos relevantes usam `MZLogService.createDetailed` e payload sanitizado: metadata inválida/corrigida, autorização negada, setter protegido, transição/rejeição de morte, falha de persistência, timeout de lock, falha final e resumo do stop. O payload inclui apenas campos úteis como auditId, source, citizenid, operação, valores pontuais, estados, motivo, resource, actorSource, revision, resultado, erro e timestamp. Metadata completa não é registrada. Mudanças comuns de fome/sede não geram log individual.

## 14. Limitações e Lote 3

- Não há state bags neste lote.
- O client e o ped ainda não aplicam health/armor nem deathState.
- Não há detecção ou reconciliação física de dano/morte.
- Consumers ainda não chamam `CanPlayerPerformAction`.
- Não há decay de fome/sede/stress nem efeitos de item.
- Validação em FiveM/OneSync, reconnect e restart real permanece pendente.

Próximo lote: **Lote 3 — sincronização client, state bags, aplicação física de health/armor, detecção e reconciliação.**

## 15. Extensão implementada no Lote 3

O lote citado acima foi implementado sem substituir a autoridade do Lote 2. `player.metadata` continua sendo a truth persistida e o runtime continua controlando revision, lock, dirty e sessão. A extensão adiciona:

- `server/player/state_sync.lua` como emissor único de snapshot e writer único de state bags;
- token opaco de sessão e token rotativo de observação no runtime;
- `applyObservedVitals`, que aceita internamente somente reduções de health/armor e incrementa uma revision atômica;
- sequence, janela/rate limit, resync e candidatos fatais no runtime existente;
- sync imediato após mutation relevante, independente do debounce de persistência;
- limpeza de bags antes de remover cache/runtime no unload.

### Correção de coerência demonstrada

O contrato anterior permitia `downed` com health 200 e estados não-alive com armor positiva. Isso era incompatível com a aplicação física exigida. Normalizer e transições agora derivam:

- downed: health `death.downedHealth` (padrão 1), armor 0;
- dead/respawning: health 0, armor 0.

Não há nova authority ou transição: os vitais apenas passam a ser coerentes com o death state autoritativo.

### Eventos adicionados

- `mz_core:client:playerStateSync`: server → client, DTO reduzido;
- `mz_core:server:requestPlayerStateSync`: client → server read-only, zero argumentos, cooldown 5 s;
- `mz_core:server:reportVitalCandidate`: client → server observation, target implícito, schema fechado, token/session/sequence/revision/rate limit.

O report nunca concede health/armor, revive, inicia/conclui respawn ou escolhe deathState. Fatal usa confirmação server-side quando disponível; se indisponível exige múltiplas observações configuradas. Contrato completo: `PLAYER_STATE_CLIENT_SYNC.md`.

### Harnesses adicionados

- `tests/player_state_sync_harness.lua`;
- `tests/player_state_client_harness.lua`;
- `tests/player_state_integration_contract_harness.lua`.

As limitações da seção 14 ficam substituídas pelo contrato do Lote 3 e pelas pendências runtime declaradas em `PLAYER_STATE_RUNTIME_CHECKLIST.md`.

## 16. Extensão implementada no Lote 4

`mz_status` é o único writer externo de sobrevivência. As allowlists são `statusWriters={'mz_status'}`, `damageWriters={'mz_status'}` e `healingWriters={'mz_status'}`; medical/armor/admin continuam restritas a `mz_admin`.

Novos exports:

- `ApplyStatusPatch(source, patch, context)`: somente deltas finitos de hunger/thirst/stress, no máximo três campos e uma seção serializada/revision/dirty/sync;
- `ApplyPlayerHealthDamage(source, amount, context)`: somente redução em alive; fatal aplica downed/dead e health/flags/timestamp atomicamente; pode retornar `persistence_pending` com `changed=true`;
- `ApplyPlayerHealing(source, amount, context)`: somente aumento em alive, clamp no máximo, sem revive ou mudança de death state.

Dano e cura têm allowlists distintas. `mz_core:server:playerVitalChangedInternal` é exclusivamente server-side e é emitido depois de liberar o lock, evitando reentrada quando `mz_status` adiciona stress. Mudanças comuns continuam em dirty/debounce; somente fatal usa flush crítico.

O inventário valida `inventory.use` também no servidor. O hook pós-commit pode falhar de forma observável e então uma transação compensatória restaura amount ou row exata antes de liberar o lock. `persistence_pending` funcional não devolve item. Contrato completo: `../../mz_status/docs/PLAYER_STATUS_SURVIVAL.md`.

## 17. Extensão implementada no Lote 5

O core persiste `downedExpiresAt` e `respawnAvailableAt` junto à metadata de morte. Os campos só existem nos estados compatíveis, são limitados a epoch futuro e a primeira atribuição vence. `SetPlayerDeathDeadline` é restrito a `mz_medical`; reconnect e restart não renovam prazo.

Transições críticas agora aceitam `expectedRevision`, impedindo revive ou conclusão de respawn sobre snapshot obsoleto. `RevivePlayer` e `CompletePlayerRespawn` recebem health/armor definidos no servidor e continuam sendo o único caminho para a aplicação física no client do core. `AbortPlayerRespawn` recupera operações órfãs para `dead` sem criar novo episódio.

`SpawnPlayerForMedical` aceita somente `mz_medical`, exige estado canônico `respawning`, payload fechado e coordenadas server-owned; o modelo vem da aparência canônica. O callback do `spawnmanager` emite um acknowledgment local vinculado à operação.

O inventário oficial adiciona reserva médica sob lock: guarda stack/instância, metadata, slot, citizen ID, sessão e deadline. Commit e cancel são idempotentes; rollback restaura no slot original quando seguro ou em slot livre sem sobrescrever dados concorrentes. Contrato completo: `../../mz_medical/docs/PLAYER_MEDICAL_FLOW.md`.
