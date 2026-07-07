# MZ Economy MVP 2 - wrappers metadata-aware

Data: 2026-06-23

Escopo: adicionar metadata opcional aos wrappers de dinheiro do `mz_core` e registrar mudancas de saldo no ledger passivo do `mz_economy`.

## Arquivos alterados

- `mz_core/server/accounts/service.lua`
- `mz_core/server/accounts/exports.lua`

Nao foram alterados neste MVP:

- `mz_core/server/accounts/payroll.lua`
- `mz_core/server/accounts/org_accounts.lua`
- `mz_core/server/bridges/qb.lua`
- `mz_fuel`
- `mz_clothing`
- `mz_tatto`
- tabelas de preco
- rotinas diarias
- calculo de ganho/hora

## Exports publicos

Chamadas antigas continuam validas:

```lua
exports['mz_core']:AddMoney(source, 'wallet', 100)
exports['mz_core']:RemoveMoney(source, 'wallet', 100)
exports['mz_core']:SetMoney(source, 'wallet', 1000)
```

Chamadas novas aceitam metadata opcional:

```lua
exports['mz_core']:AddMoney(source, 'wallet', 100, {
  reason = 'manual_metadata_test',
  category = 'legal_job',
  source_resource = 'manual_test',
  source_type = 'dev_test',
  counts_as_income = true,
  counts_as_expense = false,
  data = {
    note = 'mvp2 test'
  }
})
```

Tambem foi exposto:

```lua
exports['mz_core']:NormalizeMoneyAccount(account)
```

## Contas e aliases

Contas oficiais:

- `wallet`
- `bank`
- `dirty`

Aliases normalizados:

- `cash` -> `wallet`
- `money` -> `wallet`
- `black_money` -> `dirty`

`markedbills` nao foi normalizado neste MVP para evitar conflito se o projeto tratar isso como item separado.

## Metadata

Formato recomendado:

```lua
{
  reason = 'string',
  category = 'unknown',
  source_resource = 'resource_name',
  source_type = 'core',
  counts_as_income = false,
  counts_as_expense = false,
  related_citizenid = nil,
  related_org_code = nil,
  external_ref = nil,
  data = {}
}
```

Regras:

- Metadata `nil` vira chamada legada.
- Metadata nao-tabela e preservada em `data.raw_metadata`.
- Categoria vazia em `AddMoney`/`RemoveMoney` vira `unknown`.
- Categoria vazia em `SetMoney` vira `admin_adjustment`.
- Chamadas antigas nao contam como income nem expense.
- `source_resource` usa metadata, depois `GetInvokingResource()`, depois fallback seguro.

## Ledger

O ledger e chamado apenas depois de a alteracao de saldo ser aplicada com sucesso.

Mapeamento:

- `AddMoney` -> `direction = 'in'`
- `RemoveMoney` -> `direction = 'out'`
- `SetMoney` -> `direction = 'adjustment'`

`SetMoney` registra apenas a diferenca absoluta. Se o saldo final for igual ao saldo anterior, nenhum ledger e registrado.

O payload enviado para `mz_economy` inclui:

- `citizenid`
- `license`
- `account`
- `amount`
- `balance_before`
- `balance_after`
- `direction`
- `category`
- `reason`
- `source_resource`
- `source_type`
- `counts_as_income`
- `counts_as_expense`
- `related_citizenid`
- `related_org_code`
- `external_ref`
- `metadata`

## Se mz_economy estiver offline

O `mz_core` continua funcionando normalmente.

Comportamento:

- `AddMoney`, `RemoveMoney` e `SetMoney` continuam alterando saldo pelo fluxo atual.
- O ledger e ignorado quando `mz_economy` nao esta `started`.
- Falhas de `RecordTransaction` sao capturadas com `pcall`.
- Falhas do ledger geram log visivel no console e tentativa de registro em `mz_logs`.
- O saldo nao e revertido nem duplicado por falha do ledger.

## Compatibilidade

O retorno externo dos exports foi preservado:

- sucesso: `true`
- falha: `false, 'erro'`

Scripts antigos que chamam com tres argumentos continuam funcionando.

## Limitacoes do MVP 2

- Nao adapta payroll.
- Nao adapta org bank diretamente.
- Nao adapta fuel, clothing ou tattoos diretamente.
- Nao altera bridge QB diretamente.
- Nao cria ganho/hora.
- Nao cria preco dinamico.
- Nao cria `mz_economy_prices`, `mz_economy_runs` ou daily stats.
- Nao cria email/celular.

Observacao: qualquer fluxo que ja use `MZAccountService.addMoney`, `removeMoney` ou `setMoney` pode passar a gerar ledger por causa da centralizacao no service. Nenhum arquivo desses fluxos foi alterado neste MVP.

## Testes manuais sugeridos

Com recursos:

```cfg
ensure oxmysql
ensure mz_core
ensure mz_economy
```

Teste chamada antiga:

```lua
exports['mz_core']:AddMoney(source, 'wallet', 100)
```

Esperado:

- saldo aumenta
- ledger registra `direction = in`
- `category = unknown`
- `counts_as_income = 0`
- `counts_as_expense = 0`

Teste chamada nova:

```lua
exports['mz_core']:AddMoney(source, 'wallet', 100, {
  reason = 'manual_metadata_test',
  category = 'legal_job',
  source_resource = 'manual_test',
  source_type = 'dev_test',
  counts_as_income = true,
  counts_as_expense = false,
  data = { note = 'mvp2 test' }
})
```

Esperado:

- saldo aumenta
- ledger registra `category = legal_job`
- `counts_as_income = 1`
- `source_resource = manual_test`

Teste sem ledger:

1. Parar `mz_economy`.
2. Rodar `AddMoney` ou `RemoveMoney`.
3. Confirmar que saldo continua funcionando.
4. Reiniciar `mz_economy`.

## Proxima fase recomendada

MVP 3 deve adaptar explicitamente os fluxos atuais que geram ou removem dinheiro:

- payroll
- org bank
- fuel
- clothing
- tattoos
- bridge QB, se for necessario enriquecer origem/categoria

Ordem sugerida: adaptar primeiro gastos simples (`fuel`, `clothing`, `tattoos`) ou org/payroll, dependendo do que for mais usado no servidor.
