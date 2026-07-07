# MZ_ECONOMY MVP 4A - Daily stats e relatorios passivos

## Objetivo

Adicionar ao `mz_economy` uma camada passiva de estatisticas diarias para responder:

- quanto tempo cada jogador ficou online no dia;
- quanto entrou como income;
- quanto saiu como expense;
- qual foi o income/expense por hora;
- quais categorias geraram renda, despesa e unknown.

O `mz_core` continua sendo a fonte de identidade e sessoes. Este MVP nao altera tabelas nem regras do `mz_core`.

## Arquivos principais alterados

- `mz_economy/shared/config.lua`
- `mz_economy/server/prepare.lua`
- `mz_economy/server/repository.lua`
- `mz_economy/server/service.lua`
- `mz_economy/server/commands.lua`
- `mz_economy/server/main.lua`
- `mz_economy/docs/MVP4A_DAILY_STATS.md`

## Tabela criada

- `mz_economy_daily_player_stats`

A tabela e derivada de:

- `mz_economy_transactions`
- `mz_player_sessions`

Nao altera:

- `mz_player_accounts`
- `mz_org_accounts`
- `mz_player_sessions`
- `mz_economy_transactions`

## Comandos criados

- `/mzecon_rebuild_day [YYYY-MM-DD]`
- `/mzecon_daily [YYYY-MM-DD]`
- `/mzecon_player [source|citizenid] [YYYY-MM-DD]`
- `/mzecon_top [YYYY-MM-DD] [income|expense|unknown]`

O rebuild usa uma transacao para apagar e recriar as linhas do dia, mantendo a operacao idempotente sem deixar a data vazia se o insert falhar.

Comandos antigos foram mantidos:

- `/mzecon_report`
- `/mzecon_sources`
- `/mzecon_unknown`
- `/mzecon_test`

## Playtime

O calculo usa `mz_player_sessions`:

- `joined_at` como inicio;
- `dropped_at`, `last_seen_at` ou `NOW()` para sessoes abertas, conforme config;
- intersecao com a janela do dia;
- sessoes cruzando meia-noite sao cortadas no dia certo;
- duracao negativa e ignorada;
- menos de 1 minuto vira 0.

Config:

```lua
Config.Economy.Stats = {
  MinMinutesOnlineToCount = 60,
  MaxTopRows = 10,
  IncludeOpenSessions = true
}
```

## Income e expense

`income_total` soma somente transacoes com:

- `counts_as_income = 1`

`expense_total` soma somente transacoes com:

- `counts_as_expense = 1`

Nao contam como income:

- `admin_adjustment`
- `admin_org_adjustment`
- `system_bootstrap`
- `org_transfer`
- `player_transfer`
- `unknown`

`salary` conta como income individual quando o ledger registra essa flag.

## Garantias de escopo

- Nenhum saldo e alterado.
- Nenhuma rotina automatica foi criada.
- Nenhum preco dinamico foi criado.
- Nenhuma tabela `mz_economy_prices` foi criada.
- Nenhuma tabela `mz_economy_runs` foi criada.
- Nenhum job legal/ilegal foi criado.
- Nenhum fluxo de phone/email foi criado.
- Nenhuma regra de payroll/org/fuel/clothing/tattoos foi alterada.
- Nenhuma bridge QB foi alterada.

## Validacao local

Validado estaticamente com:

```txt
luac -p mz_economy/shared/config.lua mz_economy/server/prepare.lua mz_economy/server/repository.lua mz_economy/server/service.lua mz_economy/server/commands.lua mz_economy/server/main.lua
```

Validacao runtime permanece pendente ate executar em servidor FiveM/DB real.

Roteiro e status em `mz_economy/docs/VALIDACAO_MVP4A_DAILY_STATS_RUNTIME.md`.

## Como testar em runtime

1. Iniciar `oxmysql`, `mz_core` e `mz_economy`.
2. Gerar transacoes reais.
3. Rodar:

```txt
/mzecon_rebuild_day
/mzecon_daily
/mzecon_player 1
/mzecon_top
```

4. Rodar rebuild duas vezes e confirmar que nao duplica linhas.
5. Conferir que `admin_adjustment` e `org_transfer` nao inflam income.

## Proximo passo

Se o runtime aprovar, seguir para MVP 4B: relatorios melhores e investigacao de fontes `unknown`.

Depois, MVP 5: preview de preco, ainda sem aplicar automaticamente.
