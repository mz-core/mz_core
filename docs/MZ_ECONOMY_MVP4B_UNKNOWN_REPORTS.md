# MZ_ECONOMY MVP 4B - Unknown reports e diagnosticos passivos

Data: 2026-06-23

Este documento espelha, no `mz_core`, o fechamento do MVP 4B implementado em `mz_economy`.

Referencia principal:

- `mz_economy/docs/MVP4B_UNKNOWN_REPORTS.md`

## O que foi adicionado

Novos comandos staff/console:

- `/mzecon_health [YYYY-MM-DD]`
- `/mzecon_unknown_sources [YYYY-MM-DD] [limit]`
- `/mzecon_category_report [YYYY-MM-DD] [limit]`
- `/mzecon_suspicious [YYYY-MM-DD] [limit]`
- `/mzecon_player_tx [source|citizenid] [YYYY-MM-DD] [limit]`
- `/mzecon_source_tx [source_resource] [YYYY-MM-DD] [limit]`

Novos exports passivos em `mz_economy`:

- `GetHealthReport`
- `GetUnknownSources`
- `GetCategoryReport`
- `GetSuspiciousReport`
- `GetPlayerTransactions`
- `GetSourceTransactions`

## Garantias de escopo

O MVP 4B nao altera nenhuma regra de saldo no `mz_core`.

Nao foram alterados:

- `mz_player_accounts`;
- `AddMoney`;
- `RemoveMoney`;
- `SetMoney`;
- org bank;
- payroll;
- QB bridge;
- fuel, clothing ou tattoos;
- phone/email.

Tambem nao foram criadas tabelas de preco ou runs:

- `mz_economy_prices`;
- `mz_economy_runs`.

## Permissao

Os comandos seguem o padrao do projeto:

```cfg
add_ace group.mz_owner command allow
add_ace group.mz_owner command.quit deny
add_ace group.mz_owner group.mz_owner allow
```

`Config.Economy.StaffAce` permanece:

```lua
'group.mz_owner'
```

Console (`source = 0`) continua liberado.

## Runtime pendente

A autorizacao explicita permitiu implementar o 4B mesmo com as validacoes runtime dos MVPs 3A e 4A ainda pendentes.

Continuam pendentes:

- validar org/payroll em runtime real;
- validar daily stats/playtime em runtime real;
- validar os novos comandos 4B em servidor FiveM com DB.
