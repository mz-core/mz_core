# Cargos Staff padrão

## Autoridade máxima

O Staff Supremo é o dono do servidor resolvido pelo ACE configurado em `Config.OwnerAce`, atualmente `group.mz_owner`.

Ele possui nível virtual `1000000`, não recebe uma linha em `mz_staff_roles` e nunca é atribuído por CitizenID no menu. Remover ou trocar o dono continua sendo uma operação de configuração ACE fora do banco Staff.

## Templates

Em um banco sem esses códigos, o bootstrap cria:

| Código | Nome | Nível | Escopo inicial |
| --- | --- | ---: | --- |
| `suporte` | Suporte | 100 | painel, coordenadas, lista, goto, heal e revive |
| `moderador` | Moderador | 300 | Suporte + noclip, wall, teleporte, bring protegido, colete, reparo e advertências |
| `administrador` | Administrador | 700 | Moderador + spectate, kick, ban online, consulta de bans, whitelist, revogação de advertências, godmode, veículos, garagens, leitura/operação de membros e logs |
| `gerente_staff` | Gerente Staff | 900 | Administrador + revogação de bans, cargos Staff e gestão completa de organizações |

As listas exatas estão em `server/seed/default_staff.lua` e usam somente permissões existentes em `shared/staff_permissions.lua`.

Nenhum template recebe permissões de armas nativas. `staff.wall` começa no Moderador; `staff.spectate`, `staff.players.kick`, `staff.players.ban`, `staff.bans.view`, `staff.whitelist.view` e `staff.whitelist.manage` começam no Administrador. `staff.bans.revoke` começa no Gerente Staff.

`staff.players.bring` começa no Moderador e passa pelo guard hierárquico do servidor. Cargos já existentes não recebem essa permissão automaticamente; o Owner deve concedê-la manualmente depois de validar o guard runtime.

O mesmo princípio idempotente vale para `staff.wall`: cargos já existentes não recebem a permissão automaticamente. O Owner deve concedê-la no menu de cargos depois de validar o wall em runtime.

`staff.spectate` também não é adicionada silenciosamente a cargos existentes. Depois do teste runtime, o Owner pode concedê-la aos cargos adequados pelo menu.

`staff.players.kick` começa no Administrador. Como nos demais templates, cargos já existentes precisam receber a permissão manualmente depois do teste runtime.

As permissões de ban e whitelist também não são adicionadas silenciosamente a cargos existentes. O Owner deve conceder as permissões necessárias aos cargos já persistidos pelo gerenciador Staff.

As permissões `staff.warns.view` e `staff.warns.issue` começam no Moderador. `staff.warns.revoke` começa no Administrador. Cargos já existentes não são modificados pelo seed; o Owner deve conceder essas permissões manualmente depois de validar `mz_warns` em runtime.

## Idempotência

- cargo ausente e nível livre: cria o cargo e suas permissões em uma transação;
- código já existente: preserva integralmente nome, nível, estado e permissões;
- nível ocupado por outro código: não altera o ocupante e registra `level_conflict`;
- nenhum player recebe atribuição automática;
- restart não restaura permissões removidas nem adiciona permissões novas silenciosamente;
- não existe hard delete ou alteração de dados reais pelo seed.

Os templates são ponto de partida. Depois da primeira criação, o menu protegido por `staff.roles.manage` é a autoridade de personalização.
