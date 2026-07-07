# MZ_ECONOMY MVP 3B - Gastos atuais

## Objetivo

Adaptar gastos ja existentes para alimentar o ledger passivo do `mz_economy` por meio dos wrappers metadata-aware do `mz_core`.

Este MVP nao altera precos, regras de cobranca, mensagens, schema, payroll, bancos de organizacao, bridge QB, phone, realestate, jobs ou fluxos ilegais.

## Arquivos alterados

- `mz_fuel/server/payment.lua`
- `mz_clothing/server/main.lua`
- `mz_tatto/server/service.lua`

## Fluxos adaptados

### `mz_fuel`

O pagamento de abastecimento continua usando `MZFuelPayment.Charge`.

A chamada existente a `exports['mz_core']:RemoveMoney` passou a enviar metadata:

- `reason = fuel_purchase`
- `category = vehicle_expense`
- `source_resource = mz_fuel`
- `source_type = resource_payment`
- `counts_as_income = false`
- `counts_as_expense = true`
- `data.payment_method`
- `data.vehicle_plate`, quando recebido no contexto
- `data.liters`, quando recebido no contexto

Nao houve alteracao no calculo de litros, preco por litro ou valor cobrado.

### `mz_clothing`

O pagamento para salvar a roupa atual continua dependente de `Config.UseMoney`, `Config.ClothingPrice` e `Config.MoneyType`.

No runtime atual, `mz_clothing/shared/config.lua` usa `Config.UseMoney = false`. Portanto o fluxo atual de roupa e gratuito e nenhuma transacao no ledger e esperada enquanto essa configuracao permanecer assim.

A chamada existente a `exports['mz_core']:RemoveMoney` passou a enviar metadata:

- `reason = clothing_purchase`
- `category = cosmetic_expense`
- `source_resource = mz_clothing`
- `source_type = resource_payment`
- `counts_as_income = false`
- `counts_as_expense = true`
- `data.action = save_current`
- `data.shop_id`
- `data.payment_method`

O `shopId` ja validado pelo fluxo de save foi repassado somente para observabilidade.

A integracao fica preparada para quando a cobranca for ativada no futuro; este MVP nao cria cobranca nova.

### `mz_tatto`

O pagamento de tattoos continua somando apenas tattoos novas em relacao ao estado salvo atual.

No runtime atual, `mz_tatto/shared/config.lua` usa `Config.UseMoney = false`. Portanto o fluxo atual de tattoo e gratuito e nenhuma transacao no ledger e esperada enquanto essa configuracao permanecer assim.

A chamada existente a `exports['mz_core']:RemoveMoney` passou a enviar metadata:

- `reason = tattoo_purchase`
- `category = cosmetic_expense`
- `source_resource = mz_tatto`
- `source_type = resource_payment`
- `counts_as_income = false`
- `counts_as_expense = true`
- `data.shop_id`
- `data.new_tattoo_count`
- `data.total_tattoo_count`
- `data.payment_method`

A contagem de tattoos novas foi calculada no mesmo loop que ja calcula o total, apenas para metadata.

A integracao fica preparada para quando a cobranca for ativada no futuro; este MVP nao cria cobranca nova.

## Garantias de escopo

- Nenhuma chamada direta a `exports['mz_economy']:RecordTransaction` foi adicionada aos recursos adaptados.
- Nenhuma tabela nova foi criada.
- Nenhum preco dinamico foi introduzido.
- Nenhuma cobranca nova foi criada em roupa ou tattoo.
- Nenhum fluxo de income, ganho por hora, daily report ou run foi implementado.
- Nenhum recurso fora de `mz_fuel`, `mz_clothing` e `mz_tatto` foi alterado por este MVP.

## Validacao sugerida

1. Comprar combustivel e confirmar que o saldo diminui como antes.
2. Se `mz_clothing` estiver com `Config.UseMoney = false`, confirmar que o fluxo gratuito nao gera ledger.
3. Se `mz_tatto` estiver com `Config.UseMoney = false`, confirmar que o fluxo gratuito nao gera ledger.
4. Conferir `mz_economy_transactions` para registros com:
   - `source_resource` em `mz_fuel`, `mz_clothing` ou `mz_tatto`
   - `direction = out`
   - `counts_as_expense = 1`
   - `counts_as_income = 0`

## Proximo passo

O proximo MVP pode adaptar outros gastos ja existentes, desde que continue usando apenas metadata nos wrappers do `mz_core` e mantenha o `mz_economy` passivo.
