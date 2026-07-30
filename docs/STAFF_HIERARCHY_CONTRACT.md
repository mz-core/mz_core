# Contrato da hierarquia Staff

## Autoridade

`mz_core` e a autoridade de cargos, atribuicoes e resolucao de permissoes globais Staff. `mz_admin` e somente a interface.

Membership de organizacao, inclusive do tipo `staff`, nunca concede `staff.*`. O resolvedor global segue esta ordem:

1. owner ACE;
2. ACE explicito da permissao;
3. override oficial em `mz_player_permissions` (inclusive deny);
4. permissao do cargo Staff ativo.

## Persistencia

O prepare idempotente cria:

- `mz_staff_roles`;
- `mz_staff_role_permissions`;
- `mz_staff_assignments`.

Nao existe hard delete. Permissoes removidas recebem `allow=0`, cargos recebem `active=0` e atribuicoes revogadas recebem `active=0` com timestamp.

Cada CitizenID possui no maximo uma atribuicao atual, que pode ser reativada ou trocada. Owner continua fora das tabelas e e definido somente pelo ACE configurado.

## Base padrão

O bootstrap cria `suporte` (100), `moderador` (300), `administrador` (700) e `gerente_staff` (900) somente quando seus códigos estão ausentes e os níveis estão livres. Nenhum player é atribuído automaticamente.

Um cargo já existente nunca é sobrescrito pelo seed. O contrato e a matriz inicial estão em `STAFF_DEFAULT_ROLES.md`.

## Hierarquia

- niveis validos: 1 a 9999;
- owner possui nivel virtual 1000000;
- niveis de cargos sao unicos;
- ator administra somente cargos e alvos com nivel estritamente inferior;
- Staff nao altera a propria atribuicao;
- cargo com atribuicoes ativas nao pode ser desativado;
- codigo do cargo e imutavel;
- um Staff nao pode conceder permissao que ele proprio nao possui;
- somente permissoes do catalogo `shared/staff_permissions.lua` sao aceitas.

## Exports servidor

```lua
exports['mz_core']:GetStaffContext(source)
exports['mz_core']:CanStaffActOnPlayer(actorSource, targetSource)
exports['mz_core']:ListStaffManagement(source)
exports['mz_core']:CreateStaffRole(source, payload)
exports['mz_core']:UpdateStaffRole(source, roleCode, payload)
exports['mz_core']:SetStaffRolePermissions(source, roleCode, permissions, reason)
exports['mz_core']:AssignStaffRole(source, citizenid, roleCode, reason)
exports['mz_core']:RevokeStaffRole(source, citizenid, reason)
```

Todos os exports de mutacao revalidam `staff.roles.manage`, identidade carregada, nivel do ator, nivel do alvo, catalogo e motivo. Falha de core, banco ou validacao resulta em negacao.

## Escopo atual

Este lote entrega cargos, permissoes e atribuicoes. A proteção `actor > target` está aplicada a bring, kick, ban online, heal, revive e spectate pelo contrato `STAFF_TARGET_HIERARCHY_CONTRACT.md`. Goto move somente o ator. O wall é observacional, exige `staff.wall`, não executa mutação sobre alvo e segue o contrato `mz_admin/docs/WALL_CONTRACT.md`. Spectate segue `mz_admin/docs/SPECTATE_CONTRACT.md`. Ban pertence ao `mz_banguard`, possui integração estática e ainda exige instalação e aprovação runtime em staging.
