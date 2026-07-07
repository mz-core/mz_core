# Comandos console do mz_core

## mz_money_add

Uso:

```txt
mz_money_add <source> <wallet|bank|dirty|cash|money|black_money> <amount> [reason]
```

Exemplo:

```txt
mz_money_add 1 wallet 1000 teste_runtime
```

Regras:

- Somente console do servidor.
- Player nao pode usar pelo chat.
- Neste MVP aceita apenas `source` numerico online e carregado no `mz_core`.
- Usa `MZAccountService.addMoney`, o mesmo caminho oficial do export `mz_core:AddMoney`.
- Nao mexe diretamente em `mz_player_accounts`.
- Nao chama `mz_economy:RecordTransaction` diretamente.
- Ledger registra via wrapper como `admin_adjustment`, quando `mz_economy` esta online.
- Nao conta como renda.
- Nao conta como despesa.
- Serve para testes e ajustes administrativos.

Metadata enviada:

```lua
{
  reason = reason or 'console_money_add',
  category = 'admin_adjustment',
  source_resource = 'mz_core',
  source_type = 'console_command',
  counts_as_income = false,
  counts_as_expense = false,
  data = {
    command = 'mz_money_add',
    target = targetArg,
    account = normalizedAccount,
    amount = amount
  }
}
```

Aliases de conta:

- `cash` -> `wallet`
- `money` -> `wallet`
- `black_money` -> `dirty`

Teste manual:

```cfg
ensure oxmysql
ensure mz_core
ensure mz_economy
```

No console:

```txt
mz_money_add 1 wallet 1000 teste_runtime
```

Esperado:

- player source `1` recebe `1000` em `wallet`;
- `/mzecon_report` mostra `direction = in`, por ser `AddMoney`;
- a categoria fica `admin_adjustment`;
- `income` continua `0`;
- `expense` continua `0`;
- `unknown` nao aumenta para esse comando;
- ledger mostra `source_resource = mz_core`;
- ledger mostra `source_type = console_command`.

Resultado runtime registrado:

- `mz_money_add 1 wallet 10000 teste_runtime` executado pelo console;
- dinheiro entrou no player;
- ledger registrou `source_resource = mz_core`;
- ledger registrou `category = admin_adjustment`;
- ledger registrou `direction = in`, por ser `AddMoney`;
- `counts_as_income = 0`;
- `counts_as_expense = 0`;
- `unknown = 0`;
- player nao conseguiu usar pelo chat.

Teste pelo chat:

```txt
/mz_money_add 1 wallet 1000 teste
```

Esperado:

- nao adiciona dinheiro;
- retorna `Este comando so pode ser usado pelo console do servidor.`

Teste com `mz_economy` parado:

```txt
stop mz_economy
mz_money_add 1 wallet 100 teste_offline
ensure mz_economy
```

Esperado:

- dinheiro adiciona;
- nao ha erro fatal;
- nao duplica;
- ledger apenas nao registra enquanto `mz_economy` esta offline.
