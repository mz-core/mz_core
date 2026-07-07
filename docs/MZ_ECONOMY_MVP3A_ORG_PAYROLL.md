# MZ_ECONOMY MVP 3A - Org bank e payroll

## Objetivo

Adaptar os fluxos existentes de banco de organizacao e payroll para alimentar o ledger passivo do `mz_economy`, mantendo as regras atuais de saldo, permissao e pagamento.

Este MVP nao altera precos, jobs, phone/email, bridge QB, fuel, clothing, tattoos, schema do `mz_economy`, ganho por hora, daily runs ou relatorios novos.

## Arquivos alterados

- `mz_core/server/accounts/service.lua`
- `mz_core/server/accounts/org_accounts.lua`
- `mz_core/server/accounts/payroll.lua`

## Helper de ledger

Foi adicionado `MZAccountService.RecordEconomyTransactionSafe(data)` para fluxos que precisam registrar ledger sem necessariamente passar por `AddMoney`/`RemoveMoney`.

Caracteristicas:

- chama `exports['mz_economy']:RecordTransaction(data)` somente se `mz_economy` estiver iniciado;
- usa `pcall`;
- nao bloqueia a mudanca de saldo se o ledger falhar;
- registra falhas em `print` e em `MZLogService`, quando disponivel.

## Org bank

### Deposito player -> org

O fluxo continua:

1. valida jogador, org, permissao e saldo bancario;
2. remove dinheiro do `bank` do jogador via `MZAccountService.removeMoney`;
3. soma o valor em `mz_org_accounts`;
4. registra `mz_org_account_transactions`.

Ledger gerado:

- lado jogador: wrapper `RemoveMoney`, `direction = out`, `category = org_transfer`;
- lado org: registro explicito, `account = org`, `direction = transfer`, `category = org_transfer`;
- ambos usam o mesmo `external_ref`;
- `counts_as_income = false`;
- `counts_as_expense = false`.

### Saque org -> player

O fluxo continua:

1. valida jogador, org, permissao e saldo da org;
2. debita `mz_org_accounts`;
3. adiciona dinheiro ao `bank` do jogador via `MZAccountService.addMoney`;
4. registra `mz_org_account_transactions`.

Ledger gerado:

- lado jogador: wrapper `AddMoney`, `direction = in`, `category = org_transfer`;
- lado org: registro explicito, `account = org`, `direction = transfer`, `category = org_transfer`;
- ambos usam o mesmo `external_ref`;
- `counts_as_income = false`;
- `counts_as_expense = false`.

### Ajustes administrativos

`AddOrgAccountBalance` e `RemoveOrgAccountBalance` continuam alterando diretamente `mz_org_accounts`.

Ledger gerado:

- `account = org`;
- `direction = adjustment`;
- `category = admin_org_adjustment`;
- `source_resource = mz_core`;
- `source_type = admin_command`;
- `counts_as_income = false`;
- `counts_as_expense = false`.

Os comandos existentes que chamam esses exports continuam sem contar como renda operacional.

## Payroll

O payroll continua pagando por `citizenid`, inclusive para jogador offline. Por isso o credito bancario do salario continua no fluxo SQL atual em vez de exigir wrapper por `source`.

Para cada salario pago com sucesso:

- jogador recebe linha:
  - `account = bank`
  - `direction = in`
  - `category = salary`
  - `reason = payroll_salary`
  - `source_type = payroll`
  - `counts_as_income = true`
- org recebe linha de contraparte:
  - `account = org`
  - `direction = out`
  - `category = salary_expense`
  - `reason = payroll_salary_expense`
  - `source_type = payroll`
  - `counts_as_expense = true`
- ambas as linhas usam o mesmo `external_ref`;
- metadata inclui org, grade/cargo, salario, duty e `require_duty`.

## Garantias de escopo

- Nenhuma tabela nova foi criada.
- Nenhum preco dinamico foi criado.
- Nenhum job novo foi criado.
- Nenhum fluxo de phone/email foi criado.
- Nenhum recurso de gasto foi alterado neste MVP.
- Nenhuma regra de permissao de org bank foi alterada.
- Payroll manteve pagamento por `citizenid`.

## Validacao sugerida

Status runtime em 2026-06-23: PENDENTE.

Roteiro detalhado em `mz_core/docs/VALIDACAO_MVP3A_ORG_PAYROLL_RUNTIME.md`.

1. Depositar dinheiro em org e conferir:
   - jogador com `category = org_transfer`;
   - org com `account = org`;
   - mesmo `external_ref`;
   - ambos sem income/expense.
2. Sacar dinheiro da org e conferir as mesmas propriedades.
3. Rodar `AddOrgAccountBalance` ou comando admin equivalente e confirmar `admin_org_adjustment`.
4. Rodar `RemoveOrgAccountBalance` ou comando admin equivalente e confirmar `admin_org_adjustment`.
5. Rodar payroll e confirmar:
   - `salary` no jogador com `counts_as_income = true`;
   - `salary_expense` na org com `counts_as_expense = true`;
   - mesmo `external_ref`;
   - metadata com org e cargo.

## Observacao

O ledger permanece passivo. A verdade de saldo continua nas tabelas atuais do `mz_core`.
