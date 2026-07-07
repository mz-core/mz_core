# Validacao runtime - MZ_ECONOMY MVP 3A Org/Payroll

Data: 2026-06-23

## Ambiente

- Workspace local: `D:/git-hub/repo_oficial`
- Recursos revisados: `mz_core`, `mz_economy`
- Runtime FiveM/DB: nao executado nesta sessao
- Status desta validacao: PENDENTE

Esta validacao documenta a revisao local e o roteiro de runtime. Os testes reais em servidor FiveM ainda precisam ser executados antes de aprovar o MVP 3A.

## Arquivos revisados

- `mz_core/server/accounts/service.lua`
- `mz_core/server/accounts/org_accounts.lua`
- `mz_core/server/accounts/payroll.lua`
- `mz_core/server/accounts/commands.lua`
- `mz_core/docs/MZ_ECONOMY_MVP3A_ORG_PAYROLL.md`
- `mz_core/docs/CHECKLIST_IMPLANTACAO_ECONOMIA.md`
- `mz_economy/server/commands.lua`
- `mz_economy/server/service.lua`
- `mz_economy/server/repository.lua`

## Comandos locais executados

```txt
luac -p ./mz_core/server/accounts/service.lua ./mz_core/server/accounts/org_accounts.lua ./mz_core/server/accounts/payroll.lua ./mz_core/server/accounts/commands.lua
rg -n "mz_economy_prices|mz_economy_runs|mz_economy_daily_player_stats|income_per_hour|expense_per_hour|price_preview|apply_prices|CREATE TABLE|ALTER TABLE" mz_core/server/accounts mz_core/docs/MZ_ECONOMY_MVP3A_ORG_PAYROLL.md mz_economy/docs/README.md
rg -n "mz_economy_prices|mz_economy_runs|mz_economy_daily_player_stats|income_per_hour|expense_per_hour|price_preview|apply_prices|dynamic|preco|price|phone|email|qb_bridge|Player\.Functions|CREATE TABLE|ALTER TABLE" mz_core/server/accounts/service.lua mz_core/server/accounts/org_accounts.lua mz_core/server/accounts/payroll.lua mz_core/server/accounts/commands.lua
rg -n "org_transfer|admin_org_adjustment|payroll_salary|salary_expense|RecordEconomyTransactionSafe" mz_core/server/accounts mz_core/docs/MZ_ECONOMY_MVP3A_ORG_PAYROLL.md mz_core/docs/CHECKLIST_IMPLANTACAO_ECONOMIA.md mz_economy/docs/README.md
git diff --check -- server/accounts/service.lua server/accounts/org_accounts.lua server/accounts/payroll.lua server/accounts/commands.lua docs/CHECKLIST_IMPLANTACAO_ECONOMIA.md docs/MZ_ECONOMY_MVP3A_ORG_PAYROLL.md docs/VALIDACAO_MVP3A_ORG_PAYROLL_RUNTIME.md
```

Resultado local:

- `luac -p` passou.
- Busca de escopo proibido nos Lua de runtime nao encontrou tabelas novas, runs, ganho/hora, preco dinamico, jobs, phone/email ou bridge QB.
- Busca ampla em docs encontrou apenas mencoes de escopo/nao implementacao e categorias documentadas.
- `git diff --check` nao apontou erro de whitespace; apenas avisos normais de CRLF do Git no Windows.

## Resultado de deposito org

Runtime: nao executado.

Evidencia local esperada:

- `MZOrgAccountService.deposit` usa `MZAccountService.removeMoney` para debitar o jogador.
- O wrapper do jogador envia:
  - `category = org_transfer`
  - `reason = org_deposit`
  - `counts_as_income = false`
  - `counts_as_expense = false`
  - `related_org_code`
  - `external_ref`
- A contraparte da org registra:
  - `account = org`
  - `direction = transfer`
  - `category = org_transfer`
  - `counts_as_income = false`
  - `counts_as_expense = false`

Roteiro runtime pendente:

1. Garantir saldo bancario no jogador.
2. Depositar pelo fluxo normal da org.
3. Conferir saldo do jogador e da org.
4. Rodar `/mzecon_report`, `/mzecon_sources`, `/mzecon_unknown`.
5. Conferir SQL em `mz_economy_transactions`.

## Resultado de saque org

Runtime: nao executado.

Evidencia local esperada:

- `MZOrgAccountService.withdraw` debita a org e usa `MZAccountService.addMoney` para creditar o jogador.
- O wrapper do jogador envia:
  - `category = org_transfer`
  - `reason = org_withdraw`
  - `counts_as_income = false`
  - `counts_as_expense = false`
  - `related_org_code`
  - `external_ref`
- A contraparte da org registra:
  - `account = org`
  - `direction = transfer`
  - `category = org_transfer`
  - `counts_as_income = false`
  - `counts_as_expense = false`

Roteiro runtime pendente:

1. Garantir saldo na org.
2. Sacar pelo fluxo normal.
3. Conferir saldo do jogador e da org.
4. Rodar `/mzecon_report`, `/mzecon_sources`, `/mzecon_unknown`.
5. Conferir SQL em `mz_economy_transactions`.

## Resultado de admin org adjustment

Runtime: nao executado.

Evidencia local esperada:

- `AddOrgAccountBalance` registra:
  - `account = org`
  - `direction = adjustment`
  - `category = admin_org_adjustment`
  - `source_resource = mz_core`
  - `source_type = admin_command`
  - `counts_as_income = false`
  - `counts_as_expense = false`
- `RemoveOrgAccountBalance` usa a mesma categoria e flags.

Roteiro runtime pendente:

1. Rodar `mzorg_deposit [org] [amount]`.
2. Rodar `mzorg_withdraw [org] [amount]`.
3. Conferir saldo da org antes/depois.
4. Conferir ledger com `admin_org_adjustment`.

## Resultado de payroll com saldo

Runtime: nao executado.

Evidencia local esperada:

- `MZPayrollService.payCitizen` registra linha do jogador:
  - `account = bank`
  - `direction = in`
  - `category = salary`
  - `reason = payroll_salary`
  - `counts_as_income = true`
  - `counts_as_expense = false`
  - `related_org_code`
- Registra contraparte da org:
  - `account = org`
  - `direction = out`
  - `category = salary_expense`
  - `reason = payroll_salary_expense`
  - `counts_as_income = false`
  - `counts_as_expense = true`
  - `related_citizenid`
  - `related_org_code`
- As duas linhas usam o mesmo `external_ref`.

Roteiro runtime pendente:

1. Garantir player em org com grade salarial.
2. Garantir saldo suficiente na org.
3. Colocar duty se `Config.Payroll.requireDuty` exigir.
4. Rodar `mzpay_citizen [citizenid]` ou `mzpay_tick`.
5. Conferir saldo do jogador e da org.
6. Conferir ledger `salary` e `salary_expense`.

## Resultado de payroll sem saldo

Runtime: nao executado.

Evidencia local esperada:

- Se `balance < salary`, o fluxo nao chama `addBankMoney`.
- Sem pagamento, nao registra `salary`.
- Sem pagamento, nao registra `salary_expense`.
- A org nao fica negativa nesse ramo.

Roteiro runtime pendente:

1. Deixar a org abaixo do salario do cargo.
2. Rodar payroll.
3. Conferir que o bank do jogador nao mudou.
4. Conferir que o saldo da org nao mudou.
5. Conferir que nao nasceu ledger falso de salario.

## Resultado de mz_economy offline

Runtime: nao executado.

Evidencia local esperada:

- `RecordEconomyTransactionSafe` verifica `GetResourceState('mz_economy')`.
- Se `mz_economy` nao estiver `started`, retorna `false, economy_offline`.
- O retorno nao bloqueia org bank nem payroll.
- Wrappers `AddMoney`/`RemoveMoney` tambem ignoram ledger quando `mz_economy` esta offline.

Roteiro runtime pendente:

1. Rodar `stop mz_economy`.
2. Executar fluxo pequeno de org bank ou payroll controlado.
3. Confirmar que o saldo muda conforme regra do core.
4. Confirmar ausencia de erro fatal e duplicidade.
5. Rodar `ensure mz_economy`.
6. Confirmar que comandos `/mzecon_*` voltam a funcionar.

## Bugs encontrados e corrigidos

Nenhum bug defensivo foi corrigido nesta validacao local.

Foi ajustado apenas o status documental da checklist para nao marcar validacoes runtime como aprovadas antes do teste real.

## Arquivos alterados nesta validacao

- `mz_core/docs/VALIDACAO_MVP3A_ORG_PAYROLL_RUNTIME.md`
- `mz_core/docs/CHECKLIST_IMPLANTACAO_ECONOMIA.md`
- `mz_core/docs/MZ_ECONOMY_MVP3A_ORG_PAYROLL.md`
- `mz_economy/docs/README.md`

## Conclusao

PENDENTE.

Motivo: a revisao local e a validacao estatica passaram, mas os testes runtime FiveM/DB ainda nao foram executados.

## Proximo passo recomendado

Executar o roteiro runtime em servidor real com `oxmysql`, `mz_core`, `mz_economy` e `mz_org` iniciados. Se todos os cenarios passarem, atualizar esta conclusao para `APROVADO` e seguir para MVP 4 de relatorios/playtime/daily stats em modo preview, ainda sem preco dinamico.
