# Checklist de implantacao da economia

Data da auditoria: 2026-06-23

Objetivo: checklist pratico para implantar `mz_economy` com seguranca, sem quebrar o `mz_core` e sem ativar precos dinamicos antes de haver dados confiaveis.

## Fase 0: preparacao

- [ ] Confirmar quais recursos estao realmente ativos no `server.cfg`.
- [ ] Confirmar se `celular/resource/smartphone` legado esta ativo.
- [ ] Se o legado estiver ativo, decidir entre desligar, isolar ou adaptar ao ledger.
- [ ] Confirmar que `mz_core` inicia antes de recursos que usam dinheiro.
- [ ] Confirmar que `mz_phone` atual, e nao o telefone legado, e o telefone oficial.
- [ ] Confirmar que owners/socios estao no grupo `group.mz_owner`.
- [ ] Definir contas oficiais: `wallet`, `bank`, `dirty`.
- [ ] Definir aliases aceitos: `cash`, `money`, `black_money`, se necessario.
- [ ] Definir categorias oficiais de transacao.

## Fase 1: criar observabilidade

- [ ] Criar recurso `mz_economy`.
- [ ] Adicionar dependency de `oxmysql` e, se necessario, `ox_lib`.
- [ ] Criar tabela `mz_economy_transactions`.
- [ ] Criar indices por `citizenid`, `created_at`, `category` e `source_resource`.
- [ ] Criar funcao interna `RecordTransaction`.
- [ ] Criar validacao de `direction`: `in`, `out`, `transfer`, `adjustment`.
- [ ] Criar validacao de `account`: `wallet`, `bank`, `dirty`, `org`.
- [ ] Criar validacao de `amount > 0`.
- [ ] Registrar `source_resource`.
- [ ] Registrar `reason`.
- [ ] Registrar `category`.
- [ ] Registrar `counts_as_income`.
- [ ] Registrar `counts_as_expense`.
- [ ] Registrar `metadata_json`.
- [ ] Nao alterar saldo dentro do `mz_economy` nesta fase.

## Fase 2: integrar wrappers do core

- [ ] Adicionar metadata opcional em `AddMoney`.
- [ ] Adicionar metadata opcional em `RemoveMoney`.
- [ ] Adicionar metadata opcional em `SetMoney`.
- [ ] Manter compatibilidade com chamadas antigas.
- [ ] Criar helper `NormalizeMoneyAccount`.
- [ ] Default para chamada antiga: `category = 'unknown'`.
- [ ] Default para chamada antiga: `counts_as_income = false`.
- [ ] Default para chamada antiga: `counts_as_expense = false`.
- [ ] Registrar balance before/balance after quando disponivel.
- [ ] Registrar falhas de transacao quando saldo insuficiente for relevante.
- [ ] Garantir que erro no ledger nao duplique dinheiro.
- [ ] Garantir que erro no ledger gere log visivel para staff/dev.

## Fase 3: adaptar fluxos existentes

### Core accounts

- [ ] `MZAccountService.addMoney` registra ledger.
- [ ] `MZAccountService.removeMoney` registra ledger.
- [ ] `MZAccountService.setMoney` registra ledger como `adjustment`.
- [ ] `MZAccountRepository.updatePlayerMoney` continua limitado a contas permitidas.

### Payroll

- [x] Payroll deixa de creditar banco direto ou registra ledger explicitamente.
- [x] Credito do jogador usa categoria `salary`.
- [x] Debito da org usa categoria `salary_expense`.
- [x] Salario conta como renda do jogador.
- [x] Salario nao conta como dinheiro criado se org foi debitada.
- [x] Payroll registra org de origem.
- [x] Payroll registra grade/cargo quando disponivel.

### Org bank

- [x] Deposito player -> org registra `org_transfer`.
- [x] Saque org -> player registra `org_transfer`.
- [x] `AddOrgAccountBalance` registra `admin_org_adjustment`.
- [x] `RemoveOrgAccountBalance` registra `admin_org_adjustment`.
- [x] Comandos `mzorg_deposit` e `mzorg_withdraw` nao contam como renda.

### QBCore bridge

- [ ] `Player.Functions.AddMoney` envia `source_type = 'qb_bridge'`.
- [ ] `Player.Functions.RemoveMoney` envia `source_type = 'qb_bridge'`.
- [ ] `Player.Functions.SetMoney` envia `source_type = 'qb_bridge'`.
- [ ] Capturar `GetInvokingResource()` quando possivel.
- [ ] Chamadas sem categoria continuam como `unknown`.

### Recursos de gasto

- [ ] `mz_fuel` envia `category = 'vehicle_expense'`.
- [ ] `mz_fuel` envia `reason = 'fuel_purchase'`.
- [ ] `mz_clothing` envia `category = 'cosmetic_expense'`.
- [ ] `mz_clothing` envia `reason = 'clothing_purchase'`.
- [ ] `mz_tatto` envia `category = 'cosmetic_expense'`.
- [ ] `mz_tatto` envia `reason = 'tattoo_purchase'`.
- [ ] Todos esses gastos marcam `counts_as_expense = true`.

## Fase 4: playtime e ganho por hora

- [x] Usar `mz_player_sessions` como fonte primaria.
- [x] Criar agregacao diaria por jogador.
- [x] Dividir sessoes que passam da meia-noite.
- [x] Ignorar sessoes muito curtas se necessario.
- [x] Definir criterio de atividade real.
- [x] Criar `income_per_hour`.
- [x] Criar `expense_per_hour`.
- [x] Separar renda legal, ilegal, salario e unknown.
- [x] Criar comando para recalcular dia.
- [ ] Validar resultados com alguns jogadores reais.

## Fase 5: relatorios staff

- [x] Criar `/mzecon_report [dia]`.
- [x] Criar `/mzecon_player [id/citizenid] [dia]`.
- [x] Criar `/mzecon_sources [dia]`.
- [x] Criar `/mzecon_unknown [dia]`.
- [x] Criar `/mzecon_rebuild_day [dia]`.
- [x] Criar `/mzecon_daily [dia]`.
- [x] Criar `/mzecon_top [dia] [tipo]`.
- [x] Criar `/mzecon_health [dia]`.
- [x] Criar `/mzecon_unknown_sources [dia] [limit]`.
- [x] Criar `/mzecon_category_report [dia] [limit]`.
- [x] Criar `/mzecon_suspicious [dia] [limit]`.
- [x] Criar `/mzecon_player_tx [id/citizenid] [dia] [limit]`.
- [x] Criar `/mzecon_source_tx [source_resource] [dia] [limit]`.
- [x] Proteger comandos por ACE/permissao.
- [x] Mostrar total criado.
- [x] Mostrar total removido.
- [x] Mostrar total transferido.
- [x] Mostrar top fontes de renda.
- [x] Mostrar top gastos.
- [x] Mostrar ganho/hora medio.
- [x] Mostrar transacoes sem categoria.

## Fase 6: preparar precos dinamicos

- [ ] Criar `mz_economy_prices`.
- [ ] Cadastrar precos controlados inicialmente.
- [ ] Definir `base_price`.
- [ ] Definir `min_price`.
- [ ] Definir `max_price`.
- [ ] Definir regra de ajuste por ganho/hora.
- [ ] Ignorar transacoes `unknown` no calculo automatico.
- [ ] Criar `/mzecon_price_preview [dia]`.
- [ ] Preview nao altera preco real.
- [ ] Staff revisa preview antes de aplicar.

## Fase 7: aplicar precos com controle

- [ ] Criar `mz_economy_runs`.
- [ ] Criar trava unica por `run_date` e `run_type`.
- [ ] Criar `/mzecon_apply_prices [dia]`.
- [ ] Registrar todos os precos alterados.
- [ ] Registrar fator aplicado.
- [ ] Registrar motivo do ajuste.
- [ ] Permitir rollback manual.
- [ ] Notificar staff apos aplicacao.
- [ ] Nunca aplicar duas vezes o mesmo dia sem override explicito.

## Fase 8: notificacoes e telefone

- [ ] Usar notificacao simples no MVP.
- [ ] Integrar com `mz_phone_notifications` se fizer sentido.
- [ ] Nao depender de email enquanto o `mz_phone` nao tiver mailbox.
- [ ] Criar evento/export futuro para enviar relatorio ao telefone.
- [ ] Criar email/app economico apenas depois do ledger estar estavel.

## Fase 9: jobs legais futuros

- [ ] Todo job legal deve chamar `AddMoney` com metadata.
- [ ] Categoria padrao: `legal_job`.
- [ ] Informar nome do job.
- [ ] Informar etapa/rota/missao.
- [ ] Informar quantidade vendida, quando houver.
- [ ] Informar item vendido, quando houver.
- [ ] Marcar `counts_as_income = true`.
- [ ] Bloquear recompensa sem categoria.

## Fase 10: ilegais futuros

- [ ] Todo ilegal deve decidir entre `wallet`, `bank` e `dirty`.
- [ ] Categoria padrao: `illegal_job`.
- [ ] Marcar `counts_as_income = true`.
- [ ] Registrar risco, local ou tipo de atividade quando fizer sentido.
- [ ] Lavagem deve ser transferencia/conversao, nao renda nova.
- [ ] Roubo de jogador deve ser transferencia, nao criacao.
- [ ] Venda a NPC pode ser renda se o dinheiro nascer do sistema.
- [ ] Heist deve registrar fonte, participantes e divisao.

## Validacoes antes de liberar em producao

- [ ] Criar jogador novo e confirmar starter money como `system_bootstrap`.
- [ ] Comprar combustivel e confirmar `vehicle_expense`.
- [ ] Comprar roupa e confirmar `cosmetic_expense`.
- [ ] Comprar tatuagem e confirmar `cosmetic_expense`.
- [ ] Depositar dinheiro em org e confirmar `org_transfer`.
- [ ] Sacar dinheiro de org e confirmar `org_transfer`.
- [ ] Rodar payroll e confirmar `salary`.
- [ ] Usar comando admin de saldo de org e confirmar `admin_org_adjustment`.
- [ ] Usar chamada antiga sem metadata e confirmar `unknown`.
- [ ] Gerar relatorio diario.
- [ ] Verificar ganho/hora de um jogador conhecido.
- [ ] Rodar `/mzecon_health` e confirmar status/percentual unknown.
- [ ] Rodar `/mzecon_unknown_sources` e confirmar fontes unknown.
- [ ] Rodar `/mzecon_category_report` e confirmar categorias por direction.
- [ ] Rodar `/mzecon_suspicious` e revisar anomalias simples.
- [ ] Rodar `/mzecon_player_tx` para jogador conhecido.
- [ ] Rodar `/mzecon_source_tx` para recurso conhecido.
- [ ] Verificar que transferencias nao inflam renda.
- [ ] Verificar que starter money nao conta como renda.
- [ ] Verificar que relatorio funciona apos restart.
- [ ] Verificar que run diaria nao duplica.

## Sinais de alerta

- [ ] Existem transacoes `unknown` acima de 5% do total.
- [ ] Algum recurso altera banco direto sem passar pelo core.
- [ ] Algum recurso legado de banco/cassino esta ativo fora do ledger.
- [ ] Payroll paga sem registrar contraparte da org.
- [ ] `SetMoney` e usado por scripts de gameplay.
- [ ] Preco dinamico considera transferencias como renda.
- [ ] Player com playtime baixo aparece com renda/hora absurda.
- [ ] Comando staff consegue aplicar preco sem permissao.
- [ ] Restart do recurso roda ajuste diario duas vezes.

## Ordem recomendada de trabalho

1. Ledger.
2. Wrappers metadata-aware.
3. Adaptar gastos atuais.
4. Adaptar org/payroll.
5. Relatorios.
6. Playtime diario.
7. Preview de preco.
8. Aplicacao manual.
9. Automacao parcial.
10. Integracao telefone/email.

## Criterio para considerar a implantacao pronta

- [ ] Toda mudanca de saldo relevante esta no ledger.
- [ ] As categorias principais estao padronizadas.
- [ ] Chamadas antigas ainda funcionam.
- [ ] Staff consegue ver fontes `unknown`.
- [ ] Transferencias nao contam como renda.
- [ ] Salario e separado de dinheiro criado.
- [ ] Playtime diario e calculado.
- [ ] Ganho/hora e gerado.
- [ ] Precos dinamicos comecam em preview.
- [ ] Existe controle anti-duplicidade por dia.
