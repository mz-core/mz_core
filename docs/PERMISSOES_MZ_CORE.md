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

## Permissões granulares atuais

O grupo `group.mz_owner` continua sendo a autoridade administrativa máxima, mas o domínio de organizações já possui permissões globais Staff granulares e capabilities organizacionais.

Permissões `staff.*`:

- vêm somente de owner, ACE explícito ou override global explícito;
- nunca são resolvidas por cargo ou membership organizacional;
- não são aceitas por `CanOrg`.

Capabilities organizacionais:

- são resolvidas por membership, cargo, herança e overrides organizacionais válidos;
- nunca concedem acesso ao Staff Menu;
- incluem `members.set_leader`, que não equivale a `staff.orgs.set_leader`.

No Lote 6D, `TransferOrganizationLeadership` exige membership ativo e `members.set_leader` diretamente revalidados. Owner/ACE/Staff não são fallback nesse export. O export administrativo `SetOrgLeaderByCitizenId` continua separado e exige autorização Staff.

Liderança organizacional é suportada apenas por `job`, `gang`, `business`, `government` e `event`. O tipo `vip` representa níveis de privilégios futuros e não possui líder. Para VIP:

- `CanOrg(..., 'members.set_leader')` falha fechado, inclusive para owner ou override;
- apenas `org.view`, `members.view`, `logs.view` e capabilities `vip.*` podem ser efetivas;
- membership e nível são administrados pelo Staff; VIP não convida, remove, promove ou rebaixa;
- contextos e modelos de acesso não anunciam capabilities legadas incompatíveis;
- os dois contratos de liderança retornam `leadership_not_supported`;
- novas concessões incompatíveis são recusadas;
- a remoção de um registro legado incompatível continua disponível para Staff com autorização adequada.

Permissões granulares de outros módulos, como economia ou telefone, continuam dependendo de decisão e contrato próprios.
