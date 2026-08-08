# Auditoria de autoridade de armas, munição e dano

Data da auditoria: 2026-08-02 (America/Sao_Paulo)

Escopo: `mz_core`, `mz_inventory`, `mz_banguard` e configuração de inicialização disponível em `mz_starter`

Método: revisão estática, sem executar servidor, sem testes destrutivos e sem criar código ofensivo

## 1. Resumo executivo

O inventário persistente está protegido contra o vetor de um executor client-side criar itens. `mz_core` define os itens, consulta e grava as linhas em `mz_inventory_items` no servidor e só expõe ao cliente callbacks que operam sobre linhas que o próprio servidor relê e valida. Não foi encontrado `RegisterNetEvent` ou callback client-to-server genérico para `AddPlayerItem`/`SetPlayerSlot`. O export `AddPlayerItem` existe, mas está em script server-side e pertence à fronteira de confiança entre recursos do servidor, não ao cliente (`server/inventory/events.lua:1-103`, `server/inventory/exports.lua:101-130`, `server/inventory/service.lua:2310-2435`).

Uma arma nativa no ped é um estado diferente de um item oficial. O item, seu `instance_uid`, serial, durability e metadata de munição pertencem ao inventário persistente de `mz_core`; a arma aplicada com `GiveWeaponToPed` e sua munição nativa existem no runtime do cliente. O estado de arma equipada é criado pelo servidor em `EquippedWeaponsBySource` e espelhado no cliente em `MZClient.InventoryWeapons.authorized` apenas para aplicar/reconciliar o ped (`server/inventory/service.lua:4-8, 1688-1710, 1804-1828`; `client/inventory.lua:1-6, 644-690`).

Os aumentos persistentes de munição também estão protegidos: o servidor rejeita `nextAmmo > knownAmmo`; uma recarga legítima exige item real de munição compatível, atualiza a metadata da arma, incrementa `ammo_revision` e consome uma unidade na mesma mutação transacional (`server/inventory/service.lua:1879-1976, 1997-2150, 2648-2723`).

Essa proteção de persistência não fecha a proteção de gameplay. Se a munição nativa ficar maior que a oficial, o cliente apenas evita enviar o aumento ao servidor; ele não chama `SetPedAmmo` para reduzi-la nesse caminho (`client/inventory.lua:522-604`). Também não existe débito server-side por disparo, validação de cadência ou associação de cada dano à munição oficial.

A contenção de arma injetada é client-side, executada a cada 1500 ms. Sem arma autorizada ela remove todas as armas do ped; em mismatch ela seleciona/reaplica a arma autorizada. A denúncia ao servidor gera somente log e também nasce no cliente (`client/inventory.lua:609-642, 857-890`; `server/inventory/events.lua:96-98`; `server/inventory/service.lua:3390-3414`). Um cliente comprometido pode impedir a thread e/ou o evento de telemetria.

Não foram encontrados handlers MZ para `weaponDamageEvent`, `startProjectileEvent`, `explosionEvent` ou `entityCreating`, nem uso de `CancelEvent()` associado a armas/dano no workspace. Portanto, o servidor não consulta a arma oficialmente equipada antes de aceitar dano, projétil ou explosão. Para dano remoto, a documentação oficial do Cfx confirma que `weaponDamageEvent` pode ser cancelado; para explosões, a documentação oficial de OneSync mostra interceptação e `CancelEvent()`. A documentação atual lista `startProjectileEvent`, mas não explicita na página consultada que ele é cancelável: essa capacidade deve ser comprovada em staging antes de virar premissa de bloqueio.

Conclusão: **itens e aumentos persistentes de munição estão protegidos; arma e munição runtime não estão protegidas por uma fronteira server-side de gameplay. Dano incompatível com a arma oficial pode passar.** O risco do cenário de arma injetada com dano é crítico.

> Uma verificação client-side pode ser usada para consistência e telemetria, mas não pode ser a única fronteira de segurança contra um cliente comprometido.

Essa afirmação aplica-se diretamente ao código auditado.

## 2. Identificação do código auditado

| Recurso | Branch | Commit | Estado no momento da leitura |
|---|---|---|---|
| `mz_core` | `main` | `f5b7ea4b6ab387b51384f77821ef11e32cc650a0` — `verificação` — 2026-08-02T14:46:54-03:00 | limpo antes deste relatório; `HEAD` = `origin/main` após fetch |
| `mz_inventory` | `main` | `322db9ef462a6b46fd0312def1fe4d7f0b6f6ef0` — `simplificando hover` — 2026-05-07T00:30:48-03:00 | limpo; fetch falhou porque o remoto configurado retornou `Repository not found`; comparação local com `origin/main` era `0 0` |
| `mz_banguard` | `main` | `f60b007807e145b4c4d5fa31ea6f418ef8ad6053` — `Initial commit` — 2026-07-29T21:29:03-03:00 | limpo; `HEAD` = `origin/main` após fetch |
| `mz_starter` | `main` | `765b0bedebe42947f7e8b4672566f1fa12340f4b` — `fix` — 2026-06-07T14:24:04-03:00 | já possuía mudanças locais em `cfg/base.cfg` e `cfg/resources.cfg`; nada foi alterado pela auditoria |

O diretório `D:\git-hub\repo_oficial` é um workspace com repositórios Git aninhados, não uma raiz Git. O remoto oficial solicitado foi confirmado em `mz_core` como `https://github.com/mz-core/mz_core.git`. Não foi criada branch, porque esta etapa não implementa correção.

## 3. Arquitetura encontrada

| Responsabilidade | Recurso | Arquivo/função | Autoridade |
|---|---|---|---|
| Definições de itens/armas/munição | `mz_core` | `shared/items.lua:74-309`; `Config.Weapons` em `config.lua:97-140` | servidor/arquivo compartilhado; decisão efetiva no servidor |
| Persistência dos itens | `mz_core` | `MZInventoryRepository.getInventory`, `buildSetSlotStatement`, `runTransaction` em `server/inventory/repository.lua:22-60, 211-285`; schema em `server/prepare.lua:396-423` | servidor + banco |
| Cache de jogador/sessão | `mz_core` | `MZCache.playersBySource` e `playersByCitizenId` em `server/cache.lua:1-7`; load/unload em `server/player/service.lua:127-205, 305-350` | servidor; não é cache das linhas de inventário |
| Arma equipada | `mz_core` | `EquippedWeaponsBySource`; `setEquippedWeaponState`/`clearEquippedWeaponState` em `server/inventory/service.lua:4-8, 1804-1877` | servidor, somente runtime da sessão |
| Equipar/desequipar | `mz_core` | `handleWeaponItemUse` em `server/inventory/service.lua:2152-2255`; aplicação em `client/inventory.lua:644-690, 774-809` | decisão no servidor; aplicação nativa no cliente |
| UID/serial/durability | `mz_core` | `buildItemMetadata` em `server/inventory/service.lua:857-877`; UID de arma em `1659-1671`; definições em `shared/items.lua:74-204` | servidor + metadata persistida |
| Nonce de equipamento | `mz_core` | `generateWeaponEquipNonce`/`weaponNonceMatches` em `server/inventory/service.lua:1522-1533` | servidor; espelhado ao cliente para o contrato corrente |
| Munição oficial | `mz_core` | metadata do item + estado equipado; `updateWeaponAmmoMetadata` em `server/inventory/service.lua:1879-1976` | servidor + banco |
| Recarga | `mz_core` | `handleAmmoItemUse` em `server/inventory/service.lua:1997-2150` | servidor, transacional |
| Munição nativa | `mz_core` client | `GetAmmoInPedWeapon`/`SetPedAmmo` em `client/inventory.lua:245-279, 400-417, 522-604` | runtime do ped; não confiável como autoridade |
| NUI | `mz_inventory` | manifesto sem server script em `fxmanifest.lua:14-34`; callbacks em `client/bridge.lua:3-14, 228-261` | frontend/client; backend é `mz_core` |
| Dano | nenhum recurso MZ encontrado | busca global por `weaponDamageEvent` | sem barreira server-side MZ |
| Projéteis | nenhum recurso MZ encontrado | busca global por `startProjectileEvent` | sem barreira server-side MZ |
| Explosões | nenhum recurso MZ encontrado | busca global por `explosionEvent` | sem barreira server-side MZ |
| Entidades | nenhum recurso MZ encontrado | busca global por `entityCreating` | sem validação complementar MZ |
| Risco/evidência | `mz_banguard` | scripts listados em `fxmanifest.lua:12-26`; exports de flags em `server/flags.lua:258-276` | servidor, mas sem integração de arma/dano encontrada |

`mz_inventory` é, portanto, uma NUI/client consumer. Seu manifesto não declara `server_scripts` e `client/bridge.lua` chama contratos de `mz_core`. Não existe uma segunda camada própria de inventário server-side.

## 4. Fonte oficial de verdade — respostas classificadas

| # | Pergunta | Classificação | Evidência e resposta |
|---:|---|---|---|
| 1 | Qual recurso é a fonte oficial dos itens? | protegido | `mz_core`; definições em `shared/items.lua`, persistência e mutações em `server/inventory/repository.lua` e `server/inventory/service.lua` |
| 2 | Qual recurso mantém a arma equipada? | protegido | `mz_core`, em `EquippedWeaponsBySource` (`server/inventory/service.lua:4, 1804-1828`) |
| 3 | Onde o estado equipado é armazenado? | protegido | tabela Lua server-side indexada por `source`; o item/ammo ficam no banco, mas o status “equipado” não é persistido |
| 4 | O estado é client-side, server-side ou duplicado? | parcialmente protegido | decisão e estado oficial no servidor, espelho client-side em `MZClient.InventoryWeapons.authorized`; o espelho é necessário à aplicação nativa, mas não pode autorizar gameplay |
| 5 | O servidor valida se o item existe no slot? | protegido | `buildUsePlayerItemMutationPlan` relê o slot e a definição (`server/inventory/service.lua:2648-2685`); equip valida novamente em `2152-2194` |
| 6 | O servidor valida `instance_uid`? | protegido | hotbar valida UID esperado (`2648-2665`); equip exige UID (`2188-2193`); atualização de ammo busca a arma por UID (`1924-1933`) |
| 7 | Existe nonce/token contra replay? | protegido no contrato de equip/ammo; ausente no dano | nonce novo por equip em `1522-1533, 1688-1706`; conferido em `1780-1801` e no client apply em `700-735`; nenhum uso em evento de dano |
| 8 | Existe revision de munição? | protegido no fluxo de recarga | `ammo_revision` é persistida, incrementada na recarga e conferida nas atualizações (`1904-1913, 2103-2109`) |
| 9 | O servidor permite aumento enviado pelo cliente? | protegido | bloqueio explícito `nextAmmo > knownAmmo` em `1940-1949` |
| 10 | A recarga consome item real? | protegido | valida slot, quantidade e tipo compatível (`2053-2083`), produz update da arma e `consume = true` (`2103-2117`); consumo entra na mesma lista transacional em `2648-2723` |
| 11 | A arma é desequipada ao sair do inventário principal? | protegido enquanto `enforceInventoryWeapons` estiver ativo | toda mutação chama `enforceEquippedWeaponStillOwned` após commit (`765-831`); ausência do UID limpa o estado e notifica o client (`2280-2307`) |
| 12 | A arma persiste no banco ou só no ped? | protegido/explicativo | item e metadata persistem em `mz_inventory_items`; status equipado é runtime server-side; arma nativa é runtime no ped (`server/prepare.lua:396-412`) |
| 13 | O cliente cria itens chamando eventos diretamente? | protegido contra o vetor auditado | nenhum evento/callback Add/Set foi encontrado. Callbacks públicos movem/usam itens que o servidor relê (`server/inventory/events.lua:1-103`) |
| 14 | Existe `AddItem` server-side genérico exposto sem autorização? | parcialmente protegido | existe export server-side `AddPlayerItem` (`server/inventory/exports.lua:109-111`) sem autenticação do recurso chamador. Não é invocável diretamente por executor client-side; pressupõe recursos do servidor confiáveis. Comandos de give exigem console ou ACE `mzcore.inventory.manage` (`server/inventory/commands.lua:1-19, 33-88`) |

## 5. Fluxos reais

### 5.1 Equipar

1. NUI/hotbar envia apenas slot/ação a `mz_core` (`mz_inventory/client/bridge.lua:3-14`; `mz_core/client/inventory.lua:80-88`).
2. O servidor resolve o jogador carregado e relê inventário/slot (`server/inventory/service.lua:2648-2685`).
3. `handleWeaponItemUse` valida definição de arma e `instance_uid` (`2152-2194`).
4. O servidor gera nonce, normaliza hash/ammo/revision e grava `EquippedWeaponsBySource` (`1688-1710, 1804-1828`).
5. Só então emite `mz_core:client:inventory:equipWeapon` (`2230-2253`).
6. O cliente remove armas anteriores, executa `GiveWeaponToPed`, aplica ammo e guarda um espelho sanitizado (`client/inventory.lua:644-690`).

### 5.2 Desequipar e movimentar

- Uso da mesma arma alterna para desequipado (`server/inventory/service.lua:2196-2208`).
- Troca de arma enfileira por até 10 s uma última atualização decrescente ligada ao UID/nonce anterior (`1747-1801, 2211-2228`).
- Toda mutação oficial do inventário relê se o UID equipado continua no inventário principal; se não, limpa estado e envia unequip (`765-831, 2280-2307`).
- Limpar o atalho da arma equipada também a desequipa (`4386-4397`).
- No client, unequip envia última tentativa de sincronização, remove a arma e seleciona desarmado (`client/inventory.lua:774-797`).

### 5.3 Recarga e atualização

- `handleAmmoItemUse` exige arma equipada, item de ammo realmente presente no slot, ammoType compatível e espaço até `maxAmmo` (`server/inventory/service.lua:1997-2103`).
- O servidor incrementa revision, atualiza metadata e consome uma unidade atomicamente (`2103-2149, 2648-2723`).
- O payload de aplicação precisa casar UID, nonce, arma e exatamente `revision + 1` no cliente (`client/inventory.lua:692-766`).
- Tiros são inferidos no client por queda do valor nativo e reportados periodicamente a cada 5 s (`client/inventory.lua:467-607, 903-912`; `config.lua:97-107`).
- O servidor aceita somente queda, com UID, nonce, revision corrente, rate limit mínimo de 750 ms e prova de que o item ainda existe (`server/inventory/service.lua:1879-1976`).

### 5.4 Morte, logout e drop

- `playerDropped` limpa o estado equipado e os rate limits antes de descarregar o cache do jogador (`server/player/events.lua:153-160`; `server/inventory/service.lua:3384-3387`).
- O stop de `mz_core` faz a mesma limpeza para jogadores carregados (`server/player/events.lua:163-180`).
- Não foi encontrado handler de morte/respawn que limpe a arma equipada. Há metadata `isdead`, mas ela não é consultada no fluxo de arma (`config.lua:57`; busca global por death/respawn e `clearPlayerEquippedWeapon`).
- Não foi encontrado fluxo explícito de “logout/troca de personagem” além de unload/drop no código auditado.
- Como a sincronização de tiros é periódica/client-side, uma desconexão abrupta pode não persistir os últimos tiros; o drop limpa o estado sem enfileirar atualização (`handlePlayerDropped`, `queuePending = false`). É uma lacuna de consistência, não uma forma de aumentar ammo persistente pelo client.

## 6. Arma injetada no ped

Modelo comprovado:

```text
executor entrega arma somente ao ped
→ nenhuma linha é criada em mz_inventory_items
→ GetSelectedPedWeapon pode observar a arma injetada
→ thread client-side verifica em até 1500 ms
→ client tenta remover/reselecionar e opcionalmente denuncia
→ servidor não correlaciona weaponDamageEvent/startProjectileEvent/explosionEvent
→ efeito de gameplay não possui cancelamento MZ server-side
```

Detalhes:

- Comparação: `GetSelectedPedWeapon` contra `authorized.weapon_hash` em `client/inventory.lua:857-884`.
- Intervalo: `Wait(1500)` em `client/inventory.lua:888`.
- Sem arma autorizada: `RemoveAllPedWeapons` + unarmed (`618-625, 865-869`).
- Com outra arma autorizada: o código reaplica/seleciona a arma oficial; não remove explicitamente o hash irregular nesse ramo (`871-883`).
- Denúncia: evento client-to-server, limitado no client e no server a uma por 5 s (`628-641`; `server/inventory/service.lua:1558-1577, 3390-3414`).
- A denúncia não provoca cancelamento, kick ou ban; só chama `logInventoryAction`.
- O servidor não verifica independentemente qual arma está selecionada quando recebe a denúncia e confia nos campos de telemetria do payload.
- Existe janela nominal de até 1,5 s mesmo com cliente íntegro.
- Com cliente comprometido, a thread, os natives de contenção e o evento de denúncia podem ser impedidos.

Resultado: **a detecção atual é consistência/telemetria client-side, não uma fronteira de segurança.**

## 7. Munição injetada

### Estado oficial

- `metadata.ammo` na linha persistida da arma;
- `EquippedWeaponsBySource[source].ammo` no cache de equip da sessão;
- `ammo_revision` na metadata e no cache;
- aumento apenas pelo uso server-side de item real compatível;
- atualização do client limitada a quedas.

### Estado nativo do ped

- lido com `GetAmmoInPedWeapon`;
- aplicado com `SetPedAmmo`/`SetAmmoInClip`;
- pode divergir durante a sessão sem criar item nem metadata persistente.

Respostas objetivas:

| Pergunta | Resposta |
|---|---|
| Servidor bloqueia `nextAmmo > knownAmmo`? | Sim, `server/inventory/service.lua:1940-1949`. |
| Client reduz o ped se `nativeAmmo > knownAmmo`? | Não no caminho periódico. Ele define `ammoForServer = knownAmmo`, registra debug opcional e não chama `SetPedAmmo` (`client/inventory.lua:572-582`). |
| Ele apenas evita informar aumento? | Sim; envia/retém o valor oficial (`572-604`). |
| Existe reconciliação periódica? | Parcial: leitura visual a 150 ms e update ao servidor a 5 s, ambos client-side (`892-912`). O aumento nativo não é corrigido. |
| Validação server-side do número de tiros? | Não encontrada. |
| Validação de fire rate? | Não encontrada. O rate limit de 750 ms limita update de metadata, não cadência de tiro. |
| Débito server-side por disparo? | Não. O servidor aceita quedas relatadas pelo client. |
| Arma oficial pode usar ammo runtime extra sem persistir? | Sim. O código não reduz `nativeAmmo > knownAmmo` e não bloqueia dano por ammo oficial zero. |

Distinção obrigatória:

```text
Munição persistente criada: bloqueada pelo contrato server-side de aumento.
Munição runtime utilizável durante a sessão: possível e não reconciliada de forma autoritativa.
```

## 8. Dano, projéteis, explosões e entidades

A busca foi executada em todo `D:\git-hub\repo_oficial`, excluindo somente `.git`, dependências/artefatos web e referências não executáveis. Ocorrências de `CancelEvent()` apareceram apenas em recursos base/chat não relacionados; não houve ocorrência MZ dos quatro handlers abaixo.

| Evento | Existe no código MZ? | `CancelEvent()`? | Consulta equip oficial/hash/ammo? | Outras validações | Resultado |
|---|---|---|---|---|---|
| `weaponDamageEvent` | não | não | não | sem dano máximo, distância, cadência ou alvo | **Ausência confirmada de barreira server-side para este evento.** |
| `startProjectileEvent` | não | não | não | sem allowlist weapon/projectile, posição ou rate limit | **Ausência confirmada de barreira server-side para este evento.** |
| `explosionEvent` | não | não | não | sem tipo, arma compatível, distância, escala ou rate limit | **Ausência confirmada de barreira server-side para este evento.** |
| `entityCreating` | não | não | não | nenhuma política complementar de entidade | **Ausência confirmada de barreira server-side para este evento.** |

Compatibilidade de runtime observada:

- `mz_starter/cfg/onesync.cfg:1` contém `set onesync on`.
- `mz_starter/cfg/base.cfg:9` contém `sv_enforceGameBuild 3751`.
- A documentação oficial Cfx [Server Events](https://docs.fivem.net/docs/scripting-reference/events/server-events/) confirma `weaponDamageEvent` e diz explicitamente que ele pode ser cancelado; também lista `startProjectileEvent` e seus campos `projectileHash`/`weaponHash`, mas não explicita cancelabilidade nessa página.
- A documentação oficial Cfx [OneSync: intercepting game events](https://docs.fivem.net/docs/cookbook/2019/08/19/onesync-intercepting-game-events-such-as-explosions/) demonstra `explosionEvent` com `CancelEvent()`, mas é um artigo arquivado; validar no artefato real de staging.
- A documentação oficial Cfx confirma que `entityCreating` é cancelável, mas esse evento não substitui validação específica de dano/projétil/explosão.

Não se afirmou cancelabilidade de `startProjectileEvent` sem teste/runtime que a comprove.

## 9. Exports e contratos existentes

Não existe export `GetEquippedWeaponState`, `IsWeaponAuthorized`, `GetEquipped*`, `WeaponState` ou equivalente. `EquippedWeaponsBySource` é local a `server/inventory/service.lua` e não está acessível ao `mz_banguard` (`server/inventory/service.lua:4`; `server/inventory/exports.lua:1-203`).

Contrato read-only proposto, ainda não implementado:

```text
GetEquippedWeaponState(source)
→ nil se source inválido/jogador não carregado/sem arma
→ cópia nova e sanitizada: item, slot, instance_uid, weapon, weapon_hash,
  equip_nonce (somente se estritamente necessário internamente), ammo,
  ammo_revision, serial, durability e citizenid

IsWeaponAuthorized(source, weaponHash)
→ boolean + estado sanitizado/motivo estável
→ consulta somente EquippedWeaponsBySource e cache oficial da sessão
```

Requisitos:

- export declarado apenas por script server-side;
- nunca devolver a tabela interna mutável;
- não consultar banco por tiro;
- falhar fechado para source inexistente, jogador não carregado ou estado incoerente;
- revalidar ownership nas transições de inventário já existentes, não a cada evento;
- não duplicar inventário no `mz_banguard`;
- nonce não deve virar segredo de segurança: um cliente comprometido já o recebe no equip.

## 10. Proteções existentes

- definição server-side dos itens e atributos de armas;
- banco com unicidade por slot e por `instance_uid` (`server/prepare.lua:396-423`);
- UID obrigatório para arma e hotbar;
- serial e durability gerados pelo servidor para armas únicas (`server/inventory/service.lua:857-877`);
- equip iniciado após releitura de slot/item/UID;
- nonce renovado por equip/troca;
- revision monotônica em recargas;
- bloqueio server-side de aumento de ammo relatado pelo client;
- recarga transacional que consome item compatível;
- limite máximo por tipo de munição;
- rate limit de updates e logs;
- desequipamento quando o UID deixa o inventário principal;
- limpeza no drop/resource stop;
- logs de equip, unequip, reload, update, aumento bloqueado e detecção client-side;
- wheel/hotbar controlados e contenção periódica no client.

## 11. Lacunas confirmadas

1. **Crítica — dano sem autoridade server-side.** Nenhum `weaponDamageEvent` consulta `EquippedWeaponsBySource` ou cancela mismatch.
2. **Crítica — projétil/explosão sem política server-side.** Nenhum handler correlaciona arma/projétil/explosão oficial.
3. **Alta — munição runtime acima da oficial não é reduzida.** O client apenas evita persistir o aumento.
4. **Alta — contagem de tiros e cadência não existem no servidor.** Ammo oficial zero não impede por si só dano ou projétil.
5. **Alta — contenção de arma injetada depende do cliente.** Intervalo de 1,5 s, thread interrompível e denúncia suprimível.
6. **Alta — não há contrato read-only da arma equipada para outro recurso server-side.** `mz_banguard` não consegue consultar o estado sem mudança no core.
7. **Média — telemetria de arma irregular não é verificada no servidor.** Payload pode ser omitido ou fabricado; o rate limit só reduz volume.
8. **Média — estado equipado não é limpo explicitamente em morte/respawn.** Isso pode causar estado obsoleto e futuros falsos positivos.
9. **Baixa — desconexão abrupta pode perder a última queda de ammo.** Não aumenta ammo por evento, mas pode restaurar tiros não salvos na próxima sessão.
10. **Operacional — `mz_banguard` não aparece no `mz_starter/cfg/resources.cfg:22-50`.** Isso só prova a configuração de launcher auditada, não a produção; mesmo iniciado, o recurso auditado não contém os guards de gameplay.

## 12. Hipóteses não confirmadas

- Não foi executado runtime; portanto não foi medido se todos os danos locais/remotos geram `weaponDamageEvent` no artefato efetivamente implantado.
- Cancelabilidade efetiva de `startProjectileEvent` não foi confirmada pela documentação consultada nem por staging.
- A configuração de produção pode diferir do `mz_starter` local e pode iniciar recursos não presentes neste workspace.
- Não foi confirmado se outro recurso externo ao workspace aplica proteção de dano/explosão.
- Não foi confirmado se scripts de job/creator/staff entregam armas temporárias por fora de `mz_core`; nenhum contrato explícito foi encontrado no escopo pesquisado.
- A semântica exata de morte/troca de personagem em produção pode pertencer a recurso não encontrado; o core auditado não trata esse ciclo para armas.
- Não se conclui que todo efeito local do GTA seja interceptável; o relatório limita a afirmação aos eventos documentados e ao código ausente.

## 13. Cenários de ameaça e risco

| Cenário | Persistência | Efeito runtime | Risco | Justificativa |
|---|---|---|---|---|
| Executor tenta criar item por evento do inventário | não | não | baixo | não existe Add/Set net event; servidor relê slots |
| Executor injeta arma no ped sem item e tenta dano | não | possível | crítico | contenção só client-side; nenhum guard de dano server-side |
| Pistola oficial, dano reportado como rifle | item oficial permanece | possível | crítico | nenhum match `weaponType` ↔ hash oficial |
| Arma oficial com ammo zero recebe ammo nativa | não aumenta | possível | alto | `nativeAmmo > knownAmmo` não é reduzido; sem débito por tiro |
| RPG/projétil incompatível | não | possível | crítico | nenhum handler/allowlist para projectile/explosion |
| Spam de dano/projétil/explosão | não | possível | alto | sem rate limit desses eventos |
| Forjar evento de denúncia client-side | não | polui evidência | médio | log confia no payload; rate limit de 5 s reduz volume |
| Replay de update de ammo antigo | não | limitado | baixo | UID + nonce + revision; aumento é bloqueado |
| Item equipado removido oficialmente | n/a | client recebe unequip | baixo | enforcement pós-mutação relê ownership |
| Resource server-side malicioso chama `AddPlayerItem` | sim | sim | médio fora do vetor client | export confia em recursos server-side; exige controle do servidor |

## 14. Plano mínimo de correção — não implementado

### Lote A — contrato read-only no `mz_core`

- adicionar as duas funções de consulta em `server/inventory/service.lua`;
- devolver cópia sanitizada e fail-closed;
- expor em `server/inventory/exports.lua` somente server-side;
- criar harness de contrato para source inexistente, jogador não carregado, sem arma, arma válida e mutabilidade da cópia;
- nenhuma mudança de banco.

Critério de saída: `mz_banguard` consulta a fonte oficial sem acessar tabela interna nem banco por evento.

### Lote B — guard de dano no `mz_banguard`

- handler server-side de `weaponDamageEvent`;
- resolver `sender`, player carregado e arma oficial pelo export;
- cancelar inicialmente apenas mismatches de alta confiança: sem arma oficial + hash armado conhecido, ou hash reportado diferente do oficial fora de janela legítima;
- validar campos/tipos e limitar dano override fora da política;
- log estruturado com source, hash observado/oficial, UID, revision, alvo e razão;
- modo inicial `observe`, depois `enforce`; sem ban automático.

Critério de saída: casos legítimos passam; mismatch inequívoco é cancelado e auditado.

### Lote C — projéteis e explosões

- construir allowlist versionada arma → projectileHash/explosionType;
- validar capacidade de cancelamento de `startProjectileEvent` no runtime de staging antes de enforcement;
- aplicar rate limits por source/arma/janela;
- validar posição/distância apenas quando dados confiáveis estiverem disponíveis;
- cancelar explosão incompatível de alta confiança; modo observe para combinações desconhecidas;
- não usar `entityCreating` como substituto dos eventos específicos.

### Lote D — reconciliação client complementar

- quando `nativeAmmo > knownAmmo`, aplicar imediatamente a ammo oficial ao ped;
- manter remoção/reseleção de arma irregular e reduzir o intervalo somente após medir custo;
- heartbeat/telemetria pode sinalizar divergência, nunca autorizar dano;
- tratar morte, respawn, troca de personagem e transições legítimas;
- manter o servidor como autoridade.

### Lote E — integração futura com `mz_banguard`

- converter decisões dos guards em evidências e risco acumulado;
- cooldown e deduplicação;
- bypass granular server-side por capacidade concreta, nunca “staff total” ou apenas noclip;
- nenhum bypass deve permitir arma irregular se a permissão for somente noclip;
- kick/ban apenas após observabilidade e validação runtime, com evidência reproduzível.

Separação final:

```text
mz_core
→ fonte oficial da arma, item, UID, nonce, ammo e revision

mz_banguard
→ validação server-side de dano/projétil/explosão e evidência

client
→ aplicação visual, reconciliação e contenção complementar
```

## 15. Plano de harness seguro

O harness deve testar uma função pura de decisão, por exemplo com entrada artificial `{playerState, equippedState, eventKind, eventData, now}` e saída `{allow, reason, evidence}`. Ele deve viver em `tests/`, não registrar net event, não chamar natives e não iniciar por padrão.

Casos mínimos:

| # | Entrada artificial | Resultado esperado |
|---:|---|---|
| 1 | sem arma equipada + dano armado | negar por alta confiança |
| 2 | pistola equipada + dano de rifle | negar por hash mismatch |
| 3 | arma correta + ammo/revision válidas | permitir |
| 4 | arma correta + ammo oficial zero | negar ou observar conforme política validada, nunca assumir ammo nativa |
| 5 | hash desconhecido | observar/negação configurável, sem ban |
| 6 | arma removida após equip | negar; estado deve estar nil após mutação |
| 7 | nonce/revision antigos no contrato | rejeitar |
| 8 | projectileHash incompatível | negar após runtime confirmar cancelamento |
| 9 | explosionType incompatível | negar |
| 10 | spam | rate limit + evidência agregada |
| 11 | source inexistente | falhar fechado, sem erro |
| 12 | disconnect durante validação | falhar fechado, não acessar estado removido |
| 13 | staff com bypass somente noclip | negar arma irregular |
| 14 | arma autorizada em fluxo legítimo | permitir |
| 15 | troca legítima de arma | tolerar janela curta server-side vinculada à transição, sem tolerância genérica |

Restrições: sem dar arma real, sem dano, sem explosão, sem evento público de teste, sem comando de jogador, sem persistência e sem tocar inventário real.

## 16. Riscos de falso positivo

- troca legítima entre duas armas e ordem dos eventos durante a transição;
- lag entre commit de equip, atualização do cache e evento de gameplay;
- morte/respawn com estado equipado ainda presente;
- troca de personagem/unload parcial;
- mudança de routing bucket durante o disparo;
- armas temporárias legítimas de job, creator, minigame ou cutscene;
- staff com capacidade específica; bypass deve ser granular e server-side;
- scripts que removem/reaplicam arma durante animação;
- discrepância de hashes signed/unsigned em Lua/event payload;
- shotgun/multi-hit gerando múltiplos alvos/eventos;
- dano ambiental ou explosão encadeada sem arma direta;
- latência entre recarga server-side, `ammo_revision + 1` e aplicação no ped;
- evento observado durante player load/unload;
- dados de posição/entidade fora do scope OneSync.

Mitigação: modo observe, razões estáveis, tolerância de transição curta e específica, allowlist medida em staging, nenhuma punição automática no primeiro rollout.

## 17. Checklist runtime para staging

- [ ] Fixar commit do artefato Cfx e confirmar OneSync ativo.
- [ ] Confirmar que `mz_core`, `mz_inventory` e o guard futuro iniciam na ordem correta.
- [ ] Confirmar export read-only retorna nil para source ausente/não carregado.
- [ ] Confirmar a cópia retornada não altera `EquippedWeaponsBySource`.
- [ ] Equipar/desequipar cada arma oficial e observar hash signed/unsigned.
- [ ] Testar troca legítima sem falso positivo.
- [ ] Testar recarga compatível/incompatível e revision.
- [ ] Testar ammo oficial zero sem causar dano real (alvo dummy/controlado ou decisão pura).
- [ ] Capturar shape real de `weaponDamageEvent` e confirmar `CancelEvent()` em ambiente isolado.
- [ ] Capturar shape real de `startProjectileEvent`; comprovar cancelabilidade antes de bloquear.
- [ ] Confirmar `explosionEvent` + cancelamento no artefato atual.
- [ ] Medir shotgun/multi-hit, veículos, peds e entidades fora de scope.
- [ ] Testar morte, respawn, troca de personagem e disconnect.
- [ ] Testar routing bucket e lag artificial.
- [ ] Testar job/creator/arma temporária legítima.
- [ ] Confirmar bypass somente noclip não ignora arma irregular.
- [ ] Validar rate limits sem descartar evidência importante.
- [ ] Rodar primeiro em observe e revisar logs/falsos positivos.
- [ ] Habilitar enforce somente para mismatches de alta confiança.
- [ ] Manter kick/ban automático desativado até completar janela de observação.

## 18. Comandos e validações executados

Comandos principais, todos não destrutivos:

```powershell
git status --short --branch
git remote -v
git branch --show-current
git log -1 --format="%H%n%h %s%n%cI"
git fetch --all --prune
git rev-list --left-right --count HEAD...origin/main
rg --files
rg -n --hidden -S "EquippedWeapon|...|ammo_revision|serial|durability" mz_core mz_inventory mz_banguard
rg -n --hidden -S "weaponDamageEvent|startProjectileEvent|explosionEvent|entityCreating|CancelEvent" .
rg -n -S "RegisterNetEvent|AddEventHandler|AddPlayerItem|updateWeaponAmmo|unauthorizedWeaponDetected" ...
rg -n -S "exports\(|GetEquipped|IsWeaponAuthorized|WeaponState|AuthorizedWeapon" mz_core
Get-Content <arquivos relevantes> com numeração de linhas
```

Validações realizadas:

- estado Git e commit dos três recursos relevantes;
- igualdade `HEAD`/`origin/main` para core e banguard;
- falha de remoto do inventory registrada sem substituir o checkout;
- manifestos e ordem de scripts;
- fonte de dados, schema, queries e transações;
- criação de UID/serial/durability;
- equip, unequip, switch e pós-mutação;
- recarga, bloqueio de aumento, nonce, revision e rate limits;
- threads client-side e seus intervalos;
- ciclo drop/resource stop e ausência de morte/respawn;
- busca global pelos quatro handlers e `CancelEvent()`;
- ausência de export read-only de arma;
- documentação oficial de eventos/cancelamento consultada para não extrapolar o runtime.

## 19. Critérios de aceitação

- [x] repositório e commit auditados registrados;
- [x] fluxo de equipar arma mapeado;
- [x] fluxo de munição mapeado;
- [x] fonte oficial de itens comprovada;
- [x] fonte oficial da arma equipada comprovada;
- [x] proteção client-side contra arma injetada identificada;
- [x] ausência dos handlers server-side de dano/projétil/explosão comprovada por busca global;
- [x] persistência versus runtime documentados;
- [x] conclusões acompanhadas de arquivo/função/linhas aproximadas;
- [x] nenhum código ofensivo criado;
- [x] nenhum arquivo de produção alterado;
- [x] `reports/WEAPON_AUTHORITY_AUDIT.md` gerado;
- [x] plano mínimo incremental apresentado sem implementação.

## 20. Declaração de alteração

Nenhum arquivo de produção, banco, schema SQL, economia, garagem, propriedade, organização, telefone, inventário ou anti-cheat foi alterado. O único arquivo criado por esta auditoria é este relatório. Nenhum lote de correção foi implementado.
