# Auditoria economica do mz_core

Data da auditoria: 2026-06-23

Escopo: analisar o estado atual do `mz_core` e recursos `mz_*` relacionados a dinheiro, contas, empregos, organizacoes, telefone, casas, imobiliaria e fluxos ilegais. Esta auditoria nao implementa codigo e nao altera comportamento.

## Resumo executivo

O `mz_core` ja possui uma base propria de identidade, contas e organizacoes. O jogador e identificado por `license`, recebe um `citizenid`, tem conta em `mz_player_accounts` e pode carregar saldos em `wallet`, `bank` e `dirty`. A estrutura atual e suficiente para iniciar um modulo economico, mas ainda nao existe um ledger economico dedicado.

O dinheiro hoje e persistido principalmente em `mz_player_accounts` e `mz_org_accounts`. As mudancas em contas de jogador passam, em geral, por `MZAccountService`, mas o historico economico fica em `mz_logs`, que e generico. Ele ajuda na auditoria operacional, mas nao resolve bem perguntas como "quanto dinheiro foi criado hoje", "qual categoria gerou renda", "qual recurso removeu dinheiro" ou "qual ganho medio por hora por jogador".

Nao encontrei, nos recursos `mz_*` atuais, sistemas completos de trabalho legal com pagamento por missao, venda em NPC, mineracao, pesca, drogas, roubo, heist ou lavagem de dinheiro. O principal fluxo legal encontrado e a folha salarial por organizacao. Tambem existem gastos em combustivel, roupas e tatuagens. O recurso legado `celular/resource/smartphone` contem banco, PayPal e cassino fora do `mz_core`; se estiver ativo no servidor, ele e um bypass economico relevante.

Recomendacao central: criar um recurso separado `mz_economy` para observabilidade, classificacao e relatorios, integrado ao `mz_core` por wrappers/exports metadata-aware. Isso reduz risco sobre o core e permite evoluir precos dinamicos, relatorios diarios e integracao futura com telefone/email sem quebrar compatibilidade.

## Como o core identifica e carrega jogadores

Arquivos principais:

| Area | Arquivo | Funcao / ponto |
| --- | --- | --- |
| Identidade | `mz_core/server/player/service.lua` | `getLicense`, `loadPlayer`, `touchPlayer`, `unloadPlayer` |
| Persistencia | `mz_core/server/player/repository.lua` | `getByLicense`, `getByCitizenId`, `create`, `ensureAccount`, sessoes |
| Exports | `mz_core/server/player/exports.lua` | `GetPlayer`, `ResolvePlayerIdentity`, `EnsurePlayerLoaded`, `GetPlayerSession` |
| Eventos | `mz_core/server/player/events.lua` | `playerJoining`, `playerDropped`, `onResourceStart`, `onResourceStop` |

Fluxo atual:

1. O jogador entra.
2. O core resolve o identificador `license:`.
3. Se nao existir registro, cria linha em `mz_players` com `citizenid` novo.
4. Garante uma linha em `mz_player_accounts`.
5. Fecha sessoes ativas antigas e cria uma nova entrada em `mz_player_sessions`.
6. Coloca o jogador em cache por `source` e `citizenid`.

Observacoes:

- O `citizenid` e a chave logica usada pelos sistemas internos.
- A conta inicial vem de `Config.StarterMoney`.
- `mz_player_sessions` ja da uma boa base para playtime, mas ainda nao e um agregador diario confiavel de horas jogadas.
- `last_seen_at` e atualizado quando chamadas do core tocam o jogador, nao como heartbeat continuo.

## Como dinheiro funciona hoje

Arquivos principais:

| Area | Arquivo | Funcao / ponto |
| --- | --- | --- |
| API de dinheiro | `mz_core/server/accounts/exports.lua` | `GetMoney`, `SetMoney`, `AddMoney`, `RemoveMoney` |
| Servico | `mz_core/server/accounts/service.lua` | `getMoney`, `setMoney`, `addMoney`, `removeMoney` |
| Banco | `mz_core/server/accounts/repository.lua` | `updatePlayerMoney` |
| Config | `mz_core/config.lua` | `Config.StarterMoney`, `Config.Payroll` |

Contas suportadas:

| Conta | Significado atual |
| --- | --- |
| `wallet` | dinheiro em maos |
| `bank` | dinheiro bancario |
| `dirty` | dinheiro sujo |

O repositorio limita atualizacao a `wallet`, `bank` e `dirty`. Nao ha conta `cash` ou `black_money`; scripts futuros precisam normalizar aliases para evitar divergencia.

Pontos fortes:

- O dinheiro de jogador esta centralizado em uma tabela clara.
- O servico valida valores negativos e jogador carregado.
- O log generico registra antes/depois em operacoes feitas pelo servico.
- A bridge QBCore encaminha `Player.Functions.AddMoney`, `RemoveMoney`, `SetMoney` e `GetMoney` para o core.

Lacunas:

- Os exports atuais nao aceitam metadata publica: `AddMoney(source, moneyType, amount)` e similares.
- Nao ha campo obrigatorio para `source_resource`, `reason`, `category`, `counts_as_income` ou `counts_as_expense`.
- Nao ha tabela de transacoes economicas normalizada.
- O log atual (`mz_logs`) e generico e nao e ideal para relatorios economicos.
- `SetMoney` pode criar ou remover saldo dependendo do valor final, mas sem classificacao economica.

## Organizacoes e folha salarial

Arquivos principais:

| Area | Arquivo | Funcao / ponto |
| --- | --- | --- |
| Salarios | `mz_core/server/accounts/payroll.lua` | `payCitizen`, `RunPayrollTick`, `PayCitizenSalary` |
| Conta de org | `mz_core/server/accounts/org_accounts.lua` | `DepositOrgAccount`, `WithdrawOrgAccount`, `AddOrgAccountBalance`, `RemoveOrgAccountBalance` |
| Comandos | `mz_core/server/accounts/commands.lua` | `mzorg_balance`, `mzorg_deposit`, `mzorg_withdraw`, `mzpay_citizen`, `mzpay_tick` |
| Seeds | `mz_core/server/seed/default_orgs.lua` | policia, ambulancia, mecanica, mafia, staff, vip |

Fluxo de salario:

1. O payroll busca organizacoes do jogador.
2. Verifica se o cargo tem salario.
3. Se `Config.Payroll.requireDuty` estiver ativo, exige que o membro esteja em duty.
4. Debita a conta compartilhada da organizacao.
5. Credita o banco do jogador.
6. Registra log generico em `mz_logs`.

Classificacao economica recomendada:

- Do ponto de vista do jogador, salario e renda.
- Do ponto de vista da cidade, o payroll atual e transferencia se o dinheiro saiu de `mz_org_accounts`.
- So deve contar como dinheiro criado se a origem da conta da organizacao tambem tiver sido criada pelo sistema.

Risco importante:

`payroll.lua` atualiza `mz_player_accounts` diretamente no helper `addBankMoney`, em vez de passar por `MZAccountService.addMoney`. Isso nao quebra o fluxo atual, mas dificulta uma auditoria unica por wrapper.

## Gastos encontrados em recursos mz_*

| Recurso | Arquivo | Fluxo | Conta |
| --- | --- | --- | --- |
| `mz_fuel` | `mz_fuel/server/payment.lua` | pagamento de combustivel | configuravel, normalizado para `wallet`, `bank` ou `dirty` |
| `mz_clothing` | `mz_clothing/server/main.lua` | compra/salvamento de roupa pago | `Config.MoneyType` ou `wallet` |
| `mz_tatto` | `mz_tatto/server/service.lua` | compra de tatuagem | `Config.MoneyType` ou `wallet` |
| `mz_org` | `mz_org/server/bank.lua` | deposito e saque de banco da organizacao | `bank` via exports de org account |

Esses recursos removem dinheiro do jogador ou transferem dinheiro para organizacao, mas nao passam metadata economica rica. Em uma economia auditavel, esses pontos devem informar categoria como `shop_expense`, `vehicle_expense`, `cosmetic_expense` ou `org_transfer`.

## Jobs legais

O core tem modelo de organizacoes do tipo `job`, cargos, duty e salario. As seeds incluem policia, ambulancia e mecanica com salarios. Nao encontrei sistemas atuais de recompensa por rotas, entregas, mineracao, pesca, coleta, venda em NPC ou missoes legais nos recursos `mz_*` auditados.

Conclusao: hoje o sistema legal de renda e basicamente folha salarial. O `mz_economy` deveria nascer classificando corretamente salario e preparando uma API para futuros jobs chamarem `AddMoney` com metadata.

## Fluxos ilegais

Existe a conta `dirty` em `mz_player_accounts` e existe uma organizacao seedada como gang/mafia. Porem, nos recursos `mz_*` atuais, nao encontrei sistemas ativos de drogas, roubo, heist, lavagem de dinheiro, venda ilegal ou geracao de dinheiro sujo.

O ponto de atencao e o recurso legado `celular/resource/smartphone`, que contem banco, PayPal e cassino fora do `mz_core`. Se esse recurso estiver ativo, ele pode criar, mover ou remover dinheiro fora do ledger oficial. Ele deve ser isolado, desligado ou adaptado antes de qualquer politica economica confiavel.

## Telefone, mensagens e email

Arquivos principais:

| Area | Arquivo | Observacao |
| --- | --- | --- |
| Config do telefone | `mz_phone/shared/config.lua` | depende de `mz_core`, sincroniza telefone com core |
| Integracao core | `mz_phone/server/framework.lua` | usa `ResolvePlayerIdentity`, `EnsurePlayerLoaded`, `SetPlayerPhoneByCitizenId` |
| Tabelas | `mz_phone/server/repository.lua` | numeros, contatos, conversas, mensagens, chamadas, galeria, apps, settings, notificacoes |
| Callbacks | `mz_phone/server/callbacks.lua` | notas, contatos, mensagens, chamadas, galeria, imobiliaria |

O `mz_phone` atual esta bem integrado a identidade do `mz_core`, mas nao possui email/mailbox propria. Existe `mz_phone_notifications`, que pode servir como canal inicial de notificacao para relatorios economicos ate existir um app de email.

Recomendacao: nao fazer `mz_economy` depender de email no MVP. Criar primeiro eventos/export genericos de notificacao economica e, no futuro, plugar email/app do telefone.

## Real estate, casas e propriedades

`mz_realestate` possui agencias, corretores, listings e solicitacoes de compra/aluguel, mas a auditoria nao encontrou movimentacao de dinheiro nesse recurso. `mz_houses` possui casas, chaves e logs, sem fluxo de pagamento atual.

Isso significa que imoveis ainda nao entram na economia real. Quando compra, aluguel, comissao e taxas forem implementados, devem ser obrigatoriamente registrados no ledger economico.

## QBCore / Qbox / compatibilidade

O `mz_core` nao depende diretamente de `qb-core` ou `qbx_core`. Ele fornece uma bridge QBCore-like em `mz_core/server/bridges/qb.lua`, com `GetCoreObject` e wrapper `Player.Functions.*`.

Isso e bom para adaptar scripts legados, mas cria um risco de classificacao: chamadas via `Player.Functions.AddMoney` podem chegar como `sourceType = qb_bridge` sem indicar o recurso real, categoria ou motivo confiavel.

Recomendacao:

- Manter compatibilidade antiga.
- Adicionar metadata opcional em novos wrappers.
- Usar `GetInvokingResource()` quando possivel para preencher `source_resource`.
- Default para chamadas antigas: `category = 'unknown'`, `counts_as_income = false`, `counts_as_expense = false`.

## Principais riscos

| Risco | Impacto | Prioridade |
| --- | --- | --- |
| Nao existe ledger economico dedicado | Relatorios de renda, inflacao e gasto ficam imprecisos | Alta |
| Exports de dinheiro nao aceitam metadata publica | Scripts externos nao conseguem classificar transacoes | Alta |
| Payroll credita banco direto | Perde padronizacao de auditoria por wrapper | Alta |
| `SetMoney` sem categoria | Pode criar/remover dinheiro sem contexto | Alta |
| Bridge QB sem origem detalhada | Scripts legados podem gerar renda como `unknown` | Media |
| `mz_logs` e generico | Busca e agregacao economica ficam caras/fracas | Media |
| `celular/resource/smartphone` legado | Pode bypassar totalmente `mz_core` se ativo | Alta |
| Sem agregacao diaria de playtime | Ganho por hora nao fica confiavel | Media |
| Sem controle de execucao diaria | Rotinas de preco podem duplicar apos restart | Media |

## Respostas objetivas

### Da para criar uma economia dinamica usando o que existe?

Sim, mas nao com confiabilidade plena apenas usando `mz_logs`. O core ja tem identidade, dinheiro, organizacoes, sessoes e telefone. Falta o ledger economico normalizado e classificacao obrigatoria dos fluxos.

### Onde centralizar?

Recomendacao: criar `mz_economy` separado e integrar com `mz_core`.

Motivo:

- Menor risco sobre o core.
- Facilita iterar relatorios e precos dinamicos.
- Mantem compatibilidade com scripts atuais.
- Permite que `mz_core` continue sendo camada de identidade/contas.

O `mz_core` deve receber apenas ajustes de API/wrapper quando chegar a fase de implementacao.

### O que contar como renda?

Contar como renda somente transacoes explicitamente classificadas como renda:

- `legal_job`
- `illegal_job`
- `salary`
- `business_revenue`
- `reward`
- `sale_to_npc`

Nao contar automaticamente:

- transferencia entre jogadores
- deposito/saque de organizacao
- saque de org para jogador
- `SetMoney` administrativo
- starter money
- reembolso
- ajuste manual
- compra de combustivel, roupa, tatuagem
- movimentacoes legadas sem origem confiavel

### O que precisa existir antes de precos dinamicos?

1. Ledger economico.
2. Categorias consistentes.
3. Playtime diario confiavel.
4. Relatorio de ganho/hora.
5. Preview manual de ajuste de precos.
6. Travas contra execucao duplicada.

Sem isso, precos dinamicos vao reagir a dados incompletos e podem punir ou inflar a economia de forma errada.

## Recomendacao final

Comecar por observabilidade. O primeiro MVP do `mz_economy` deve apenas registrar transacoes, classificar fontes e gerar relatorios. Depois disso, adaptar fuel/clothing/tattoos/payroll/orgs. So entao ativar precos dinamicos com preview e comando staff.
