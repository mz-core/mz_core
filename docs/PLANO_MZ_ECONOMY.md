# Plano para mz_economy

Data da auditoria: 2026-06-23

Objetivo: desenhar um plano seguro para criar economia dinamica, relatorios e ajuste de precos usando o `mz_core` como base de identidade/contas, sem quebrar scripts existentes.

## Decisao recomendada

Criar um recurso separado: `mz_economy`.

O `mz_core` deve continuar sendo dono de:

- identidade
- jogadores carregados
- contas `wallet`, `bank`, `dirty`
- organizacoes
- sessoes
- bridge de compatibilidade

O `mz_economy` deve ser dono de:

- ledger economico
- classificacao de transacoes
- relatorios diarios
- ganho/hora
- preview e aplicacao de precos dinamicos
- integracao futura com telefone/email/notificacoes

## Por que separar do core

| Motivo | Beneficio |
| --- | --- |
| Menor risco | Evita mexer diretamente em fluxo critico de login, conta e org |
| Evolucao rapida | Relatorios e regras podem mudar sem refatorar o core |
| Compatibilidade | Exports antigos continuam funcionando |
| Observabilidade | `mz_economy` pode nascer passivo, so registrando |
| Futuro | Facil integrar jobs, telefone, email, lojas e staff tools |

## Contrato minimo entre mz_core e mz_economy

### Exports do core que ja existem

| Export | Uso |
| --- | --- |
| `GetPlayer` | Ler jogador carregado |
| `ResolvePlayerIdentity` | Resolver `source`, `citizenid`, `license`, nome e telefone |
| `GetPlayerSession` | Obter sessao atual |
| `GetMoney` | Ler saldos |
| `SetMoney` | Ajuste absoluto |
| `AddMoney` | Credito |
| `RemoveMoney` | Debito |
| `GetOrgAccount` | Conta compartilhada |
| `DepositOrgAccount` | Transferencia player -> org |
| `WithdrawOrgAccount` | Transferencia org -> player |

### Exports/wrappers recomendados para fase de implementacao

Sem alterar scripts antigos, adicionar suporte opcional a metadata:

```lua
exports['mz_core']:AddMoney(source, account, amount, metadata)
exports['mz_core']:RemoveMoney(source, account, amount, metadata)
exports['mz_core']:SetMoney(source, account, amount, metadata)
exports['mz_core']:TransferMoney(from, to, account, amount, metadata)
exports['mz_core']:NormalizeMoneyAccount(account)
```

Campos esperados em `metadata`:

```lua
{
    reason = 'fuel_purchase',
    category = 'vehicle_expense',
    source_resource = 'mz_fuel',
    counts_as_income = false,
    counts_as_expense = true,
    related_citizenid = nil,
    related_org_code = nil,
    external_ref = nil,
    data = {}
}
```

Compatibilidade:

- Chamadas antigas continuam validas.
- Sem metadata, registrar como `category = 'unknown'`.
- Sem metadata, `counts_as_income = false` e `counts_as_expense = false`.
- `source_resource` pode usar `GetInvokingResource()` quando disponivel.

## Tabelas recomendadas

### `mz_economy_transactions`

Ledger principal. Uma linha por mudanca economica relevante.

| Campo | Tipo sugerido | Motivo |
| --- | --- | --- |
| `id` | bigint auto increment | Identificador |
| `transaction_id` | varchar unique | ID externo/uuid opcional |
| `citizenid` | varchar | Jogador principal |
| `license` | varchar nullable | Auditoria |
| `account` | varchar | `wallet`, `bank`, `dirty`, `org` |
| `amount` | bigint/int | Valor absoluto da mudanca |
| `balance_before` | bigint/int nullable | Saldo antes |
| `balance_after` | bigint/int nullable | Saldo depois |
| `direction` | varchar | `in`, `out`, `transfer`, `adjustment` |
| `category` | varchar | Classificacao economica |
| `reason` | varchar | Motivo tecnico/humano |
| `source_resource` | varchar | Recurso chamador |
| `source_type` | varchar | `core`, `qb_bridge`, `org_account`, `payroll`, etc |
| `counts_as_income` | tinyint/bool | Entra em ganho/hora |
| `counts_as_expense` | tinyint/bool | Entra em gasto/hora |
| `related_citizenid` | varchar nullable | Contraparte jogador |
| `related_org_code` | varchar nullable | Contraparte org |
| `external_ref` | varchar nullable | Pedido, invoice, item, job run |
| `metadata_json` | longtext/json | Dados extras |
| `created_at` | timestamp | Data de registro |

Indices:

- `(citizenid, created_at)`
- `(category, created_at)`
- `(source_resource, created_at)`
- `(counts_as_income, created_at)`
- `(counts_as_expense, created_at)`
- `(related_org_code, created_at)`

### `mz_economy_daily_player_stats`

Snapshot agregado por jogador/dia.

| Campo | Motivo |
| --- | --- |
| `stat_date` | Dia de referencia |
| `citizenid` | Jogador |
| `playtime_minutes` | Tempo ativo no dia |
| `income_total` | Renda considerada |
| `expense_total` | Despesa considerada |
| `income_per_hour` | Renda / horas |
| `expense_per_hour` | Despesa / horas |
| `legal_income` | Soma legal |
| `illegal_income` | Soma ilegal |
| `salary_income` | Soma salario |
| `unknown_total` | Dinheiro sem categoria |
| `created_at` / `updated_at` | Auditoria |

### `mz_economy_prices`

Precos dinamicos por item, servico ou recurso.

| Campo | Motivo |
| --- | --- |
| `price_key` | Ex: `fuel.liter`, `clothing.outfit`, `tattoo.service` |
| `resource_name` | Recurso dono |
| `item_type` | `service`, `item`, `fee`, `job_reward` |
| `base_price` | Preco base |
| `current_price` | Preco ativo |
| `min_price` / `max_price` | Travas |
| `last_factor` | Ultimo multiplicador aplicado |
| `last_reason` | Motivo do ajuste |
| `updated_at` | Auditoria |

### `mz_economy_runs`

Controle de execucao.

| Campo | Motivo |
| --- | --- |
| `run_date` | Dia |
| `run_type` | `daily_report`, `price_preview`, `price_apply`, `rebuild_stats` |
| `status` | `running`, `done`, `failed` |
| `started_at` / `finished_at` | Auditoria |
| `metadata_json` | Parametros/resultado |

Indice unico recomendado: `(run_date, run_type)`.

### `mz_economy_reports`

Opcional, para guardar relatorios prontos.

| Campo | Motivo |
| --- | --- |
| `report_date` | Dia |
| `report_type` | Tipo |
| `summary_json` | Numeros principais |
| `created_at` | Auditoria |

## Uso de `mz_player_sessions` para playtime

O core ja possui `mz_player_sessions`. Ele deve ser a fonte primaria de sessoes, mas nao deve ser a unica camada de relatorio.

Recomendacao:

1. Usar `mz_player_sessions` para saber entrada, ultima atividade e saida.
2. Criar agregacao diaria em `mz_economy_daily_player_stats`.
3. Dividir sessoes que atravessam meia-noite.
4. Ignorar ou limitar sessoes sem heartbeat recente.
5. Recalcular stats por comando staff quando necessario.

Nao e obrigatorio criar `mz_playtime_sessions` separado se `mz_player_sessions` for confiavel. Porem, se o servidor quiser separar dados economicos de dados do core, criar `mz_economy_playtime_daily` e manter `mz_player_sessions` como origem.

## Classificacao padrao

| Categoria | Conta como renda | Conta como despesa | Exemplos |
| --- | --- | --- | --- |
| `legal_job` | Sim | Nao | entregas, coletas, vendas legais |
| `illegal_job` | Sim | Nao | drogas, roubos, heists |
| `salary` | Sim | Nao | payroll |
| `business_revenue` | Sim | Nao | receita de empresa |
| `shop_expense` | Nao | Sim | compras |
| `vehicle_expense` | Nao | Sim | combustivel, reparo |
| `cosmetic_expense` | Nao | Sim | roupas, tatuagens |
| `org_transfer` | Nao | Nao | deposito/saque org |
| `player_transfer` | Nao | Nao | pix/transferencia |
| `admin_adjustment` | Nao | Nao | set/add manual |
| `system_bootstrap` | Nao | Nao | starter money |
| `refund` | Nao por padrao | Nao por padrao | devolucao |
| `unknown` | Nao | Nao | compatibilidade antiga |

## Comandos staff sugeridos

| Comando | Objetivo |
| --- | --- |
| `/mzecon_report [dia]` | Mostra resumo diario da economia |
| `/mzecon_player [id/citizenid] [dia]` | Mostra renda, gastos e categorias do jogador |
| `/mzecon_sources [dia]` | Lista recursos que criaram/removeram dinheiro |
| `/mzecon_unknown [dia]` | Lista transacoes sem categoria |
| `/mzecon_price_preview [dia]` | Simula ajuste de precos sem aplicar |
| `/mzecon_apply_prices [dia]` | Aplica precos aprovados |
| `/mzecon_rebuild_day [dia]` | Recalcula stats do dia |
| `/mzecon_mark_transaction [id] [categoria]` | Corrige classificacao pontual |

Todos devem exigir ACE especifica, por exemplo `mzcore.economy.manage` ou permissao equivalente no sistema de staff.

## Relatorio diario minimo

O relatorio diario deve responder:

- Total de dinheiro criado.
- Total de dinheiro removido.
- Total transferido.
- Renda legal total.
- Renda ilegal total.
- Salarios pagos.
- Despesas por categoria.
- Top fontes de renda.
- Top fontes de despesa.
- Ganho medio por hora.
- Jogadores acima do limite esperado de ganho/hora.
- Transacoes `unknown`.
- Recursos que usaram API antiga.
- Precos sugeridos para ajuste.

## Precos dinamicos

Nao aplicar precos dinamicos automaticamente no inicio.

Ordem recomendada:

1. Coletar dados por pelo menos alguns dias.
2. Gerar preview.
3. Staff revisa.
4. Aplicar manualmente.
5. Registrar em `mz_economy_runs`.
6. So depois considerar automacao parcial.

Regra simples inicial:

- Se renda/hora media estiver acima do alvo, aumentar despesas controladas.
- Se renda/hora media estiver abaixo do alvo, reduzir despesas ou aumentar recompensas.
- Sempre respeitar `min_price` e `max_price`.
- Nunca usar transacoes `unknown` para ajuste automatico.

## Integracao com recursos atuais

### `mz_fuel`

Adaptar pagamento para enviar metadata:

- `category = 'vehicle_expense'`
- `reason = 'fuel_purchase'`
- `source_resource = 'mz_fuel'`
- `counts_as_expense = true`

### `mz_clothing`

Adaptar cobranca:

- `category = 'cosmetic_expense'`
- `reason = 'clothing_purchase'`
- `source_resource = 'mz_clothing'`
- `counts_as_expense = true`

### `mz_tatto`

Adaptar cobranca:

- `category = 'cosmetic_expense'`
- `reason = 'tattoo_purchase'`
- `source_resource = 'mz_tatto'`
- `counts_as_expense = true`

### Payroll

Registrar duas perspectivas:

- player recebe `salary`, `counts_as_income = true`
- org perde `salary_expense`, `counts_as_expense = true`

Nao contar como dinheiro criado se a org foi debitada.

### Org bank

Registrar:

- deposito: `org_transfer`
- saque: `org_transfer`
- admin add/remove: `admin_org_adjustment`

Nao contar como renda.

### QBCore bridge

Manter compatibilidade, mas registrar:

- `source_type = 'qb_bridge'`
- `source_resource = GetInvokingResource() or 'unknown'`
- `category = metadata.category or 'unknown'`

## Integracao com telefone/email

Estado atual:

- `mz_phone` tem notificacoes, conversas e mensagens.
- Nao ha app de email no telefone atual.
- O telefone ja resolve identidade pelo `mz_core`.

Plano:

1. No MVP, enviar somente notificacoes in-game/staff command.
2. Depois, criar export generico no telefone, por exemplo `SendNotificationToCitizen`.
3. Quando existir email, criar `SendEconomyMail(citizenid, subject, body, metadata)`.
4. Relatorios administrativos podem ser enviados por comando e, futuramente, por app interno.

## Fases de implantacao

### Fase 1: observabilidade

- Criar `mz_economy`.
- Criar tabela `mz_economy_transactions`.
- Criar funcao `RecordTransaction`.
- Nao alterar saldo diretamente.
- Registrar transacoes chamadas pelo core.

### Fase 2: wrappers no core

- Adicionar metadata opcional aos exports de dinheiro.
- Manter assinatura antiga.
- Normalizar contas.
- Registrar ledger sempre que saldo muda.

### Fase 3: adaptar recursos atuais

- Fuel.
- Clothing.
- Tatto.
- Org bank.
- Payroll.
- QB bridge.

### Fase 4: relatorios

- Agregar playtime diario.
- Gerar ganho/hora.
- Expor comandos staff.
- Identificar fontes `unknown`.

### Fase 5: precos dinamicos em preview

- Criar `mz_economy_prices`.
- Gerar sugestoes sem aplicar.
- Criar comando de preview.

### Fase 6: aplicacao controlada

- Aplicar precos manualmente.
- Registrar `mz_economy_runs`.
- Adicionar limites minimo/maximo.

### Fase 7: automacao parcial

- Rodar diario.
- Evitar duplicidade por `mz_economy_runs`.
- Notificar staff.
- Permitir rollback manual.

## Criterios de sucesso

O sistema esta pronto para precos dinamicos quando:

- Mais de 95% das transacoes possuem categoria diferente de `unknown`.
- Todas as fontes de dinheiro passam pelo ledger.
- Transferencias nao inflam renda.
- Salario e distinguido de dinheiro criado.
- Playtime diario e confiavel.
- Staff consegue revisar preview antes de aplicar.
- Existe trava contra execucao duplicada.
- Recursos legados fora do core foram desligados ou adaptados.

## Primeiro MVP recomendado

Escopo pequeno:

1. Criar ledger.
2. Registrar Add/Remove/SetMoney.
3. Registrar org deposit/withdraw/payroll.
4. Adaptar fuel, clothing e tattoo com metadata.
5. Criar `/mzecon_report`.
6. Criar `/mzecon_unknown`.
7. Nao alterar precos ainda.

Esse MVP ja responde a pergunta mais importante: de onde o dinheiro esta vindo e para onde esta indo.
