# Lote 6 — auditoria de consumers e compatibilidade

## Revisão de alterações locais pós-Lote 5

Sem usar Git, a revisão por conteúdo e datas encontrou mudanças locais em spawn médico do core, harnesses de banco/medical, ordem de startup e logging de atividade suspeita no state service. Spawn, harnesses e ordem foram mantidos. O logging foi corrigido: fallback continua disponível para harness isolado, enquanto runtime usa observabilidade central, redaction, agregação e cooldown. Nenhuma mudança foi descartada automaticamente.

## Matriz de consumers

| Resource | Ação | Guard anterior | Guard final | Cleanup/compensação |
| -- | -- | -- | -- | -- |
| mz_core inventory | open/use/move/drop/pickup/storage/hotbar/ammo | parcial | `CanPlayerPerformAction` específico em cada entrada pública e direta | reservation cancel/rollback permanece |
| mz_inventory | UI/hotbar/storage | open parcial | guard local + fechamento em sync bloqueado; servidor continua decisivo | fechar UI permitido |
| mz_phone | open | somente requestOpen | guard central em todos os eventos de efeito | bankClose/endCall/decline/debugReport |
| mz_bank | operações | guard já existente | mantido e coberto por harness | fechar sessão permitido |
| mz_garagem | open/store/withdraw | parcial | respawn/spawn/snapshot/confirm também guardados | cancel/release/rollback permitidos |
| mz_vehicles/mz_fuel | enter/lock/drive/sirene/refuel/jerrycan | principalmente client/context | guards server-side `vehicle.enter/drive` e `inventory.use` | cancel refuel/cleanup permitido |
| mz_houses | enter/features | parcial | tax/door/purchase e features guardados | leave/session cleanup permitido |
| mz_clothing/mz_tatto | shop/save | distância/security lifecycle | `shop.use` antes de abrir/pagar/salvar | fechar lifecycle e admin skip-payment separados |
| mz_animations | emote | guard no start | cancelamento por bag/sync canônico | stop permitido |
| mz_progress | progress | morte física | bloqueio canônico no start/loop/sync | cancel callback permitido |
| mz_core client | arma/veículo/interação | controles bloqueados | mantém firing/controls e remove somente motorista bloqueado, com cooldown | alive não é afetado |
| mz_medical | tratamento/respawn | Lote 5 | guards/locks existentes + recovery e telemetria | cancel/abort/rollback permitidos |
| mz_creator | appearance | contrato de spawn/modelo | leitura por snapshot; lifecycle BanGuard mantido | close lifecycle permitido |

Não há endpoint central ativo de craft/trade. As ações `craft.use` e `trade.use` estão registradas para novos resources; qualquer futura implementação deve aplicar o guard. Comandos gameplay existentes são protegidos no domínio; comandos administrativos/cleanup não recebem bloqueio global de `command.use`.

## Inventário de contratos

| Contrato | Direção | Autorização/payload |
| -- | -- | -- |
| `GetPlayerState`, `CanPlayerPerformAction` | server resource → core | leitura; source server-side |
| `GetPlayerSnapshot`, `GetPlayerByCitizenIdSnapshot` | server resource → core | cópia read-only |
| `SetStatus`, `ApplyStatusPatch`, dano/cura/transições | server resource → core | allowlist exata por operação |
| `RecordPlayerStateEvent`, `ReportPlayerStateSuspicion` | status/medical/core → core | resource+prefixo/evento em allowlist; campos truncados/redigidos |
| `GetPlayerStateObservability` | admin → core | read-only; `mz_admin` |
| reservas médicas reserve/commit/cancel | medical → inventory core | `mz_medical`, source+operationId; terminal idempotente |
| `GetMedicalItemReservations` | medical/admin → core | read-only allowlist |
| `GetMedicalOperations`, `RecoverMedicalOperation` | admin/core staging → medical | read/recovery allowlists exatas |
| vital observation/resync | client → core | schema fechado, source implícito, token/revision, rate limit |
| medical help/start/complete/cancel/respawn/ack | client → medical | schema fechado, source implícito, session/op token/revision |
| state sync/bags | core → client | projeção; revision como commit marker |

## Depreciações

| Contrato antigo | Consumer | Substituto | Estado | Remoção planejada |
| -- | -- | -- | -- | -- |
| `GetPlayer` mutável | consumers legados externos | `GetPlayerSnapshot` | mantido, warning único; consumers ativos migrados | major após duas versões staging sem uso |
| `GetPlayerByCitizenId` mutável | consumers legados | snapshot por citizenid | mantido, warning único | mesma condição |
| QB `SetMetaData`/metadata patch | aliases QB | SetStatus/ApplyStatusPatch | protegido e warning único | major após inventário zero |
| aliases QB/flags isdead/inlaststand | compatibilidade | APIs/DTO canônicos | projeção, não truth | após migração de ecossistema |
| evento HUD legado | mz_hud legado | snapshot revisionado | adapter mantido | após HUD consumir só contrato novo |
| spawnmanager bootstrap | core spawn | futuro bootstrap canônico | vendor aprovado | somente com substituto runtime-validado |

## Balanceamento preservado

| Parâmetro | Default | Impacto aproximado | Decisão |
| -- | -- | -- | -- |
| hunger | -1/90 s | esvazia em ~150 min | mantido, sem playtest |
| thirst | -1/60 s | esvazia em ~100 min | mantido, sem playtest |
| stress passivo | política existente | depende de atividade/cooldown | mantido |
| dano crítico | scheduler existente | dano periódico quando zero | mantido |
| downed | 300 s | janela de atendimento de 5 min | mantido |
| respawn | 180 s | espera dead de 3 min | mantido |
| firstaid | 10 s | exposição do atendimento | mantido |

## Exceções conhecidas das varreduras

`spawnmanager` chama `NetworkResurrectLocalPlayer` somente para bootstrap aprovado; o core reaplica o estado. Referências `_local_backups/` e `ref/` não são resources ativos. O creator troca modelo, mas não escreve health/armor. Não existe runtime executado nesta auditoria.
