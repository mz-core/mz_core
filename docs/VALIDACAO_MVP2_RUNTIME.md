# Validacao runtime - MZ Economy MVP 2

Data: 2026-06-23

Escopo: validar os wrappers metadata-aware de dinheiro do `mz_core` integrados ao ledger passivo do `mz_economy`.

Esta validacao nao implementa preco dinamico, ganho/hora, daily runs, payroll, org bank, fuel, clothing, tattoos, bridge QB, telefone, jobs ou alteracoes no schema de `mz_player_accounts`.

## Arquivos revisados

- `mz_core/server/accounts/service.lua`
- `mz_core/server/accounts/exports.lua`
- `mz_core/docs/MZ_ECONOMY_MVP2_WRAPPERS.md`
- `mz_economy/server/service.lua`
- `mz_economy/server/repository.lua`
- `mz_economy/server/commands.lua`
- `mz_economy/docs/VALIDACAO_MVP1.md`

## Status da validacao estatica

| Item | Status | Observacao |
| --- | --- | --- |
| Chamadas antigas de `AddMoney` | OK | Export aceita 3 argumentos e metadata e opcional |
| Chamadas antigas de `RemoveMoney` | OK | Export aceita 3 argumentos e metadata e opcional |
| Chamadas antigas de `SetMoney` | OK | Export aceita 3 argumentos e metadata e opcional |
| Chamadas novas com metadata | OK | 4o argumento e repassado ao service |
| Ledger depois do saldo | OK | `RecordTransaction` e chamado apos `updatePlayerMoney` e cache atualizado |
| Falha do `mz_economy` | OK em codigo | `GetResourceState` checa `started`; chamada usa `pcall` |
| Retry infinito | OK | Nao existe retry/loop de ledger |
| Balance before/after | OK em codigo | Usa saldo antes do update e saldo final aplicado |
| `SetMoney` com saldo igual | OK | Nao registra ledger quando delta e zero |
| Chamada antiga como `unknown` | OK | Add/Remove defaultam categoria `unknown` |
| `SetMoney` default | OK | Categoria padrao `admin_adjustment` |
| Metadata `nil` | OK | Vira tabela vazia/contexto legado |
| Metadata nao-tabela | OK | Preservada como `raw_metadata` |
| `source_resource` | OK | Usa metadata, `GetInvokingResource()` ou fallback |
| Aliases de conta | OK | `cash/money -> wallet`, `black_money -> dirty` |
| Conta invalida | OK | Recusada antes de update e antes do ledger |
| Preco dinamico | OK | Nao implementado |
| `mz_economy_prices` | OK | Nao criado |
| Payroll/org/fuel/clothing/tattoos/QB | OK | Nao alterados neste ciclo |
| Schema de `mz_player_accounts` | OK | Nao alterado |

## Bug encontrado e corrigido

### Campos internos de ledger em metadata publica

Durante a revisao estatica foi encontrado um risco defensivo: um chamador externo poderia tentar enviar campos internos como `__ledgerDirection` em metadata de `SetMoney` e alterar a direction do ledger.

Correcao:

- `SetMoney` agora sempre usa `direction = 'adjustment'`, exceto quando chamado internamente por `addMoney`/`removeMoney`.
- `addMoney` e `removeMoney` marcam chamadas internas com `__ledgerFromWrapper = true`.
- `__ledgerDirection` e `__ledgerAmount` so sao aceitos quando `__ledgerFromWrapper == true`.

Impacto:

- Nao muda regra de saldo.
- Nao muda retorno externo.
- Evita classificacao indevida de `SetMoney` como entrada/saida.

## Fluxo confirmado em codigo

### `AddMoney`

1. Valida player carregado.
2. Normaliza conta.
3. Valida amount positivo.
4. Le saldo atual.
5. Chama `setMoney` com saldo atual + valor.
6. `setMoney` grava no banco.
7. Atualiza cache `player.money`.
8. Registra log generico.
9. Registra ledger com `direction = 'in'`.
10. Retorna `true` ou `false, erro` no contrato antigo.

### `RemoveMoney`

1. Valida player carregado.
2. Normaliza conta.
3. Valida amount positivo.
4. Confere saldo suficiente.
5. Chama `setMoney` com saldo atual - valor.
6. `setMoney` grava no banco.
7. Atualiza cache `player.money`.
8. Registra log generico.
9. Registra ledger com `direction = 'out'`.
10. Retorna `true` ou `false, erro` no contrato antigo.

### `SetMoney`

1. Valida player carregado.
2. Normaliza conta.
3. Valida amount >= 0.
4. Le saldo antes.
5. Grava saldo final.
6. Atualiza cache.
7. Registra log generico.
8. Se delta != 0, registra ledger com `direction = 'adjustment'`.
9. Se delta == 0, nao registra ledger inutil.
10. Retorna `true` ou `false, erro` no contrato antigo.

## Roteiro de teste manual no servidor

### 1. Configuracao

No `server.cfg`:

```cfg
ensure oxmysql
ensure mz_core
ensure mz_economy

add_ace group.mz_owner command allow
add_ace group.mz_owner command.quit deny
add_ace group.mz_owner group.mz_owner allow

add_principal identifier.fivem:SEU_ID_FIVEM_AQUI group.mz_owner
add_principal identifier.fivem:ID_DO_SOCIO_AQUI group.mz_owner
```

### 2. Subida dos recursos

Confirmar:

- Console sem erro de `fxmanifest`.
- Console sem erro de `oxmysql`.
- Console sem erro de export.
- `mz_economy` imprime `[mz_economy] passive ledger ready`.
- Jogador consegue entrar e carregar pelo `mz_core`.

### 3. Teste legado AddMoney

Executar em comando/dev helper seguro server-side:

```lua
exports['mz_core']:AddMoney(source, 'wallet', 100)
```

Esperado:

- saldo `wallet` aumenta 100.
- ledger registra uma linha.
- `direction = in`.
- `account = wallet`.
- `category = unknown`.
- `counts_as_income = 0`.
- `counts_as_expense = 0`.
- `balance_before` e `balance_after` preenchidos.

### 4. Teste metadata AddMoney

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

- saldo aumenta 100.
- ledger registra `category = legal_job`.
- `reason = manual_metadata_test`.
- `source_resource = manual_test`.
- `source_type = dev_test`.
- `counts_as_income = 1`.
- `counts_as_expense = 0`.

### 5. Teste RemoveMoney

```lua
exports['mz_core']:RemoveMoney(source, 'wallet', 50, {
  reason = 'manual_expense_test',
  category = 'shop_expense',
  source_resource = 'manual_test',
  source_type = 'dev_test',
  counts_as_income = false,
  counts_as_expense = true
})
```

Esperado:

- saldo reduz 50.
- ledger registra `direction = out`.
- `category = shop_expense`.
- `counts_as_expense = 1`.
- `balance_before - balance_after = 50`.

### 6. Teste SetMoney

```lua
exports['mz_core']:SetMoney(source, 'wallet', 1000)
```

Esperado:

- saldo `wallet` vira 1000.
- ledger registra `direction = adjustment`.
- `category = admin_adjustment`.
- `counts_as_income = 0`.
- `counts_as_expense = 0`.
- `amount` no ledger e a diferenca absoluta, nao o saldo final.

Rodar novamente com o mesmo valor:

```lua
exports['mz_core']:SetMoney(source, 'wallet', 1000)
```

Esperado:

- saldo permanece 1000.
- nenhuma transacao inutil e registrada para delta zero.

### 7. Teste aliases

```lua
exports['mz_core']:AddMoney(source, 'cash', 10)
exports['mz_core']:AddMoney(source, 'money', 10)
exports['mz_core']:AddMoney(source, 'black_money', 10)
```

Esperado:

- `cash` entra como `wallet`.
- `money` entra como `wallet`.
- `black_money` entra como `dirty`.

Teste conta invalida:

```lua
exports['mz_core']:AddMoney(source, 'invalid_account', 10)
```

Esperado:

- retorna `false, 'invalid_money_type'`.
- saldo nao muda.
- ledger nao registra linha falsa.

### 8. Teste mz_economy offline

1. Parar `mz_economy`.
2. Rodar:

```lua
exports['mz_core']:AddMoney(source, 'wallet', 10)
```

Esperado:

- saldo aumenta.
- `mz_core` nao quebra.
- nenhum erro fatal.
- no maximo log defensivo se `Config.Debug = true`.
- sem retry infinito.

3. Reiniciar `mz_economy`.
4. Confirmar que `/mzecon_report` volta a funcionar.

### 9. Teste comandos do mz_economy

Com `mz_economy` ligado:

```txt
/mzecon_report
/mzecon_unknown
/mzecon_sources
```

Esperado:

- report lista totais.
- unknown lista chamadas antigas/categoria `unknown`.
- sources mostra `source_resource` conforme metadata ou recurso invocador.

## Consultas SQL uteis

Ultimas transacoes:

```sql
SELECT id, citizenid, account, amount, direction, category, reason,
       source_resource, source_type, counts_as_income, counts_as_expense,
       balance_before, balance_after, created_at
FROM mz_economy_transactions
ORDER BY id DESC
LIMIT 20;
```

Unknown do dia:

```sql
SELECT id, citizenid, account, amount, direction, source_resource, reason, created_at
FROM mz_economy_transactions
WHERE category = 'unknown'
  AND created_at >= CURDATE()
ORDER BY id DESC
LIMIT 20;
```

## Pontos que so podem ser confirmados no runtime real

- Se `GetInvokingResource()` retorna o recurso esperado em cada caminho de chamada.
- Se `mz_economy` esta `started` no momento exato das primeiras chamadas apos restart.
- Se `RecordTransaction` insere corretamente no banco real.
- Se `/mzecon_report`, `/mzecon_unknown` e `/mzecon_sources` renderizam bem no chat/console.
- Se o player de teste esta no grupo `group.mz_owner`.
- Se o log de falha em `mz_logs` ocorre corretamente quando `RecordTransaction` falha.

## Riscos restantes

- Chamadas internas que passam por `MZAccountService` agora tambem podem gerar ledger, mesmo que o arquivo chamador nao tenha sido adaptado explicitamente.
- Fontes antigas sem metadata ainda entram como `unknown`, como esperado para compatibilidade.
- Runtime FiveM/oxmysql ainda precisa confirmar o comportamento real com resources parados/reiniciados.

## Status para MVP 3

Do ponto de vista estatico, o MVP 2 esta apto para validacao runtime e, se os testes manuais acima passarem, pode seguir para MVP 3.

Proxima fase recomendada:

- adaptar gastos simples (`mz_fuel`, `mz_clothing`, `mz_tatto`) com metadata explicita, ou
- adaptar payroll/org bank primeiro se a prioridade for salario e caixa de organizacao.
