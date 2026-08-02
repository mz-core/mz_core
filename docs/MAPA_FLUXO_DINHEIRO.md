# Mapa de fluxo de dinheiro

Data da auditoria: 2026-06-23

Objetivo: mapear onde dinheiro nasce, sai, muda de dono ou e apenas registrado no ecossistema atual do `mz_core`.

## Contas conhecidas

| Conta | Origem | Observacao |
| --- | --- | --- |
| `wallet` | `mz_player_accounts.wallet` | Dinheiro em maos |
| `bank` | `mz_player_accounts.bank` | Dinheiro bancario |
| `dirty` | `mz_player_accounts.dirty` | Dinheiro sujo |
| org account | `mz_org_accounts.balance` | Saldo compartilhado de organizacao |

Aliases recomendados para futuro:

| Alias legado | Conta oficial |
| --- | --- |
| `cash` | `wallet` |
| `money` | `wallet` |
| `black_money` | `dirty` |
| `markedbills` | `dirty` ou item separado, conforme regra futura |

## Criacao ou entrada de dinheiro

| Tipo | Recurso | Arquivo | Funcao / evento / export | Valor / formula | Conta como renda? | Categoria sugerida | Observacao |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Starter money | `mz_core` | `mz_core/server/player/repository.lua` | `ensureAccount` | `Config.StarterMoney.wallet`, `bank`, `dirty` | Nao | `system_bootstrap` | Cria saldo inicial para novo `citizenid`. Nao deve entrar em ganho/hora. |
| AddMoney direto | `mz_core` | `mz_core/server/accounts/exports.lua` | `AddMoney(source, moneyType, amount)` | saldo atual + `amount` | So com metadata | `unknown` por compatibilidade | Export atual nao recebe categoria publica. |
| AddMoney service | `mz_core` | `mz_core/server/accounts/service.lua` | `MZAccountService.addMoney` | saldo atual + `amount` | So com metadata | depende do chamador | Internamente aceita `options`, mas export publico nao expoe metadata. |
| SetMoney acima do saldo | `mz_core` | `mz_core/server/accounts/exports.lua` | `SetMoney(source, moneyType, amount)` | saldo final absoluto | Nao por padrao | `admin_adjustment` | Pode criar dinheiro se o novo saldo for maior. Precisa ser classificado como ajuste. |
| QBCore bridge AddMoney | `mz_core` | `mz_core/server/bridges/qb.lua` | `Player.Functions.AddMoney` | saldo atual + `amount` | So com metadata | `qb_bridge_unknown` | Bom para compatibilidade, mas origem real pode ficar escondida. |
| Saque de org | `mz_core` / `mz_org` | `mz_core/server/accounts/org_accounts.lua` | `WithdrawOrgAccount` | org - amount, player bank + amount | Nao | `org_transfer` | Transferencia de saldo existente da org para jogador. |
| Payroll | `mz_core` | `mz_core/server/accounts/payroll.lua` | `PayCitizenSalary`, `RunPayrollTick` | salario do cargo, debitado da org | Como renda do jogador, nao como dinheiro criado | `salary` | Como debita `mz_org_accounts`, e transferencia economica. |
| Add org balance | `mz_core` | `mz_core/server/accounts/org_accounts.lua` | `AddOrgAccountBalance`, comando `mzorg_deposit` | org + amount | Nao | `admin_org_adjustment` | Cria saldo em org. Deve ser separado de receita real. |
| Reembolso de compra da org | `mz_core` / `mz_org_activities` | `mz_core/server/accounts/org_accounts.lua` | `RefundOrgAccount` | org + valor do recibo original | Nao | `org_facility_refund` | Compensacao idempotente; um recibo de gasto admite apenas um reembolso. |
| Legacy banco/PayPal/cassino | `celular` | `celular/resource/smartphone/server.js` | banco, PayPal, cassino | varia | Nao confiavel | `legacy_bypass` | Fora do `mz_core`. Se ativo, precisa isolamento/adaptacao. |

## Saida ou remocao de dinheiro

| Tipo | Recurso | Arquivo | Funcao / evento / export | Valor / formula | Conta como despesa? | Categoria sugerida | Observacao |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RemoveMoney direto | `mz_core` | `mz_core/server/accounts/exports.lua` | `RemoveMoney(source, moneyType, amount)` | saldo atual - `amount` | So com metadata | `unknown` por compatibilidade | Export atual nao recebe categoria publica. |
| RemoveMoney service | `mz_core` | `mz_core/server/accounts/service.lua` | `MZAccountService.removeMoney` | saldo atual - `amount` | So com metadata | depende do chamador | Base correta para wrapper futuro. |
| SetMoney abaixo do saldo | `mz_core` | `mz_core/server/accounts/exports.lua` | `SetMoney(source, moneyType, amount)` | saldo final absoluto | Nao por padrao | `admin_adjustment` | Pode remover dinheiro sem representar gasto real. |
| QBCore bridge RemoveMoney | `mz_core` | `mz_core/server/bridges/qb.lua` | `Player.Functions.RemoveMoney` | saldo atual - `amount` | So com metadata | `qb_bridge_unknown` | Precisa capturar recurso invocador e motivo. |
| Combustivel | `mz_fuel` | `mz_fuel/server/payment.lua` | `chargePlayer` | `amount` informado pelo abastecimento | Sim | `vehicle_expense` | Remove de conta configurada. |
| Roupa | `mz_clothing` | `mz_clothing/server/main.lua` | `chargeIfNeeded` | preco configurado da acao | Sim | `cosmetic_expense` | Remove `Config.MoneyType` ou `wallet`. |
| Tatuagem | `mz_tatto` | `mz_tatto/server/service.lua` | compra/salvamento de tatuagem | soma dos precos de tatuagens novas | Sim | `cosmetic_expense` | Remove `Config.MoneyType` ou `wallet`. |
| Deposito em org | `mz_core` / `mz_org` | `mz_core/server/accounts/org_accounts.lua` | `DepositOrgAccount` | player bank - amount, org + amount | Nao | `org_transfer` | Transferencia entre jogador e org. |
| Remove org balance | `mz_core` | `mz_core/server/accounts/org_accounts.lua` | `RemoveOrgAccountBalance`, comando `mzorg_withdraw` | org - amount | Nao | `admin_org_adjustment` | Remove saldo de org sem representar despesa real. |
| Compra de instalacao da org | `mz_core` / `mz_org_activities` | `mz_core/server/accounts/org_accounts.lua` | `SpendOrgAccount` | org - preco autoritativo | Sim | `org_facility_purchase` | Debito idempotente com recibo; nao reutiliza ajuste administrativo. |
| Payroll debit | `mz_core` | `mz_core/server/accounts/payroll.lua` | `payCitizen` | org - salario | Sim para org | `salary_expense` | Contraparte do credito salarial ao jogador. |

## Transferencias que nao devem ser renda liquida

| Fluxo | Origem | Destino | Contar como renda? | Motivo |
| --- | --- | --- | --- | --- |
| Jogador deposita em org | player `bank` | `mz_org_accounts` | Nao | Dinheiro apenas mudou de dono. |
| Jogador saca de org | `mz_org_accounts` | player `bank` | Nao por padrao | Transferencia de saldo existente. |
| Payroll | `mz_org_accounts` | player `bank` | Sim como renda do jogador; nao como dinheiro criado | Salario e renda individual, mas nao emite dinheiro se org foi debitada. |
| Starter money | sistema | player | Nao | Bootstrap inicial. |
| Admin SetMoney | staff/sistema | player | Nao | Ajuste manual nao representa atividade economica. |
| Admin AddOrgBalance | staff/sistema | org | Nao | Ajuste manual de org. |
| Compra de fuel/clothing/tattoos | player | sistema/loja | Nao | E despesa, nao renda. |
| Real estate request atual | nenhum | nenhum | Nao | Hoje nao ha movimentacao financeira encontrada. |
| Telefone atual | nenhum | nenhum | Nao | `mz_phone` nao tem banco/email/economia. |
| Legacy banco/PayPal | legado | legado | Nao confiavel | Fora do ledger oficial. |

## Tabelas atuais relevantes

| Tabela | Arquivo de criacao | Uso economico |
| --- | --- | --- |
| `mz_players` | `mz_core/server/prepare.lua` | Identidade do jogador |
| `mz_player_accounts` | `mz_core/server/prepare.lua` | Saldo `wallet`, `bank`, `dirty` |
| `mz_player_sessions` | `mz_core/server/prepare.lua` | Base para playtime |
| `mz_orgs` | `mz_core/server/prepare.lua` | Organizacoes/jobs/gangs |
| `mz_org_grades` | `mz_core/server/prepare.lua` | Salarios por cargo |
| `mz_player_orgs` | `mz_core/server/prepare.lua` | Membro, duty, grade |
| `mz_org_accounts` | `mz_core/server/prepare.lua` | Saldo de org |
| `mz_org_account_transactions` | `mz_core/server/prepare.lua` | Historico de conta da org |
| `mz_logs` | `mz_core/server/prepare.lua` | Log generico |
| `mz_phone_notifications` | `mz_phone/server/repository.lua` | Canal futuro de aviso |

## Tabelas ausentes para economia dinamica

| Tabela sugerida | Motivo |
| --- | --- |
| `mz_economy_transactions` | Ledger normalizado de toda entrada, saida e transferencia |
| `mz_economy_daily_player_stats` | Ganho por hora, despesa por hora, tempo ativo |
| `mz_economy_prices` | Precos dinamicos por item/servico/recurso |
| `mz_economy_runs` | Controle de execucao diaria e anti-duplicidade |
| `mz_economy_reports` | Snapshots diarios para staff |

## Politica recomendada de classificacao

| Categoria | Direction | Conta como renda | Conta como despesa | Exemplo |
| --- | --- | --- | --- | --- |
| `legal_job` | `in` | Sim | Nao | entrega, coleta, recompensa legal |
| `illegal_job` | `in` | Sim | Nao | venda ilegal, roubo, heist |
| `salary` | `in` | Sim para jogador | Nao | payroll |
| `business_revenue` | `in` | Sim | Nao | venda de empresa |
| `shop_expense` | `out` | Nao | Sim | compra em loja |
| `vehicle_expense` | `out` | Nao | Sim | combustivel/reparo |
| `cosmetic_expense` | `out` | Nao | Sim | roupa/tatuagem |
| `org_transfer` | `transfer` | Nao | Nao | deposito/saque de org |
| `player_transfer` | `transfer` | Nao | Nao | transferencia entre jogadores |
| `admin_adjustment` | `adjustment` | Nao | Nao | set/add manual |
| `system_bootstrap` | `adjustment` | Nao | Nao | starter money |
| `refund` | `in` | Nao por padrao | Nao | devolucao de compra |
| `unknown` | varia | Nao | Nao | chamada antiga sem metadata |

## Fontes que devem ser adaptadas primeiro

1. `mz_core/server/accounts/exports.lua`
2. `mz_core/server/accounts/service.lua`
3. `mz_core/server/accounts/payroll.lua`
4. `mz_core/server/accounts/org_accounts.lua`
5. `mz_core/server/bridges/qb.lua`
6. `mz_fuel/server/payment.lua`
7. `mz_clothing/server/main.lua`
8. `mz_tatto/server/service.lua`
9. `mz_org/server/bank.lua`

## Regra de ouro

Toda mudanca de saldo deve responder:

1. Quem recebeu ou perdeu?
2. Qual conta mudou?
3. Quanto mudou?
4. O dinheiro foi criado, removido ou transferido?
5. Qual recurso chamou?
6. Qual categoria economica?
7. Deve contar para ganho/hora?
8. Deve contar para despesa/hora?
9. Existe contraparte?
10. O evento e reversivel/auditavel?
