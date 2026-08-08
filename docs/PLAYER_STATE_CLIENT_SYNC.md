# Player State — contrato de sincronização client (Lote 3)

## Arquitetura

`player.metadata` no cache server-side continua sendo a única verdade persistida. O runtime de `state_service.lua` guarda revision, lock, dirty fields, token opaco de sessão e controles operacionais dos eventos client. `state_sync.lua` é o único emissor do snapshot canônico e o único writer das state bags. `client/player_state.lua` mantém uma cópia defensiva, aplica os valores no ped local e reporta somente observações não confiáveis.

A persistência e a sincronização são independentes: mudanças comuns sincronizam imediatamente e persistem pelo debounce do Lote 2; transições críticas sincronizam imediatamente e continuam usando flush crítico.

## Payload server → client

Evento: `mz_core:client:playerStateSync` (somente server → client).

```lua
{
  revision = 12,
  sessionToken = "opaque-session-token",
  observationToken = "opaque-observation-token",
  status = {
    hunger = 92,
    thirst = 81,
    stress = 4,
    health = 175,
    armor = 50
  },
  death = {
    state = "alive",
    isdead = false,
    inlaststand = false
  },
  permissions = {
    inventoryBlocked = false,
    weaponBlocked = false,
    interactionBlocked = false
  },
  reason = {
    code = "player_loaded",
    serverTime = 0
  },
  forcePhysicalApply = true,
  sessionReset = true
}
```

O DTO não contém citizenid, metadata completa, timestamps de morte, dinheiro, organizações ou dados de outros módulos. Todas as tabelas retornadas/emitted são snapshots, não referências ao cache.

### Revision e sessão

- revision menor que a local: descartada;
- mesma revision sem `forcePhysicalApply`: idempotente e ignorada fisicamente;
- mesma revision com `forcePhysicalApply`: reaplica no ped sem criar estado lógico novo;
- revision maior: substitui o espelho e cancela qualquer aplicação anterior pela geração local;
- token de sessão diferente: descartado, salvo a troca explicitamente aberta por `playerLoaded` e vinculada ao token esperado;
- `observationToken` gira em resync e invalida reports atrasados de uma instância client anterior.

## State bags oficiais

Writer único: `mz_core` server por `Player(source).state:set(key, value, true)`.

| Bag | Tipo | Semântica |
| --- | --- | --- |
| `mz:loaded` | boolean | runtime canônico carregado |
| `mz:stateRevision` | number | marcador final do conjunto |
| `mz:deathState` | string | `alive`, `downed`, `dead` ou `respawning` |
| `mz:isDead` | boolean | estado `dead` |
| `mz:isDowned` | boolean | estado `downed` |
| `mz:isRespawning` | boolean | estado `respawning` |
| `mz:inventoryBlocked` | boolean | bloqueio local/consumer |
| `mz:weaponBlocked` | boolean | bloqueio local/consumer |
| `mz:interactionBlocked` | boolean | bloqueio local/consumer |

Ordem de escrita: flags derivadas, `deathState`, bloqueios, `loaded` e `stateRevision` por último. Consumers que precisem de uma visão consistente devem reagir à mudança de `mz:stateRevision`. Health, armor, hunger, thirst, stress, timestamps e metadata não são replicados em bags.

No unload, os derivados/bloqueios são limpos, `loaded=false` e `stateRevision=0` é escrito por último antes do runtime ser removido. Um novo load no mesmo source sobrescreve todo o conjunto e recebe tokens novos.

## Sincronização inicial, spawn e modelo

Fluxo real:

1. repository e normalizer constroem metadata;
2. `state_service` cria runtime/tokens;
3. `playerLoaded` informa ao client o token esperado;
4. `state_sync` escreve bags e envia o snapshot;
5. o client guarda a revision sem tocar cedo no ped;
6. `spawnmanager` cria/troca o modelo e emite `playerSpawned`;
7. o core sinaliza `mz_core:client:pedModelReady` ao concluir seu callback;
8. creator sinaliza o mesmo contrato somente quando `SetPlayerModel` realmente trocou o handle;
9. o espelho espera player ativo/ped existente, com timeout, e reaplica a revision atual.

O core removeu sua segunda chamada de `SetPlayerModel`, sua segunda ressurreição e seu segundo `playerSpawned`. A ressurreição de bootstrap ainda pertence ao `spawnmanager`; imediatamente depois dela o snapshot vigente é reaplicado. Assim, um personagem canonicamente morto volta à condição física morta, sem mudar metadata para alive.

## Aplicação física atômica

A aplicação usa `applying`, generation, revision, session token e handle do snapshot. Uma execução antiga aborta se qualquer identificador mudar.

### Escala de health

Metadata usa escala canônica 0–200. O client lê `GetEntityMaxHealth`:

- máximo abaixo de 200: eleva com `SetEntityMaxHealth(200)`;
- máximo igual ou acima de 200: não reduz o máximo;
- conversão: `round(canonical / 200 * pedMax)`;
- observação inversa: `round(physical / pedMax * 200)`.

`alive` aplica no mínimo `sync.aliveMinHealth` e nunca ressuscita um ped morto sem uma transição canônica nova proveniente de `dead/downed/respawning`. `dead` e `respawning` aplicam health 0 e armor 0. `downed` é temporariamente recuperado para health física/canônica 1 e armor 0, com gameplay bloqueado; não há animação, timer ou medicina neste lote.

### Revive e respawn

Uma revision nova que transiciona para `alive` a partir de estado não-alive pode usar `NetworkResurrectLocalPlayer` nas coordenadas atuais. O native executa no máximo uma vez por revision. Tasks/dano visual só são limpos nessa transição. Heal comum não chama revive.

`respawning` permanece bloqueado e sem health positiva. Um resource autorizado executa o spawn/teleporte fora deste contrato; apenas `CompletePlayerRespawn` server-side produz a revision `alive` que restaura health/armor.

### Armor

Armor é clampada em 0–100, aplicada somente no client local e confirmada por `GetPedArmour`. Alive recebe o snapshot; downed/dead/respawning recebem 0. Troca de modelo, spawn e resync forçam reaplicação. Um valor local maior nunca vira persistido: é corrigido para o snapshot.

## Observação de vitais

Evento: `mz_core:server:reportVitalCandidate` (client → server, sinal não confiável).

Schema fechado:

```lua
{
  sessionToken = "opaque",
  observationToken = "opaque",
  sequence = 4,
  localRevision = 12,
  observedHealth = 150, -- opcional, 0..200
  observedArmor = 20,   -- opcional, 0..100
  observedDead = false
}
```

Não há target, operação arbitrária, deathState, revive, coordenadas, attacker, weapon ou razão controlada pelo client. Campos desconhecidos e mais de sete campos são recusados. Sequence é estritamente crescente por observation token; revision precisa coincidir como proteção contra report atrasado; janela padrão aceita no máximo 10 reports/10 s.

Somente reduções de health/armor são aceitas. O servidor faz clamp, rejeita aumento, ignora update comum em dead/respawning e incrementa uma única revision quando aceita uma redução combinada. Reduções extremas geram log, mas não são automaticamente classificadas como cheat.

### Fatal

`gameEventTriggered/CEventNetworkEntityDamage` agenda leitura do ped após 100 ms; polling de reconciliação a cada 3 s é fallback. Se natives server-side confirmarem o ped morto, a política é aplicada imediatamente. Se confirmarem vivo, o candidato é recusado. Se o servidor não puder verificar o ped/entidade, são exigidos dois reports coerentes em 5 s, separados por no mínimo 500 ms no servidor.

Com `death.lastStandEnabled=true`, fatal aceito chama `MarkPlayerDowned`; com `false`, chama `MarkPlayerDead`. Report em estado já não-alive é idempotente. Client jamais escolhe o estado final.

## Reconciliação

O loop roda somente no intervalo configurado (mínimo efetivo de 1 s; padrão 3 s), nunca por frame quando alive. Compara ped/handle, death state, health escalada, armor, tolerâncias e application guard.

- alive + ped morto: report fatal;
- dead/respawning + ped vivo: reaplica a mesma revision;
- downed divergente: reaplica health temporária/bloqueios;
- vitais abaixo do snapshot além da tolerância: reporta redução com debounce;
- vitais acima do snapshot: trata como reset/script externo e reaplica, sem persistir aumento;
- handle mudou: registra model reset e reaplica;
- ped ausente/aplicação em andamento/diferença tolerada: ignora.

## Resync no restart client

Evento: `mz_core:server:requestPlayerStateSync` (client → server, read-only), sem argumentos e sem target. Cooldown padrão: 5 s. Uma resposta gira `observationToken`, envia a mesma revision com `forcePhysicalApply=true` e reconstrói bags/bloqueios. O client tenta novamente uma vez após o cooldown se o primeiro request não receber snapshot.

## Bloqueios e consumers

Enquanto downed/dead/respawning, a thread por frame existe somente para desabilitar ataque, disparo, troca de arma, entrada/saída/condução, contexto/interação, telefone e hotkeys comuns. Alive dorme 500 ms. `mz_inventory` consulta o export local antes da tecla de abertura; a hotbar do core consulta o espelho antes do request. `mz_phone` consulta o export local antes de abrir e `CanPlayerPerformAction('phone.use')` no servidor antes de autorizar os dados.

Exports client, sempre com cópia onde aplicável:

- `GetLocalPlayerState()`;
- `GetLocalDeathState()`;
- `IsLocalPlayerDead()`;
- `IsLocalPlayerDowned()`;
- `CanLocalPlayerPerformAction(action)`;
- `RequestPlayerStateResync(reason)` — `reason` é somente contexto local; nenhum valor é enviado.

`GetLocalPlayerState` omite `sessionToken` e `observationToken`; esses identificadores ficam privados ao módulo de transporte/reconciliação.

Segurança server-side continua exigindo `CanPlayerPerformAction`; DisableControl/state bags são defesa em profundidade, não autorização.

## HUD e admin

`state_sync` ainda emite `mz_core:client:hudStateUpdated` como adapter legado. O DTO legado agora inclui health, armor e deathState além de hunger/thirst/stress/flags. `mz_hud` usa health/armor canônicas desse adapter (health 100–200 convertida à faixa visual 0–100) e só recorre ao ped quando o snapshot ainda não existe. Nenhuma NUI foi redesenhada.

Heal administrativo chama `SetStatus(health, 200)`, armor chama `SetStatus(armor, amount)` e revive chama `RevivePlayer`. O admin não executa mais `SetEntityHealth`, `SetPedArmour` ou `NetworkResurrectLocalPlayer`; seu novo evento de confirmação só apresenta notificação.

## Limitações e pendências

- disponibilidade/semântica real dos natives server-side e state bags precisa de FiveM com OneSync;
- `spawnmanager` necessariamente ressuscita o ped durante o bootstrap; o core reaplica morte logo no callback e mantém controles bloqueados;
- múltiplos reports client sem confirmação server-side mitigam atraso/duplicação, mas não transformam o client em fonte confiável;
- downed ainda não tem animação, timer ou atendimento (Lote 5);
- validação visual do HUD, animações de consumo e confirmação de natives continuam pendentes de runtime FiveM.

## Extensão do Lote 4

`mz_hud` consome diretamente `mz_core:client:playerStateSync`. Seu reducer aceita somente revision maior, copia hunger/thirst/stress/health/armor e suprime alertas fora de alive. O adapter `hudStateUpdated` é fallback apenas antes do primeiro snapshot. Alertas de threshold disparam na entrada, respeitam cooldown e rearmam na saída; não há mutation ou persistência no HUD.

O dano local de colisão/cinto por `SetEntityHealth` foi removido. O HUD emite apenas `mz_status:client:reportVehicleImpact`; `mz_status` traduz para seu único endpoint de atividade, sem amount/target, e o dano do próprio source passa por `ApplyPlayerHealthDamage`.

Consumo confirmado chega por `mz_status:client:consumablePresented`. O payload controla apenas apresentação; efeito e remoção já foram decididos no servidor. Tiro e alta velocidade são candidatos de tipo fechado.

## Extensão do Lote 5

O DTO canônico inclui `downedExpiresAt` e `respawnAvailableAt`; o reducer continua revisionado e limpa deadlines incompatíveis. `mz_medical` consome o sync read-only, combina-o com um envelope local de sessão permitido apenas ao próprio resource e nunca escolhe estado ou vitais.

Downed/dead/respawning bloqueiam interações pelo estado oficial. A animação de downed tem timeout, revalidação e limpeza determinística. O HUD recebe somente estado e contagem regressiva. O fluxo hospitalar só envia acknowledgment depois do callback de spawn autorizado do core; coordenadas, modelo, health, armor e conclusão permanecem server-owned.

O único código ativo que aplica `NetworkResurrectLocalPlayer`, `SetEntityHealth` e `SetPedArmour` segue em `mz_core/client/player_state.lua`. Documento completo: `../../mz_medical/docs/PLAYER_MEDICAL_FLOW.md`.
