# Inventory Item Access Contract

Data: 2026-09-07  
Consumer inicial: `mz_phone`

O inventário canônico continua sendo a autoridade de posse/localização de `instance_uid`. Este contrato mantém sessão lógica com um item e serializa somente o trecho curto de autorização/commit.

## Exports server-only

| Export | Resultado | Efeito |
|---|---|---|
| `AcquireInventoryItemAccess(source, instanceUid, itemName, purpose)` | `true, leaseSnapshot` ou erro | Confirma item no inventário principal e cria token sem manter lock |
| `ValidateInventoryItemAccess(source, accessToken)` | `true, leaseSnapshot` ou erro | Revalida source, citizenid, prazo e custody version |
| `BeginInventoryItemOperation(source, accessToken)` | `true, permit` ou erro | Revalida item e mantém lock do container |
| `EndInventoryItemOperation(source, permitToken)` | `true` ou erro | Encerra exatamente o permit do mesmo source |
| `ReleaseInventoryItemAccess(source, accessToken)` | `true` ou erro | Revoga lease e permits relacionados |

Somente `mz_phone` é aceito por `GetInvokingResource`. Tokens não são IDs de domínio e não devem ser persistidos ou enviados ao client.

## Lock e custody

Lease dura até 20 minutos, é renovada no begin e não bloqueia movimentação. Permit tem deadline diagnóstico de 15 segundos, mas somente `EndInventoryItemOperation` libera o lock. `playerDropped` e stop de `mz_phone` revogam lease/permits; outro source não valida nem encerra o token.

Toda mutação compara `instance_uid → container/slot` antes/depois do commit. Instância adicionada, removida ou movida recebe nova custody version, revoga lease e emite `mz_core:server:inventory:itemAccessInvalidated(instanceUid, version, reason)`. Slot/player/stash/trunk/drop preservam o UID. O payload do handler oficial agora inclui `instance_uid`.

Erros estáveis: `not_authorized`, `item_selection_required`, `item_not_held`, `item_access_invalid`, `item_access_expired`, `item_access_holder_mismatch`, `item_access_identity_changed`, `item_access_revoked`, `item_operation_invalid`, `item_operation_holder_mismatch`, `inventory_busy`.

`tests/inventory_item_access_harness.lua` valida seleção, holder, retenção além do deadline, fim explícito e cleanup. Consumable e player transfer protegem regressões. Para rollback, remover primeiro o uso dos exports pelo consumer; não mudar `instance_uid` nem liberar permits ativos por timer.
