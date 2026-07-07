# Validacao runtime - MZ Economy MVP 3B gastos

Data: 2026-06-23

Escopo: validar estaticamente e preparar o teste runtime dos gastos adaptados no MVP 3B:

- `mz_fuel`
- `mz_clothing`
- `mz_tatto`

Esta validacao nao implementa preco dinamico, ganho por hora, daily runs, `mz_economy_prices`, payroll, org bank, bridge QB, jobs legais/ilegais, telefone, email ou novas tabelas.

## Arquivos revisados

- `mz_core/docs/MZ_ECONOMY_MVP3B_GASTOS.md`
- `mz_core/docs/MZ_ECONOMY_MVP2_WRAPPERS.md`
- `mz_core/docs/VALIDACAO_MVP2_RUNTIME.md`
- `mz_core/docs/MAPA_FLUXO_DINHEIRO.md`
- `mz_core/docs/CHECKLIST_IMPLANTACAO_ECONOMIA.md`
- `mz_economy/docs/VALIDACAO_MVP1.md`
- `mz_economy/docs/README.md`
- `mz_fuel/server/payment.lua`
- `mz_clothing/server/main.lua`
- `mz_tatto/server/service.lua`
- `mz_core/server/accounts/service.lua`
- `mz_core/server/accounts/exports.lua`
- `mz_economy/server/service.lua`
- `mz_economy/server/commands.lua`

## Resultado da validacao estatica

| Item | Status | Observacao |
| --- | --- | --- |
| `mz_fuel` usa `RemoveMoney` do `mz_core` | OK | Chamada em `mz_fuel/server/payment.lua` com metadata |
| `mz_clothing` usa `RemoveMoney` do `mz_core` | OK | Chamada em `mz_clothing/server/main.lua` com metadata |
| `mz_tatto` usa `RemoveMoney` do `mz_core` | OK | Chamada em `mz_tatto/server/service.lua` com metadata |
| Chamada direta a `RecordTransaction` nos tres recursos | OK | Nenhuma ocorrencia encontrada |
| Fuel category/reason | OK | `vehicle_expense` / `fuel_purchase` |
| Clothing category/reason | OK | `cosmetic_expense` / `clothing_purchase` |
| Tattoo category/reason | OK | `cosmetic_expense` / `tattoo_purchase` |
| `counts_as_income` | OK | Todos os tres usam `false`; nenhum `true` foi encontrado nos gastos |
| `counts_as_expense` | OK | Todos os tres usam `true` |
| `source_resource` | OK | `mz_fuel`, `mz_clothing`, `mz_tatto` |
| Variaveis opcionais em metadata | OK | Fuel protege `context`; clothing usa `shopId` ja calculado; tattoo usa `payload.shopId` apos validar payload tabela |
| Sintaxe Lua | OK | `luac -p` passou nos arquivos revisados |
| Preco dinamico e tabelas novas | OK | Nao encontrado nos arquivos dos gastos |
| Payroll/org/bridge QB | OK | Sem alteracao em `payroll.lua`, `org_accounts.lua` e `qb.lua` |

## Fechamento runtime

Data do teste registrado: 2026-06-23

| Item | Status runtime | Evidencia |
| --- | --- | --- |
| `mz_fuel` | APROVADO | `/mzecon_sources` e `/mzecon_report` mostraram `source=mz_fuel`, `tx=16`, `in=0`, `out=80`, `unknown=0`, `category=vehicle_expense`, `expense=80`, `income=0` |
| `mz_clothing` | NAO APLICAVEL NO RUNTIME ATUAL | Fluxo gratuito: `Config.UseMoney = false` em `mz_clothing/shared/config.lua`; nenhuma transacao no ledger e esperada enquanto nao houver cobranca real |
| `mz_tatto` | NAO APLICAVEL NO RUNTIME ATUAL | Fluxo gratuito: `Config.UseMoney = false` em `mz_tatto/shared/config.lua`; nenhuma transacao no ledger e esperada enquanto nao houver cobranca real |
| `mz_money_add` | APROVADO | Comando console-only registrou `source=mz_core`, `category=admin_adjustment`, `direction=in`, `counts_as_income=0`, `counts_as_expense=0`, `unknown=0` |
| Saldo insuficiente com `mz_fuel` | PENDENTE | Aguardando teste real confirmando que saldo nao fica negativo e ledger nao registra compra falsa |
| `mz_economy` offline com `mz_fuel` | PENDENTE | Aguardando teste real com `stop mz_economy`, abastecimento pequeno e `ensure mz_economy` |

### Comando auxiliar para testes de saldo

Foi criado o comando console-only `mz_money_add` no `mz_core` para facilitar testes runtime sem abrir comando de dinheiro para player.

Uso:

```txt
mz_money_add <source> <wallet|bank|dirty|cash|money|black_money> <amount> [reason]
```

Exemplo:

```txt
mz_money_add 1 wallet 1000 teste_runtime
```

Regras:

- somente console do servidor (`source == 0`);
- player nao pode usar pelo chat;
- aceita apenas source online carregado no `mz_core` neste MVP;
- registra via wrapper oficial como `admin_adjustment`;
- nao conta como income;
- nao conta como expense;
- nao substitui os testes pendentes de clothing, tattoo, saldo insuficiente e `mz_economy` offline.

Resultado runtime confirmado:

- `mz_money_add 1 wallet 10000 teste_runtime` executado pelo console;
- `source_resource = mz_core`;
- `source_type = console_command`;
- `category = admin_adjustment`;
- `direction = in`, por usar `AddMoney`;
- `counts_as_income = 0`;
- `counts_as_expense = 0`;
- `unknown = 0`;
- dinheiro entrou no player;
- player nao pode usar o comando pelo chat.

### Resultado runtime confirmado - mz_fuel

Comandos usados:

```txt
/mzecon_report
/mzecon_sources
/mzecon_unknown
```

Resultado observado:

- comandos do `mz_economy` registrados e funcionais;
- permissao `group.mz_owner` funcionando para os comandos administrativos;
- ledger gravando transacoes;
- `mz_fuel` enviando metadata correta;
- `mz_core` alterando saldo antes de registrar no `mz_economy`;
- top source: `mz_fuel`;
- top category: `vehicle_expense`;
- `tx = 16`;
- `in = 0`;
- `out = 80`;
- `unknown = 0`;
- `expense = 80`;
- `income = 0`;
- `counts_as_income = 0`;
- `counts_as_expense = 1`.

Conclusao do teste de fuel:

- `mz_fuel` aprovado em runtime para o MVP 3B.

### Resultado runtime nao aplicavel - mz_clothing

Status: NAO APLICAVEL NO RUNTIME ATUAL.

Motivo:

- `mz_clothing/shared/config.lua` esta com `Config.UseMoney = false`;
- o fluxo atual de roupa e gratuito;
- nenhuma transacao no ledger e esperada enquanto nao houver cobranca real.

Isso nao e bug do MVP 3B. A integracao de metadata em `RemoveMoney` permanece preparada para quando a cobranca for ativada no futuro.

Resultado esperado:

- enquanto `Config.UseMoney = false`, nao deve aparecer `source_resource = mz_clothing` no ledger por compra de roupa;
- quando a cobranca for ativada, o ledger deve registrar `category = cosmetic_expense`, `reason = clothing_purchase`, `counts_as_expense = 1` e `counts_as_income = 0`.

### Resultado runtime nao aplicavel - mz_tatto

Status: NAO APLICAVEL NO RUNTIME ATUAL.

Motivo:

- `mz_tatto/shared/config.lua` esta com `Config.UseMoney = false`;
- o fluxo atual de tattoo e gratuito;
- nenhuma transacao no ledger e esperada enquanto nao houver cobranca real.

Isso nao e bug do MVP 3B. A integracao de metadata em `RemoveMoney` permanece preparada para quando a cobranca for ativada no futuro.

Resultado esperado:

- enquanto `Config.UseMoney = false`, nao deve aparecer `source_resource = mz_tatto` no ledger por compra/salvamento de tattoo;
- quando a cobranca for ativada, o ledger deve registrar `category = cosmetic_expense`, `reason = tattoo_purchase`, `counts_as_expense = 1` e `counts_as_income = 0`.

### Resultado runtime pendente - saldo insuficiente com mz_fuel

Roteiro pendente:

1. Deixar o player sem saldo suficiente na conta usada pelo `mz_fuel`.
2. Tentar abastecer.
3. Conferir saldo antes/depois.
4. Rodar:

```txt
/mzecon_report
/mzecon_unknown
```

Resultado esperado:

- compra falha como antes;
- saldo nao muda;
- ledger nao registra transacao falsa;
- nao aparece `category = vehicle_expense` nova para tentativa falha;
- `/mzecon_unknown` continua sem unknown indevido;
- mensagem/comportamento para o player segue o padrao anterior.

### Resultado runtime pendente - mz_economy offline com mz_fuel

Roteiro pendente:

1. Parar o recurso:

```txt
stop mz_economy
```

2. Fazer um abastecimento pequeno no `mz_fuel`.
3. Confirmar:
   - cobranca continua funcionando;
   - saldo muda corretamente;
   - nao ha erro fatal;
   - nao ha cobranca duplicada;
   - ledger nao registra enquanto parado.
4. Reiniciar:

```txt
ensure mz_economy
```

5. Rodar:

```txt
/mzecon_report
/mzecon_sources
```

Resultado esperado:

- `mz_core`, `mz_fuel` e recursos de gameplay continuam funcionando sem `mz_economy`;
- ledger volta a registrar depois que `mz_economy` e reiniciado.

## Bugs encontrados/corrigidos

### Roteiro documental com direction incorreta

Foi encontrado um detalhe no documento do MVP 3B: o roteiro de conferencia citava `direction = debit`.

Correcao aplicada:

- `mz_core/docs/MZ_ECONOMY_MVP3B_GASTOS.md` agora usa `direction = out`.

Motivo:

- O wrapper `RemoveMoney` do `mz_core` registra ledger com `direction = out`.
- O `mz_economy` aceita `out`, nao `debit`.

Nao houve correcao funcional nos scripts dos recursos nesta validacao.

## Metadata esperada por recurso

### Fuel

```lua
{
  reason = 'fuel_purchase',
  category = 'vehicle_expense',
  source_resource = 'mz_fuel',
  source_type = 'resource_payment',
  counts_as_income = false,
  counts_as_expense = true,
  data = {
    payment_method = account,
    vehicle_plate = plate,
    liters = liters
  }
}
```

`vehicle_plate` e `liters` entram somente quando existem no contexto recebido por `MZFuelPayment.Charge`.

### Clothing

```lua
{
  reason = 'clothing_purchase',
  category = 'cosmetic_expense',
  source_resource = 'mz_clothing',
  source_type = 'resource_payment',
  counts_as_income = false,
  counts_as_expense = true,
  data = {
    action = 'save_current',
    shop_id = shopId,
    payment_method = account
  }
}
```

### Tattoo

```lua
{
  reason = 'tattoo_purchase',
  category = 'cosmetic_expense',
  source_resource = 'mz_tatto',
  source_type = 'resource_payment',
  counts_as_income = false,
  counts_as_expense = true,
  data = {
    shop_id = shopId,
    new_tattoo_count = newCount,
    total_tattoo_count = totalCount,
    payment_method = account
  }
}
```

## Roteiro runtime

### Configuracao

No `server.cfg`:

```cfg
ensure oxmysql
ensure mz_core
ensure mz_economy
ensure mz_fuel
ensure mz_clothing
ensure mz_tatto

add_ace group.mz_owner command allow
add_ace group.mz_owner command.quit deny
add_ace group.mz_owner group.mz_owner allow

add_principal identifier.fivem:SEU_ID_FIVEM_AQUI group.mz_owner
add_principal identifier.fivem:ID_DO_SOCIO_AQUI group.mz_owner
```

Antes dos testes:

1. Entrar com um player.
2. Confirmar que o player carregou no `mz_core`.
3. Confirmar saldo inicial em `wallet`, `bank` e `dirty`.
4. Dar saldo de teste por metodo controlado, se necessario.
5. Rodar:

```txt
/mzecon_report
/mzecon_sources
/mzecon_unknown
```

### Teste 1 - Fuel

1. Comprar combustivel normalmente.
2. Confirmar que o dinheiro foi removido uma unica vez.
3. Rodar novamente:

```txt
/mzecon_report
/mzecon_sources
/mzecon_unknown
```

Resultado esperado:

- Uma nova transacao.
- `direction = out`.
- `category = vehicle_expense`.
- `reason = fuel_purchase`.
- `source_resource = mz_fuel`.
- `counts_as_expense = 1`.
- `counts_as_income = 0`.
- `amount` igual ao valor cobrado.
- `balance_before` e `balance_after` coerentes.

### Teste 2 - Clothing

No runtime atual, `mz_clothing` esta gratuito (`Config.UseMoney = false`).

1. Salvar roupa no fluxo atual.
2. Confirmar que nao ha cobranca.
3. Conferir que nenhuma transacao nova de `mz_clothing` e esperada no ledger.

Resultado esperado:

- Nao aparece nova transacao de `source_resource = mz_clothing` enquanto o fluxo for gratuito.
- Isso nao e bug.
- A metadata ja esta preparada para quando `Config.UseMoney` for ativado no futuro.

### Teste 3 - Tattoo

No runtime atual, `mz_tatto` esta gratuito (`Config.UseMoney = false`).

1. Salvar/comprar uma ou mais tattoos no fluxo atual.
2. Confirmar que nao ha cobranca.
3. Conferir que nenhuma transacao nova de `mz_tatto` e esperada no ledger.

Resultado esperado:

- Nao aparece nova transacao de `source_resource = mz_tatto` enquanto o fluxo for gratuito.
- Isso nao e bug.
- A metadata ja esta preparada para quando `Config.UseMoney` for ativado no futuro.

### Teste 4 - mz_economy offline

1. Parar o ledger:

```txt
stop mz_economy
```

2. Fazer uma compra pequena, preferencialmente fuel.
3. Confirmar:
   - cobranca continua funcionando;
   - `mz_core` nao quebra;
   - recurso comprador nao quebra;
   - nao ha cobranca duplicada;
   - ledger apenas nao registra enquanto `mz_economy` esta parado.
4. Reiniciar:

```txt
ensure mz_economy
```

5. Rodar os reports novamente.

### Teste 5 - saldo insuficiente

1. Deixar o player sem saldo suficiente.
2. Tentar abastecer com `mz_fuel`.
3. Confirmar:
   - compra falha como antes;
   - saldo nao muda;
   - ledger nao registra transacao falsa;
   - mensagem/retorno para o player segue o comportamento anterior.

## SQL opcional

```sql
SELECT id, citizenid, account, amount, direction, category, reason, source_resource,
       counts_as_income, counts_as_expense, balance_before, balance_after, created_at
FROM mz_economy_transactions
ORDER BY id DESC
LIMIT 20;
```

## Pontos ainda dependentes de teste real

- Se `balance_before` e `balance_after` refletem o banco real apos `oxmysql`.
- Se `mz_economy` offline nao gera erro visual ou falha de compra.
- Se saldo insuficiente nao gera linha falsa no ledger.
- Se os comandos `/mzecon_report`, `/mzecon_sources` e `/mzecon_unknown` exibem os dados corretamente no chat/console.

## Confirmacoes de escopo

- Sem preco dinamico.
- Sem `mz_economy_prices`.
- Sem daily runs.
- Sem ganho por hora.
- Sem payroll/org/bridge QB.
- Sem `RecordTransaction` direto em `mz_fuel`, `mz_clothing` ou `mz_tatto`.
- Sem mudanca de valor cobrado.
- Sem mudanca de formula de cobranca.
- Sem mudanca de mensagens de cobranca.
- Sem novas tabelas.

## Proximo passo recomendado

Rodar os testes pendentes no servidor FiveM com `oxmysql`: saldo insuficiente usando `mz_fuel` e `mz_economy` offline usando `mz_fuel`.

Se esses dois testes passarem, o MVP 3B fica aprovado com observacao:

- clothing e tattoo nao foram validados como despesa porque atualmente sao gratuitos;
- a integracao de metadata desses recursos esta preparada para quando a cobranca for ativada.

Depois disso, o proximo passo recomendado e iniciar o MVP 3A de org/payroll.
