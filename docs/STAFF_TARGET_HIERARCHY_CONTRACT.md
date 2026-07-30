# Contrato de hierarquia sobre alvos Staff

## Guard oficial

```lua
local allowed, reason, context =
  exports['mz_core']:CanStaffActOnPlayer(actorSource, targetSource)
```

O export compara somente identidade e hierarquia. A permissão específica da ação continua sendo revalidada pelo resource chamador.

## Decisões

| Situação | Resultado | Motivo |
| --- | --- | --- |
| ator e alvo são o mesmo player | permite | `self` |
| ator é Owner ACE | permite | `owner_override` |
| alvo é Owner ACE | nega | `target_owner` |
| alvo não possui cargo Staff ativo | permite | `target_not_staff` |
| alvo é Staff e ator não possui nível Staff persistente | nega | `actor_without_staff_level` |
| nível do ator é igual ou inferior ao alvo | nega | `target_higher_or_equal` |
| alvo é Staff estritamente inferior | permite | `target_lower_staff` |
| ator/alvo não está carregado | nega | `actor_not_loaded` / `target_not_loaded` |

ACE ou override de uma permissão de comando não inventa nível hierárquico. Um ator sem cargo persistente pode operar um player comum quando possuir a permissão, mas não pode afetar um alvo Staff.

Membership na organização legada `staff` não participa da comparação.

## Integração atual

O `mz_admin` aplica o guard em:

- `bring`;
- `kick`;
- ban online pelo `mz_banguard`;
- `heal`;
- `revive`;
- `spectate`.

`goto` move somente o ator e não precisa comparar a hierarquia do destino. Heal/revive sem ID são enviados ao servidor com o próprio source para passar pela mesma autorização e auditoria.

## Auditoria

Cada tentativa server-side gera uma ação em `mz_logs`:

```text
admin.player.bring.authorized
admin.player.bring.denied
admin.player.kick.authorized
admin.player.kick.denied
admin.player.heal.authorized
admin.player.heal.denied
admin.player.revive.authorized
admin.player.revive.denied
admin.spectate.started
admin.spectate.switched
admin.spectate.stopped
admin.spectate.denied
admin.spectate.revoked
admin.spectate.target_lost
```

O payload inclui ator, alvo, CitizenIDs, cargos, níveis, Owner, permissão exigida, decisão, relacionamento e motivo. Coordenadas não são gravadas.

Ban revalida o mesmo export dentro do resource autoritativo antes da transação. Sua auditoria principal é `ban.created.integration` na tabela do BanGuard; o `mz_admin` também registra `admin.ban.create.completed|denied` no log global sem identifiers ou tokens.

Uma ação autorizada só é despachada se o log for persistido. Falha da auditoria cancela a ação. Uma tentativa já negada permanece negada mesmo se o banco de logs estiver indisponível e deixa diagnóstico estruturado no console.

## Fora do escopo

Wall possui contrato observacional próprio: não altera o alvo e por isso não consome este guard, mas exige permissão global, auditoria e revalidação contínua. Spectate consome o guard no início, na troca de alvo e durante a sessão. Kick consome o guard antes da auditoria e da remoção da sessão. Ban online consome o guard dentro do BanGuard antes da transação e ainda depende de aprovação runtime.
