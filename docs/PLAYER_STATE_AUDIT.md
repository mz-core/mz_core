# Auditoria dos estados do jogador

Status: **Lote 1 — auditoria e contratos concluído em 2026-08-04**  
Escopo desta entrega: diagnóstico, mapa de responsabilidades, fonte de verdade, modelo canônico proposto, APIs e compatibilidade.  
Fora do escopo deste lote: alterar gameplay, banco, eventos ou manifests; criar o checklist de runtime; afirmar validação dentro do FiveM.

## 1. Resumo executivo

O sistema de estados do jogador foi apenas iniciado. `mz_core` já possui identidade, sessão, cache, metadata em `mz_players.metadata`, carregamento, export genérico de metadata e um payload parcial para o HUD. Porém, os campos vitais declarados não formam hoje um sistema funcional:

- `hunger`, `thirst` e `stress` têm defaults, persistência genérica e apresentação no HUD, mas não possuem ciclo, regras ou efeitos;
- `health` e `armor` têm defaults na metadata, mas não são enviados pelo payload do core, restaurados no spawn ou gravados a partir do ped;
- `isdead` e `inlaststand` têm defaults e chegam ao cache/HUD, mas nenhum fluxo oficial os altera;
- não existe máquina de morte, estado `downed`, último suspiro, respawn médico ou resource médico ativo;
- o spawn normal sempre chama `NetworkResurrectLocalPlayer`, inclusive quando a metadata eventualmente disser que o jogador está morto;
- o revive administrativo ressuscita somente o ped no client e não atualiza o core;
- o inventário valida e transaciona o uso de itens no servidor, mas água apenas é removida sem recuperar sede; pão e bandagem são marcados como usáveis sem handler;
- não há state bags oficiais de sessão/morte/bloqueio nem consulta central de autorização de ações;
- não há dirty state, flush agrupado, revisão ou serialização das mutações de metadata;
- o setter genérico e a bridge QB permitem que qualquer resource server-side altere campos sensíveis sem allowlist, contexto ou transição.

Conclusão: a única fonte persistente existente é a metadata do `mz_core`, mas ela ainda não é uma fonte de verdade operacional. Na prática, o ped, a metadata, o cache client e cada consumer podem divergir.

## 2. Escopo e método da auditoria

Foram inventariados os resources da raiz, seus manifests, configuração de startup, schema gerado pelo core, scripts server/client, bridges, inventário, itens, HUD, spawn, creator/clothing, comandos administrativos, integrações com morte física e os resources CFX locais `spawnmanager` e `baseevents`.

A workspace contém aproximadamente 3.231 arquivos. As buscas globais cobriram os termos solicitados e variantes de metadata, morte, revive, respawn, health/armor, eventos, state bags e bloqueios. `ref/` e `_local_backups/` foram reconhecidos, mas não tratados como código de runtime: são referências/artefatos históricos e não constam em `mz_starter/cfg/resources.cfg`. Dependências CFX locais foram examinadas quando participam do fluxo.

Não foram encontrados resources ativos chamados `mz_status`, `mz_survival`, `mz_medical`, `mz_hospital` ou `mz_ambulance`. Existe uma organização `ambulance`, permissões médicas e conteúdo visual/configuracional de hospital, mas não um sistema médico.

## 3. Mapa dos resources relacionados

| Resource | Papel atual | Lê | Escreve/atua | Persistência | Avaliação |
| --- | --- | --- | --- | --- | --- |
| `mz_core` | identidade, sessão, cache, metadata, spawn, inventário e payload HUD | `mz_players`, ped somente em módulos não relacionados | metadata genérica, posição, spawn/resurrect, inventário | MySQL | fonte principal existente, incompleta |
| `mz_hud` | apresentação e dano de colisão/cinto | metadata parcial do core; health/armor/oxygen/stamina do ped | reduz health do ped em colisão | configuração própria; não persiste vitais | mistura apresentação com dano de gameplay |
| `mz_inventory` | NUI consumer do inventário do core | snapshots/handlers do core | solicita use/move/drop/split/merge | persistência fica no core | não bloqueia morto/downed |
| `mz_admin` | heal, armor e revive administrativos | permissões/hierarquia do core; ped | altera health/armor/revive diretamente no client | não persiste vitais/morte | autorização parcial boa, estado canônico ausente |
| `mz_creator` | aparência | metadata `appearance` no core | `SetPlayerModel`, metadata de aparência | via setter genérico do core | troca de modelo pode resetar o ped sem reconciliação vital |
| `mz_clothing` | componentes/roupas | jogador do core e eventos de spawn | aplica roupa | tabelas próprias | reaplica no spawn; não coordena estados vitais |
| `mz_houses` | casas e stash | ped morto; `baseevents` | força saída de imóvel na morte física | própria | único consumer explícito de eventos de morte; fallback por polling |
| `mz_bank` | banco | health do ped no servidor e client | bloqueia sessão quando health `<= 0` | própria | não reconhece `downed` ou metadata de morte |
| `mz_animations` | emotes | ped e state bags genéricas | escreve `mz:animation` | nenhuma | prevê state key `dead`, que ninguém escreve |
| `mz_progress` | barra de progresso | morte física do ped | cancela progresso | nenhuma | não reconhece `downed` canônico |
| `mz_fuel` | abastecimento/galão | morte física do ped | cancela ação | metadata do item | sem integração canônica de morte |
| `mz_target` / `mz_interact` | interação | estado próprio/NUI | abre inventários/interações | nenhuma | sem bloqueio de morte oficial |
| `mz_garagem` | garagem | sessão do core | abre/retira veículos | própria/core vehicles | sem bloqueio de morte oficial |
| `mz_phone` | telefone | sessão/identidade do core | abre telefone/câmera | própria | sem bloqueio de morte oficial |
| `mz_banguard` | segurança/telemetria | spawn e respawn nativo | abre grace/lease de segurança | runtime próprio | observador, não é fonte de estado do jogador |
| `spawnmanager` | spawn CFX | payload de spawn | cria ped e emite `playerSpawned` | nenhuma | usado pelo core |
| `baseevents` | detector CFX de morte física | ped a cada frame | emite eventos locais/server | nenhuma | presente em disco, mas não aparece no startup MZ |

### Resources que aparentam existir, mas não implementam medicina

- `mz_core/server/seed/default_orgs.lua`: cria organização `ambulance` e capacidades `ambulance.medkit.*` / `ambulance.revive.*`.
- `mz_org/shared/capabilities.lua`: cataloga capacidades médicas.
- `mz_settings`: contém IPL/cenário de hospital e controle de veículos ambientais.
- `mz_radio`: tem canal rotulado como Hospital.
- `mz_progress`: aceita a categoria visual `hospital`.

Nenhum deles implementa downed, death screen, revive médico, hospitalização ou respawn.

## 4. Inventário das implementações encontradas

| Arquivo / símbolo | Lado | Responsável | Escrita / leitura | Cache | Banco | State bag | HUD | Segurança e situação |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `mz_core/config.lua:50` `Config.Player.defaultMetadata` | shared | core | declara hunger/thirst/stress/health/armor/isdead/inlaststand | — | usado na criação | não | indireto | defaults duplicados no HUD; sem limites centralizados |
| `mz_core/shared/utils.lua:3` `jsonDecode` | shared | core | decodifica JSON ou retorna fallback | — | — | não | não | JSON inválido não é distinguido; fallback pode ser a tabela de config compartilhada |
| `mz_core/server/prepare.lua:136` `mz_players` | server | core | declara `metadata LONGTEXT NULL` | — | sim | não | não | schema funcional, sem revisão/dirty/versionamento |
| `mz_core/server/player/repository.lua:31` `updateMetadata` | server | core | sobrescreve o JSON inteiro | — | imediato | não | não | risco de lost update com snapshot antigo |
| `mz_core/server/player/service.lua:17` `buildPlayerData` | server | core | banco → `player.metadata` | sim | lê | não | depois | não completa campos, converte tipos, limita ou corrige invariantes |
| `mz_core/server/player/service.lua:127` `loadPlayer` | server | core | cria/carrega personagem e sessão | sim | sim | não | sincroniza depois | funcional para sessão; incompleto para estados |
| `mz_core/server/player/service.lua:265` `setMetadataValue` | server | core | setter genérico de qualquer chave | sim | write-through | não | sincroniza 5 campos | sem tipo, clamp, allowlist, contexto, rate limit ou transição |
| `mz_core/server/player/exports.lua:297` `SetMetadataValue` | server export | core | expõe setter genérico | sim | imediato | não | sim | `GetInvokingResource()` não é validado |
| `mz_core/server/bridges/qb.lua:54` `SetMetaData` | server bridge | core/QB | alias do setter genérico | sim | imediato | não | sim | campos sensíveis podem contornar contrato futuro se não forem interceptados |
| `mz_core/server/bridges/qb.lua:62` `SetPlayerData('metadata')` | server bridge | core/QB | itera metadata e grava chave a chave | sim | N writes | não | N syncs | não atômico e excessivo; preserva compatibilidade, mas é inseguro para vitais |
| `mz_core/server/player/hud.lua:40` `buildStateFromPlayer` | server | core | lê hunger/thirst/stress/isdead/inlaststand | sim | não | não | payload | clamps apenas na projeção; não corrige a fonte |
| `mz_core/client/hud.lua` | client | core | mantém cópia parcial em `MZClient.HUDState` e `PlayerData.metadata` | sim client | não | não | exporta | health/armor ausentes; cache client pode ficar obsoleto após mudanças fora do payload |
| `mz_hud/client/main.lua:721` `getStatusPayload` | client | HUD | ped → health/armor; core → hunger/thirst/stress | sim local | não | voz apenas | NUI | apresentação funciona, mas combina duas fontes concorrentes |
| `mz_hud/client/main.lua:297` dano de colisão | client | HUD | reduz health do ped | não | não | não | sim | gameplay dentro do HUD; server não conhece nem persiste o dano |
| `mz_core/server/main.lua:35` `getSpawnData` | server | core | posição/modelo, ignora vitais/morte | sim | lê posição | não | não | retorna spawn vivo para qualquer metadata |
| `mz_core/client/spawn.lua:83` `doSpawn` | client | core | sempre ressuscita o ped | client | não | não | ped refletido | crítico: reconnect/spawn normal apaga morte física |
| `mz_creator/client/appearance.lua:45` `ensureModel` | client | creator | troca modelo do player | client | não | não | ped refletido | não preserva/reaplica health, armor ou morte |
| `mz_core/server/inventory/service.lua:2671` uso de item | server | core inventory | valida slot/item/handler e transaciona consumo | contexto | sim | não | resposta | boa base transacional, sem consulta de morte/status |
| `mz_core/server/inventory/service.lua:4578` handler `water` | server | core inventory | remove 1 água | — | inventário | não | não | funcional como consumo, efeito de sede ausente |
| `mz_core/shared/items.lua` `bread`, `bandage` | shared | core inventory | declara `usable = true` | — | definição | não | NUI | sem handler; falha com `item_not_usable` |
| `mz_admin/server/main.lua:333` `revivePlayer` | server | admin | autoriza alvo e envia evento client | não | não | não | não | possui permissão, rate limit, hierarquia e log; não valida estado/transição nem atualiza core |
| `mz_admin/client/commands.lua:581` `mz_admin:client:revive` | client | admin | ressuscita e cura o ped | client | não | não | ped refletido | evento localmente acionável; metadata permanece divergente |
| `mz_admin/client/commands.lua:464/472` heal/armor | client/admin | admin | altera ped | client | não | não | ped refletido | armor é somente client após autorização; nenhum estado persistido |
| `baseevents/deathevents.lua` | client CFX | baseevents | polling por frame e eventos de morte física | local | não | não | não | client é não confiável; resource não está listado no startup MZ |
| `mz_houses/client/main.lua:2325` | client | houses | reage a `baseevents` e polling físico | local | não | não | não | apenas sai da casa; duplica detecção e não atualiza core |
| `mz_bank/server/service.lua:55` | server | bank | consulta ped/health para abrir sessão | não | não | não | não | bom bloqueio físico pontual; desconhece downed persistido |
| `mz_animations/shared/config.lua` | client | animations | espera state key `dead` | local | não | lê state bag | não | contrato previsto, porém ninguém publica a key |
| `mz_banguard/server/security_lifecycle.lua:412` | server | banguard | observa `respawnPlayerPedEvent` | runtime | não | não | não | somente grace de anticheat; não é respawn médico |

## 5. Matriz de cobertura atual

Legenda: **sim** = implementação coerente no aspecto; **parcial** = dado/caminho existe mas não fecha o fluxo; **não** = ausente.

| Estado | Declarado | Cache | Persistência | Client | HUD | Gameplay | Segurança | Situação |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| hunger | sim | sim | parcial | parcial | sim | não | não | **incompleto / alto** |
| thirst | sim | sim | parcial | parcial | sim | não | não | **incompleto / alto** |
| stress | sim | sim | parcial | parcial | sim | não | não | **apenas campo / médio** |
| health | sim | sim | não efetiva | não | ped direto | dano parcial | não | **divergente / crítico** |
| armor | sim | sim | não efetiva | não | ped direto | admin parcial | não | **divergente / alto** |
| downed | legado `inlaststand` | sim | possível via setter | parcial HUD | não exibido | não | não | **ausente / crítico** |
| dead | legado `isdead` | sim | possível via setter | parcial HUD | não exibido | não | não | **ausente / crítico** |
| revive | não | não | não | admin direto | não | parcial | parcial admin | **fora do core / crítico** |
| respawn | não | não | não | spawn sempre vivo | não | spawn genérico | não | **incorreto para morte / crítico** |

Observação: “persistência parcial” significa que o setter genérico conseguiria gravar o valor, não que exista política funcional de atualização.

## 6. Fonte de verdade atual e caminho dos dados

### 6.1 Estrutura persistente

`mz_players.metadata` é um `LONGTEXT` contendo JSON. Somente `MZPlayerRepository.updateMetadata` foi encontrado escrevendo a metadata de jogador na tabela `mz_players`; não há segundo resource atual gravando esse JSON diretamente.

### 6.2 Estrutura em cache

`MZCache.playersBySource[source]` e `MZCache.playersByCitizenId[citizenid]` apontam para `playerData`, que contém `metadata`, `state.loaded` e `session`. O `state` dessa tabela é cache interno Lua e não é FiveM state bag.

### 6.3 Estrutura enviada ao client

O evento `mz_core:client:playerLoaded` envia o snapshot inteiro. O callback `mz_core:server:getPlayerData` também o retorna. Mudanças posteriores de metadata somente atualizam o client por `mz_core:client:hudStateUpdated`, cujo payload contém cinco campos. `health` e `armor` não entram nesse payload.

### 6.4 Estrutura usada pelo HUD

O HUD combina:

- hunger/thirst/stress: `MZClient.HUDState.metadata`, originada do cache server;
- health/armor: natives do ped client-side;
- isdead/inlaststand: recebidos pelo core client, mas não renderizados como estado médico pelo HUD.

### 6.5 Veredito da fonte de verdade

A fonte persistente pretendida é `mz_core -> player.metadata`, mas a fonte efetiva varia por atributo:

| Atributo | Fonte efetiva atual |
| --- | --- |
| hunger/thirst/stress | metadata/cache, porém estáticos |
| health/armor | ped client para exibição; metadata inicial permanece obsoleta |
| morte/incapacitação | ped físico; flags de metadata não participam do fluxo |
| revive | evento direto de `mz_admin` no client |
| respawn | `mz_core/client/spawn.lua` + `spawnmanager` |

Portanto, já é possível a combinação proibida: metadata morta + ped ressuscitado pelo spawn + HUD de vida normal.

## 7. Fluxos atuais

### Carregamento do personagem

1. `playerJoining`, restart do core ou callback tardio chama `MZPlayerService.loadPlayer`.
2. O core busca por license; se não existir, cria personagem com os defaults.
3. `jsonDecode(row.metadata, Config.Player.defaultMetadata)` carrega metadata.
4. O snapshot entra nos dois caches e uma sessão é criada.
5. `mz_core:client:playerLoaded` envia o snapshot; o HUD parcial é enviado em seguida.

Falhas: JSON inválido usa fallback sem registrar/persistir correção; campos ausentes continuam ausentes; números string não são convertidos; campos fora de limite continuam na fonte; flags incompatíveis não são corrigidas; não existe schema/revision da metadata.

### Spawn inicial

1. O client recebe `playerLoaded` e pede `getSpawnData`.
2. O servidor retorna última posição/default e modelo de aparência.
3. O client troca o modelo, chama `spawnmanager:spawnPlayer` e depois `NetworkResurrectLocalPlayer` incondicionalmente.
4. Não aplica `metadata.health`, `metadata.armor`, `isdead` ou `inlaststand`.
5. Emite o evento local `playerSpawned`.

Falhas: revive silencioso; reconnect morto não é preservado; não existe confirmação server-side de spawn médico. Existem listeners para `mz_core:client:playerSpawned` em `mz_admin` e `mz_banguard`, mas o core não emite esse evento de rede.

### Restauração de vida e armadura

Não existe fluxo oficial. Spawn/model swap usa os valores implícitos do novo ped. Admin heal/revive/armor altera apenas o ped client. Metadata `health = 200` e `armor = 0` não é aplicada nem atualizada.

### Alteração de metadata

`SetMetadataValue(source, key, value)` atualiza o cache e sobrescreve imediatamente o JSON inteiro no banco. Depois sincroniza o payload parcial do HUD. Não há dirty state, debounce, lock, revision, merge por campo, validação de chave sensível ou evento de mudança estável.

### Consumo de comida

`bread` está marcado como usável, mas não possui handler. A tentativa termina em `item_not_usable`; fome não muda.

### Consumo de bebida

`water` possui handler server-side. O inventário valida player, slot e item e remove uma unidade em transação. Nenhum efeito é aplicado a `thirst`, portanto o item é perdido sem benefício de status.

### Dano

O dano normal fica no ped. O HUD também aplica dano por colisão/cinto no client. O core não recebe snapshots vitais, não reconcilia e não persiste. Não há handler de `CEventNetworkEntityDamage` no ecossistema MZ.

### Incapacitação / último suspiro

Ausente. `inlaststand` é somente um campo legado declarado.

### Morte

O core não detecta nem transiciona morte. `baseevents` existe no pacote CFX, mas não aparece na lista de `ensure` do starter; mesmo se iniciado, somente `mz_houses` reage para retirar o jogador de uma casa. Alguns resources verificam `IsEntityDead`, sem contrato comum.

### Revive

Somente administrativo: server valida permissão, rate limit, alvo online, hierarquia e auditoria; depois dispara um evento client que ressuscita o ped e o cura. Não verifica estado anterior, não é idempotente, não atualiza metadata/state bag e pode ser executado localmente por um client modificado.

### Respawn

Não existe respawn médico. O único spawn de personagem é também um revive incondicional. O `respawnPlayerPedEvent` observado pelo banguard é evento de segurança/anticheat, não uma operação de gameplay.

### Disconnect e reconnect

No drop, inventário limpa runtime e o core encerra a sessão/remove o cache. Metadata só está segura se já tiver sido gravada por setter. No reconnect, o spawn ignora flags de morte. Disconnect vivo/downed/morto não tem política distinta. `respawning` também não existe.

### Restart de resource

- restart do core: recarrega jogadores online do banco e dispara novo `playerLoaded`; pode iniciar novo spawn client se o resource client reiniciou;
- restart do HUD: busca novamente o payload parcial do core; health/armor continuam vindos do ped;
- restart do inventário: reabre sob demanda; nenhuma flag oficial o bloqueia;
- restart médico/status: não aplicável, pois esses resources não existem;
- restart creator/clothing: pode reaplicar aparência; troca de modelo pelo creator não reconcilia vitais.

## 8. Problemas classificados

### Crítico

1. Não existe autoridade server-side nem máquina de estados para morte.
2. Spawn/reconnect ressuscita incondicionalmente e ignora metadata de morte.
3. Health/armor persistidos nunca são reconciliados com o ped.
4. Revive administrativo altera somente o client; o handler pode ser acionado localmente e não muda o estado canônico.
5. Setter/bridge genéricos permitem mutação de campos sensíveis sem contrato ou allowlist.
6. Nenhum bloqueio server-side impede inventário/itens e demais ações enquanto morto/downed.

### Alto

1. Metadata não é normalizada ao carregar e pode conter combinações inválidas.
2. Escrita de JSON inteiro sem lock/revision pode perder mudanças concorrentes.
3. Fome e sede não têm ciclo; água é consumida sem efeito e pão não funciona.
4. Não há persistência crítica em morte/revive/respawn nem política de reconnect/combat log.
5. HUD mistura metadata e ped como fontes concorrentes.
6. Troca de modelo pode restaurar vida implicitamente.
7. Não há rate limit específico nos callbacks de inventário/status (o inventário possui locks de container, mas não política de estado do jogador).

### Médio

1. Stress é somente declarativo.
2. Defaults de status estão duplicados em `Config.Player`, HUD server e HUD client.
3. Não há payload HUD de downed/dead/oxygen canônico; oxygen é exclusivamente local.
4. Resources usam `IsEntityDead` ou uma state key `dead` inexistente, gerando semânticas diferentes.
5. `baseevents` não está declarado no startup MZ e seria client-authoritative mesmo se usado sozinho.
6. O evento `mz_core:client:playerSpawned` tem consumers, mas não é emitido.

### Baixo

1. `health` usa unidade nativa (default 200) enquanto o HUD exibe percentual; o contrato de unidade não está documentado.
2. Nomes legados `isdead` e `inlaststand` não seguem a capitalização usual dos demais contratos, mas precisam ser preservados.

### Melhoria futura

1. Métricas agregadas de rejeições e transições.
2. Instrumentação de latência/volume de flush.
3. Efeitos visuais avançados de stress em resource de apresentação.

## 9. Arquitetura adotada para os próximos lotes

Esta é a decisão contratual do Lote 1; a implementação deve ocorrer nos lotes seguintes.

| Camada | Responsabilidade |
| --- | --- |
| `mz_core` server | fonte canônica, normalização, transições, status, cache, persistência, autorização de resources, state bags e consulta de ações |
| `mz_core` client | aplicar snapshot autorizado ao ped, detectar sinais físicos, reconciliar e confirmar spawn/respawn; nunca decidir transição final |
| `mz_inventory` + inventário do core | validar posse/uso/transação; chamar efeito canônico do core e compensar falhas |
| `mz_hud` | somente ler payload estável e apresentar; dano de cinto deve migrar para um domínio de gameplay apropriado ou chamar uma API autorizada |
| resource médico futuro/real encontrado antes do Lote 5 | animações, câmera, timers visuais, atendimento e hospital; transições sempre solicitadas ao core |
| `mz_admin` | autorizar ação administrativa e chamar API server-side separada do revive médico |
| `mz_creator` / `mz_clothing` | preservar/reaplicar snapshot vital após mudança de modelo sem alterar death state |
| consumers (`bank`, `phone`, `garage`, `houses`, `animations`, `progress`, `target`) | usar `CanPlayerPerformAction` e/ou state bags oficiais |
| `mz_banguard` | observar leases/lifecycles legítimos de spawn/revive, sem virar fonte de verdade |

Não será criado player cache paralelo, metadata paralela ou resource de status independente.

## 10. Modelo canônico proposto

### 10.1 Campo interno persistido

Adicionar `metadata.deathState` com valores:

```text
alive | downed | dead | respawning
```

Manter, normalizar e derivar os campos existentes:

```text
metadata.isdead
metadata.inlaststand
```

`deathState` será a representação explícita; os dois booleanos permanecem contratos de compatibilidade e nunca podem ser gravados de forma independente por consumers.

### 10.2 Campos e limites

| Campo | Unidade | Default atual preservado | Limite/contrato proposto |
| --- | --- | ---: | --- |
| `hunger` | percentual | 100 | inteiro 0..100 |
| `thirst` | percentual | 100 | inteiro 0..100 |
| `stress` | percentual | 0 | inteiro 0..100 |
| `health` | health nativa do ped | 200 | inteiro 0..`maxHealth` configurado; regras por death state |
| `armor` | percentual nativo | 0 | inteiro 0..100 |
| `deathState` | enum | derivado dos legados | alive/downed/dead/respawning |
| `isdead` | compatibilidade | false | derivado |
| `inlaststand` | compatibilidade | false | derivado |
| timestamps de morte | epoch server | ausente | apenas campos definidos no contrato do Lote 2/5 |

O HUD continuará convertendo health nativa para percentual; não deve gravar o percentual de volta como health nativa.

### 10.3 Invariantes

| Estado | `isdead` | `inlaststand` | Inventário/ações | Health persistida |
| --- | ---: | ---: | --- | --- |
| `alive` | false | false | conforme ação normal | maior que limiar de morte |
| `downed` | false | true | bloqueado salvo allowlist médica | valor controlado de downed |
| `dead` | true | false | bloqueado salvo apresentação/respawn | valor de morte |
| `respawning` | true até conclusão | false | bloqueado e idempotente | valor transitório não aplicado como alive |

Nunca aceitar `isdead = true` junto com `inlaststand = true`. `respawning` é uma transição interna; para consumers legados ele permanece morto até `CompleteRespawn`.

### 10.4 Transições válidas

```text
alive -> downed
alive -> dead              (morte imediata configurada)
downed -> dead
downed -> alive            (revive)
dead -> alive              (revive autorizado, se permitido)
dead -> respawning
respawning -> alive
```

Qualquer outra transição retorna `false, 'invalid_transition'`. Repetir a mesma operação deve retornar o snapshot atual sem duplicar custos, itens ou efeitos.

## 11. Contrato de normalização

No load, antes de inserir no cache:

1. decodificar JSON com retorno explícito de sucesso/erro;
2. se inválido/nulo/não-tabela, iniciar de cópia profunda dos defaults;
3. preservar todas as chaves desconhecidas;
4. preencher apenas campos canônicos ausentes;
5. converter números string finitos;
6. arredondar/clamp conforme configuração única;
7. aceitar booleanos legados seguros (`true/false`, `1/0` e strings conhecidas);
8. derivar `deathState` de dados antigos;
9. resolver conflito legado com precedência conservadora: `isdead` vence `inlaststand`;
10. regerar `isdead`/`inlaststand` a partir de `deathState`;
11. retornar `(normalized, changed, issues)`;
12. persistir uma vez somente quando `changed == true`;
13. garantir idempotência: segunda normalização não altera o resultado.

Defaults e limites devem ficar em `Config.PlayerStates` ou extensão equivalente de `Config.Player`, mantendo `Config.Player.defaultMetadata` como compatibilidade. Não repetir números no HUD.

## 12. APIs canônicas propostas

Os nomes seguem `MZPlayerService` e exports PascalCase já usados pelo projeto.

### 12.1 Service server-side

```lua
MZPlayerStateService.getState(source)
MZPlayerStateService.getStatus(source, statusName)
MZPlayerStateService.setStatus(source, statusName, value, context)
MZPlayerStateService.addStatus(source, statusName, amount, context)
MZPlayerStateService.removeStatus(source, statusName, amount, context)
MZPlayerStateService.getDeathState(source)
MZPlayerStateService.markDowned(source, context)
MZPlayerStateService.markDead(source, context)
MZPlayerStateService.revive(source, context)
MZPlayerStateService.beginRespawn(source, context)
MZPlayerStateService.completeRespawn(source, context)
MZPlayerStateService.canPerformAction(source, action)
MZPlayerStateService.reconcilePedSnapshot(source, snapshot, context)
MZPlayerStateService.flush(source, reason, force)
```

Retorno padrão de mutações:

```lua
true, sanitizedState
false, 'stable_error_code'
```

### 12.2 Exports server-side

```text
GetPlayerState
GetStatus
SetStatus
AddStatus
RemoveStatus
GetDeathState
MarkPlayerDowned
MarkPlayerDead
RevivePlayer
BeginPlayerRespawn
CompletePlayerRespawn
CanPlayerPerformAction
ReconcilePlayerVitals
FlushPlayerState
```

`SetMetadataValue` permanece para metadata não sensível. Para as chaves canônicas, deve encaminhar à API específica ou recusar conforme origem/contexto; nunca executar o caminho genérico.

### 12.3 Eventos e callbacks

Eventos client → server devem expressar intenção, não valor final:

```text
mz_core:server:playerState:reportFatalDamage
mz_core:server:playerState:requestRespawn
mz_core:server:playerState:confirmRespawn
mz_core:server:playerState:reportVitals
```

O payload vital do client deve ser limitado, rate-limited e reconciliado; não é autoridade. Eventos server → client:

```text
mz_core:client:playerStateChanged
mz_core:client:applyPlayerState
mz_core:client:beginRespawn
```

Payload estável proposto:

```lua
{
  revision = 1,
  status = { hunger = 100, thirst = 100, stress = 0 },
  vitals = { health = 200, maxHealth = 200, armor = 0 },
  death = { state = 'alive', isdead = false, inlaststand = false },
  restrictions = { inventory = false, combat = false, movement = false },
  reason = 'player_loaded'
}
```

## 13. State bags oficiais propostos

Somente o servidor escreve as keys sensíveis.

| Nome | Tipo | Escritor | Leitores | Replica | Limpeza/restart |
| --- | --- | --- | --- | ---: | --- |
| `mz:loaded` | boolean | core server | todos | sim | false no unload; reconstruído no load |
| `mz:deathState` | string | core server | médico/HUD/consumers | sim | reconstruído da metadata |
| `mz:isDead` | boolean | core server | compatibilidade | sim | derivado de deathState |
| `mz:isDowned` | boolean | core server | compatibilidade | sim | derivado de deathState |
| `mz:inventoryBlocked` | boolean | core server | inventário/UI | sim | derivado de ação/estado |

Não replicar metadata inteira. Em restart do core, as bags devem ser reconstruídas após load e permanecer conservadoras (`loaded=false`, ações sensíveis bloqueadas) durante a janela de recuperação.

## 14. Persistência e concorrência propostas

- cache server-side continua sendo a cópia de trabalho;
- mutações canônicas são serializadas por jogador;
- metadata é alterada por merge na cópia atual, nunca por snapshot client/consumer;
- `revision` de runtime aumenta a cada mutação e acompanha payloads;
- hunger/thirst/stress marcam dirty fields e usam debounce + flush periódico;
- downed/dead/revive/begin/complete respawn fazem flush crítico imediato;
- unload e stop do core fazem flush antes de remover o cache;
- health/armor são persistidas em alterações relevantes, snapshots limitados, unload e transições; nunca por frame;
- falha de flush mantém dirty state e gera log; não marca sucesso falso;
- operação de inventário + efeito deve usar plano/compensação: efeito validado antes, remoção transacional, aplicação após commit idempotente ou reserva confirmada.

O padrão de lock determinístico existente no inventário é uma boa referência local, mas o lock de player state deve cobrir metadata e transições, não compartilhar snapshots antigos.

## 15. Segurança e allowlists propostas

### 15.1 Origens server-side

Toda API sensível deve usar `GetInvokingResource()` e uma configuração central. Proposta inicial baseada nos resources existentes:

| Capacidade | Resources iniciais |
| --- | --- |
| status consumível | `mz_core` (inventário interno) |
| registrar efeitos de item | allowlist explícita; hoje `mz_fuel`, `mz_bank` apenas para seus itens não vitais |
| health/armor médico | futuro resource médico nomeado + `mz_admin` |
| revive médico | futuro resource médico nomeado |
| revive administrativo | somente `mz_admin`, rota separada |
| spawn/respawn | `mz_core`; resource médico apenas solicita |
| dano de sobrevivência/stress | `mz_core` e resources declarados por configuração |

Console/invocação interna deve ter contexto explícito. Resource ausente da allowlist retorna `unauthorized_resource` e gera log agregado.

### 15.2 Eventos client → server

Validar source online/carregado, tipo/tamanho do payload, sequência/revision, cooldown, death state atual, distância server-side quando aplicável e ausência de target arbitrário. Rejeições suspeitas devem registrar evento, source, estado, razão e bucket de rate limit sem dados sensíveis.

### 15.3 Revive comum

Executor e alvo conectados/carregados; alvo downed/dead; executor alive; distância calculada no servidor; organização/capacidade e duty; item/charge/reserva; cooldown; conclusão do progresso; mesma revision/transição ainda válida; consumo/cobrança exatamente uma vez.

### 15.4 Revive administrativo

Manter permissionamento, hierarquia, rate limit e auditoria já existentes em `mz_admin`, mas substituir o evento client direto por export server-side do core com contexto `admin`. O client recebe somente o snapshot autorizado resultante.

## 16. Contrato de bloqueio de ações

`CanPlayerPerformAction(source, action)` deve ser a verificação server-side oficial. State bags servem como antecipação de UI, nunca como única proteção.

| Ação | alive | downed | dead | respawning |
| --- | ---: | ---: | ---: | ---: |
| abrir/mover/usar/pegar/drop de inventário | sim | não | não | não |
| arma/atirar/atacar | sim | não | não | não |
| dirigir/entrar em veículo | sim | não | não | não |
| banco/garagem/propriedade/target | sim | não | não | não |
| telefone/menus/emotes | sim | configurável e restrito | não | não |
| ação médica de apresentação | — | sim | sim | sim |
| solicitar respawn | não | não | quando elegível | idempotente |

Os callbacks server-side de cada domínio devem verificar o contrato. Apenas esconder/fechar UI no client não é segurança.

## 17. Compatibilidade

### Contratos existentes que devem permanecer

- `PlayerData.metadata.hunger/thirst/stress/health/armor/isdead/inlaststand`;
- exports `GetPlayer`, `GetPlayerData`, `GetMetadataValue`, `SetMetadataValue`, `GetHUDState`;
- evento `mz_core:client:playerLoaded`;
- bridge QB `Player.Functions.GetMetaData`, `SetMetaData`, `SetPlayerData`;
- evento HUD `mz_core:client:hudStateUpdated` durante uma janela de migração.

### Regras da bridge

- leitura continua retornando campos legados derivados;
- escrita não sensível continua no setter genérico;
- escrita de `hunger/thirst/stress` passa por status API, com origem e clamp;
- escrita de `health/armor/isdead/inlaststand/deathState` é recusada ou traduzida para operação canônica autorizada;
- `SetPlayerData('metadata', table)` deve executar uma mutação merge única, não N gravações;
- aliases `hospital:server:SetDeathStatus`, `hospital:server:SetLaststandStatus` não existem hoje e não devem ser criados como eventos públicos desprotegidos; se compatibilidade futura exigir, serão adapters server-only para a máquina canônica.

### Consumers atuais a migrar

| Consumer | Migração necessária |
| --- | --- |
| `mz_hud` | consumir payload único; retirar autoridade/dano de status do HUD |
| `mz_inventory`/core inventory | checar ação e aplicar efeitos de water/bread/bandage via contrato |
| `mz_admin` | chamar revive/heal/armor canônicos server-side |
| `mz_creator` | preservar snapshot vital/death state em troca de modelo |
| `mz_bank`, `mz_garagem`, `mz_houses`, `mz_phone`, `mz_target`, `mz_interact` | checar ação no servidor; usar bag apenas para UX |
| `mz_animations`, `mz_progress`, `mz_fuel` | trocar detecção isolada por `mz:deathState`/consulta oficial, mantendo fallback físico defensivo |
| `mz_banguard` | receber leases para spawn/revive válidos e observar eventos, sem escrever estado |

## 18. Critérios de aceite dos próximos lotes

### Lote 2 — base server-side

- normalizador idempotente com preservação de desconhecidos;
- cache/mutações serializadas, revision, dirty e flush;
- APIs específicas, invariantes, logs e allowlists;
- harnesses de metadata, status, concorrência e forged resource.

### Lote 3 — sincronização client

- payload/revision estável, state bags server-owned;
- aplicação e reconciliação de health/armor;
- detecção de dano/morte como sinal não confiável;
- spawn respeita morte persistida e troca de modelo não revive.

### Lote 4 — fome, sede e stress

- decay configurável server-side e agrupado;
- efeitos a zero;
- água/pão e demais consumíveis transacionais;
- HUD somente apresenta.

### Lote 5 — morte e medicina

- downed/dead/revive/respawn/reconnect completos e idempotentes;
- integração médica real ou módulo de apresentação definido sem duplicar core;
- validações de distância, capacidade, duty, item e cooldown.

### Lote 6 — hardening

- consumers migrados, aliases restritos, rate limits finais;
- testes de eventos forjados e restarts;
- `PLAYER_STATE_RUNTIME_CHECKLIST.md` e execução no servidor FiveM.

## 19. Decisões e pendências do Lote 1

Decidido:

- `mz_core` continuará sendo a única autoridade e persistência de player state;
- `metadata.deathState` será canônico, com booleanos legados derivados;
- state bags serão projeções server-owned, não outra fonte de verdade;
- HUD e consumers não poderão mutar estados sensíveis;
- revive admin e médico terão rotas separadas para a mesma máquina de estados;
- nenhum sistema paralelo será criado.

Pendente de implementação/validação em lotes posteriores:

- parâmetros finais de timers, dano por fome/sede, health de downed/revive e regras de perda/cobrança;
- nome e existência do resource médico de apresentação;
- teste real do comportamento de health após `SetPlayerModel` no build do servidor;
- teste OneSync dos natives server-side e state bags;
- testes de restart, reconnect e dois jogadores dentro do FiveM.

## 20. Implementação do Lote 2 — base server-side

Status em 2026-08-04: **implementado e validado estaticamente/por harness; runtime FiveM pendente**.

### Decisões finais

- `MZCache.playersBySource[source].metadata` permanece a única fonte funcional em memória; o runtime novo guarda somente revision, dirty, lock, timestamps operacionais e identidade da sessão.
- A normalização ocorre uma vez no `buildPlayerData`, antes da inserção no cache. JSON inválido usa defaults seguros e a correção é tentada no repository existente.
- `metadata.deathState` foi implementado com `alive`, `downed`, `dead` e `respawning`; `isdead`/`inlaststand` são sempre derivados. Em conflito legado, `isdead=true` vence.
- Os cinco timestamps de ciclo de morte foram persistidos em epoch Unix server-side por serem necessários para reconnect, auditoria e futuros lotes. Não foram criadas colunas SQL.
- Mutações usam mutex cooperativo por player, timeout configurável e release central em erro.
- Status comuns usam dirty/debounce/thread global. Transições de morte, correções, unload e stop tentam persistência imediata.
- Falha crítica mantém estado em cache e dirty para retry, retornando `persistence_pending`; não há rollback de uma transição já aplicada em memória.
- Revision é runtime, começa em zero e só muda em mutação canônica efetiva.
- `SetMetadataValue` bloqueia todos os campos canônicos/timestamps. A bridge traduz status, aplica patch de metadata em uma gravação e nega booleanos de morte.
- Writers externos usam allowlists exatas por categoria; `mz_admin` entra por default como writer medical, armor e administrative. Não foram criados eventos client→server de estado no core.
- Heal e revive administrativos server-side foram migrados para atualizar a API canônica antes de preservar seus efeitos client legados; armor físico fica pendente do Lote 3.

### Divergências controladas da proposta do Lote 1

- `ReconcilePlayerVitals` não foi exposto no Lote 2 porque depende de sinal client, rate limit e reconciliação física definidos para o Lote 3.
- State bags e eventos server→client novos foram mantidos fora deste lote conforme a divisão final; o evento HUD legado continua sendo apenas compatibilidade.
- O retorno canônico foi expandido de `false, 'code'` para `false, { code, message }`, seguindo o requisito final de retorno uniforme do Lote 2.
- Todos os timestamps propostos foram persistidos, em vez de manter parte somente em runtime, para que reconnect não perca o estágio temporal do episódio.

### Testes executados

Executados localmente com Lua 5.5:

```text
lua tests/player_state_normalizer_harness.lua
lua tests/player_state_service_harness.lua
lua tests/player_state_concurrency_harness.lua
lua tests/player_state_lifecycle_harness.lua
lua mz_admin/tests/security_contract_harness.lua
```

Os quatro harnesses novos e o harness de segurança do `mz_admin` passaram. Eles cobrem normalização/idempotência, status, autorização, snapshot imutável, revision, dirty/debounce, transições/idempotência, persistência crítica/falha/retry, bridge, ação, unload, duas operações concorrentes, status+morte, flush/mutação, unload/mutação, release em erro, lock timeout, percurso/agregação do resource stop e preservação do guard administrativo.

Os cinco harnesses preexistentes do `mz_core` também passaram: commerce de conta de organização (implementação e contrato), roles Staff default, hierarquia Staff e autoridade de armas.

`luac -p` passou nos 18 arquivos Lua alterados. Uma varredura nos 76 arquivos Lua do core encontrou somente dois arquivos preexistentes com sintaxe de hash por backtick específica do CfxLua (`client/inventory.lua` e `server/vehicles/debug.lua`), que o parser Lua 5.5 padrão não reconhece; nenhum deles foi alterado neste lote.

Também foram executadas validação de sintaxe Lua, busca de setters sensíveis, exports duplicados, eventos perigosos e conferência da ordem do `fxmanifest.lua`. Os comandos e resultados finais constam no relatório de conclusão do Lote 2.

### Riscos remanescentes

- O comportamento de yield/timeout, restart, disconnect durante falha do banco e reutilização de source ainda precisa ser observado dentro do scheduler do FiveM.
- O ped, o HUD e os consumers continuam sem sincronização física/canônica até os lotes seguintes.
- A allowlist de status está vazia por segurança; medical/armor contêm apenas `mz_admin`, consumer real já autorizado. Novos resources deverão ser adicionados explicitamente.
- O `GetPlayer` legado ainda expõe o objeto do player para código server-side antigo; os novos consumers devem usar snapshots canônicos.
- Encerramento abrupto do processo não garante o flush final.

## Lote 3 — sincronização client, state bags e física (implementado)

### Ordem real e conflitos confirmados

O startup local garante `spawnmanager` antes de `mz_core`; creator, clothing, HUD e admin carregam depois. O percurso observado é metadata/runtime → `playerLoaded` → callback de spawn → `spawnmanager` troca modelo/ressuscita → `playerSpawned` → callback core → aparência/creator. Foram confirmados:

1. o core chamava `SetPlayerModel` antes do `spawnmanager` chamar novamente;
2. o callback core repetia `NetworkResurrectLocalPlayer` e `playerSpawned`;
3. `mz_admin` ainda aplicava heal/revive/armor diretamente depois/fora da mutation canônica.

Os caminhos redundantes foram removidos. O `spawnmanager` continua sendo o bootstrap inevitável; core e creator emitem `mz_core:client:pedModelReady`, que só força a reaplicação da revision autorizada.

### Contratos implementados

- payload server → client reduzido, revisionado, tokenizado e validado;
- espelho local sem persistência/authority e exports defensivos;
- bags `mz:*` server-authoritative com revision escrita por último;
- aplicação central de max health, health, armor e death state;
- resync read-only após restart client;
- observation endpoint fechado para reduções e fatal candidates;
- confirmação do ped server-side quando disponível, ou 2 reports/5 s quando indisponível;
- reconciliação padrão de 3 s com tolerância 2 health/1 armor;
- bloqueio por frame somente em downed/dead/respawning;
- adapter temporário para `mz_core:client:hudStateUpdated`.

### State bags

`mz:loaded`, `mz:stateRevision`, `mz:deathState`, `mz:isDead`, `mz:isDowned`, `mz:isRespawning`, `mz:inventoryBlocked`, `mz:weaponBlocked` e `mz:interactionBlocked`. Derivados, death, bloqueios e loaded são escritos antes; revision é o marcador final. Unload limpa o conjunto antes de finalizar runtime.

### Admin, HUD e consumers

Heal, revive e armor administrativos terminam no sync do core. `mz_admin:client:heal` e `mz_admin:client:revive` foram removidos; confirmação administrativa não usa natives. A tecla do inventário e hotbar consultam o contrato local. HUD mantém o adapter legado. O dano de colisão/cinto preexistente dentro de `mz_hud` permanece classificado como pendência de migração, não como writer canônico.

### Testes e pendências runtime

Os harnesses novos cobrem payload/revision/session, bags/order/unload/source reuse, aplicação alive/dead/downed/respawning, revive idempotente, timeout/cancelamento/model reapply, reductions/increase rejection/target/rate/fatal e reconciliação. Há ainda contrato estático de manifest/spawn/creator/admin/HUD/inventory. Os harnesses do Lote 2 e security contract do admin continuam obrigatórios.

Exigem FiveM/OneSync: disponibilidade real de `Player(source).state`, leitura server-side do ped, ordem de replicação, modelos customizados, janela transitória do bootstrap, `CEventNetworkEntityDamage`, reconnect/restart e render real do HUD. Reports client continuam sinais não confiáveis; múltiplos reports são mitigação, não prova.

Documentos: `PLAYER_STATE_CLIENT_SYNC.md` e `PLAYER_STATE_RUNTIME_CHECKLIST.md`.

## Lote 4 — sobrevivência funcional (implementado)

### Diagnóstico e resource

Não existia `mz_status`, `mz_survival` ou equivalente ativo. Os IDs reais são `water`, `bread` e `bandage`: stack/usable, sem metadata. Água removia sem recuperar sede; pão e bandagem não tinham handler. `bread.png` estava ausente, sendo adotado `sandwich.png`. O HUD apresentava status por adapter, mas não descartava revision e aplicava colisão diretamente no ped.

Foi criado `mz_status`, separado do core/HUD, com scheduler global, acumuladores por sessão, decay agrupado, stress, dano crítico, catálogo fechado e apresentação. Core continua truth/persistência; inventário continua posse/lock/transação; HUD continua apresentação.

### Contratos e segurança

- `ApplyStatusPatch`: schema fechado hunger/thirst/stress e uma revision por lote;
- `ApplyPlayerHealthDamage`: writer separado, somente redução e fatal atômico;
- `ApplyPlayerHealing`: writer separado, alive only e sem revive;
- evento interno de vitais não registrável pela rede;
- único candidato client de atividade, source implícito, um campo, allowlist, rate e cooldown;
- consumo pelo slot real, benefício/cooldown/operação server-side, operationId e idempotência;
- remoção transacional antes do efeito, com restauração exata em falha; pending funcional não duplica;
- HUD revisionado e colisão migrada para dano canônico.

### Testes e riscos

Novos harnesses: player-state survival, inventário/compensação, serviço de status e contrato HUD. Harnesses dos Lotes 2/3 e security contract do admin permanecem sem regressão. Não há SQL ou flush em `mz_status`, thread por player, setter no HUD ou `SetEntityHealth` de colisão.

Pendente de runtime: scheduler/natives/OneSync, ordem de start/restart, disconnect no yield, NUI, animações, thresholds e balanceamento. Crash exatamente entre efeito canônico e ack/compensação não é transação distribuída. Downed/morte/medicina/respawn continuam fora do lote.

Documento: `../../mz_status/docs/PLAYER_STATUS_SURVIVAL.md`.

## Auditoria direcionada — Lote 5

Antes deste lote não havia resource médico ativo, prazo persistido de downed/dead, atendimento autoritativo nem operação hospitalar. Havia apenas estados canônicos e aplicação física central no core. O job oficial encontrado foi `ambulance`, com duty, grades e capabilities já fornecidos por `mz_player_orgs`; o inventário possuía `bandage`, mas não um item reservado para revive.

Foi criado `mz_medical`, sem banco, inventário, job ou metadata paralelos. O novo `firstaid` usa o catálogo oficial e uma reserva transacional no core. Billing e perda de itens permanecem desligados por falta de contrato distribuído comprovado. Pillbox usa o IPL já iniciado e coordenada configurada que ainda precisa de aprovação visual em runtime.

Varreduras dos consumers ativos confirmam natives de revive/vitais apenas no client do core. Banco, garagem, casas, inventário, telefone e animações consultam o estado/guard canônico nas entradas alteradas; `vehicle.drive` segue com bloqueio client-side e não possui um consumer server central único para migrar neste lote. Documento: `../../mz_medical/docs/PLAYER_MEDICAL_FLOW.md`.

## Lote 6 — hardening e aprovação estática (2026-08-08)

A revisão local pós-Lote 5 manteve as adições de spawn médico e harnesses. A instrumentação suspeita posterior foi consolidada em observabilidade com schema/redaction, contadores, agregação e cooldown; duplicidades de sinalização no bridge foram removidas.

Consumers finais receberam guards server-side: inventário (open/use/move/drop/pickup/storage/hotbar), telefone com bypass somente de cleanup, garagem, veículos/sirene/fuel, propriedades, roupas/tatuagem, animações e progress. Player bloqueado é retirado do banco do motorista com cooldown. Leituras externas ativas usam `GetPlayerSnapshot`; objeto mutável e aliases QB seguem compatíveis e deprecados.

Reservas médicas ganharam cache terminal idempotente, retry exponencial limitado, estados pending/exhausted, consulta read-only e recovery protegido por admin/staging. Billing permanece off e item loss `none`: não há saga médica debit/refund nem adapter determinístico de perda validados em MySQL/runtime.

Observabilidade é read-only para `mz_admin`; BanGuard continua responsável por incidentes/sanções e não recebe auto-ban. Classificação: aprovado estaticamente e por harnesses; runtime FiveM/OneSync/MySQL e dois jogadores permanecem pendentes.

Documentos finais: `PLAYER_STATE_INTEGRATION_GUIDE.md`, `PLAYER_STATE_OPERATIONS.md`, `PLAYER_STATE_SECURITY.md`, `adr/ADR_PLAYER_STATE_AUTHORITY.md`, `PLAYER_STATE_RUNTIME_CHECKLIST.md` e `PLAYER_STATE_RUNTIME_RESULTS.md`.
