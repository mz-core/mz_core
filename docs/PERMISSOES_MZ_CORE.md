# Permissoes do mz_core

## Grupo owner

O projeto usa `group.mz_owner` como grupo administrativo principal.

```cfg
add_ace group.mz_owner command allow
add_ace group.mz_owner command.quit deny
add_ace group.mz_owner group.mz_owner allow

add_principal identifier.fivem:SEU_ID_FIVEM_AQUI group.mz_owner
add_principal identifier.fivem:ID_DO_SOCIO_AQUI group.mz_owner
```

## Economia

Os comandos administrativos do `mz_economy` devem seguir o padrao do `mz_core` e serem restritos ao owner/socio.

Nao usar como padrao a combinacao antiga de `group.admin` com permissao granular de economia. O padrao atual e o grupo `group.mz_owner`.

## Console

Os comandos administrativos do `mz_economy` continuam permitindo execucao pelo console (`source == 0`), preservando o comportamento ja existente nos roteiros de validacao.

O comando `mz_money_add` e console-only. Ele nao depende de chat/ACE de player porque `source` precisa ser `0`; se um player tentar usar pelo chat, o comando e negado.

## Observacao

Se no futuro o projeto quiser permissoes granulares por modulo, isso deve ser decidido explicitamente e documentado, por exemplo:

- `mzcore.economy.manage`
- `mzcore.org.manage`
- `mzcore.phone.manage`

Mas o padrao atual e `group.mz_owner`.
