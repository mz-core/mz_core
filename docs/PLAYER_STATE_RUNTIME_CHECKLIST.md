# Player State — checklist consolidado de runtime

Preencha `PLAYER_STATE_RUNTIME_RESULTS.md`. Nunca marque aprovado sem log/estado/bag/revision ou evidência equivalente. Tokens devem ser mascarados.

## Preparação

- Servidor staging com OneSync, MySQL descartável e ordem de startup documentada.
- Dois jogadores, um médico ambulance grade 2+ em duty e um admin com ACE de staging.
- Itens `water`, `bread`, `bandage`, `firstaid`; saldos antes/depois capturados.
- `set mz_player_state_staging 1` e ACE `mz.player_state.staging` somente durante o teste.
- Console server/client, observabilidade, logs do banco/inventário/medical e consulta SQL disponíveis.
- Billing hospitalar off, item loss none e debug de produção off.

Cada linha contém: ID, pré-condição, comando/ação, resultado e logs esperados, evidência, status e observação.

## Carregamento

| ID | Pré-condição | Comando/ação | Resultado esperado | Logs esperados | Evidência | Status | Observação |
| -- | -- | -- | -- | -- | -- | -- | -- |
| LOAD-01 | Personagem novo | Conectar/criar | Defaults normalizados; token/revision novos; bags coerentes | normalized/load sem erro | snapshot+bags+SQL | NÃO EXECUTADO | — |
| LOAD-02 | Metadata antiga/inválida em staging | Conectar | Correções conservadoras persistidas uma vez | player_state_normalized | antes/depois+auditId | NÃO EXECUTADO | Não editar DB durante o caso |
| LOAD-03 | Estado dead persistido | Reconnect e troca de personagem | Dead preservado; source não herda sessão | sessão substituída; stale antiga recusada | token mascarado+revision | NÃO EXECUTADO | — |

## Vitais

| ID | Pré-condição | Comando/ação | Resultado esperado | Logs esperados | Evidência | Status | Observação |
| -- | -- | -- | -- | -- | -- | -- | -- |
| VIT-01 | Alive 150/60 persistido | Reconnect | Ped/core/bags convergem 150/60 | sync/reconcile sem mismatch persistente | native+snapshot+bags | NÃO EXECUTADO | — |
| VIT-02 | Alive 200/100 | Sofrer dano health/armor | Somente reduções aceitas; revision cresce | vital accepted | antes/depois | NÃO EXECUTADO | — |
| VIT-03 | Alive, last stand on/off | Dano fatal real | Downed ou dead conforme config, nunca alive health 0 | transition auditada | ped+snapshot+SQL | NÃO EXECUTADO | — |
| VIT-04 | Alive/dead com modelo autorizado | Trocar modelo | Estado/armor reaplicados; dead não revive | model ready/reconciled | native+revision | NÃO EXECUTADO | — |

## Status

| ID | Pré-condição | Comando/ação | Resultado esperado | Logs esperados | Evidência | Status | Observação |
| -- | -- | -- | -- | -- | -- | -- | -- |
| STA-01 | Hunger/thirst 100 | Aguardar 90/60 s | -1 nos intervalos, sem flush/tick ruidoso | métricas de lote | snapshot+SQL após debounce | NÃO EXECUTADO | Defaults mantidos sem playtest |
| STA-02 | Stress baixo | Dano, tiro e direção rápida | Incrementos server-confirmed/cooldown | activity rejected apenas inválidos | revisions | NÃO EXECUTADO | — |
| STA-03 | Itens e status abaixo do máximo | Usar water/bread/bandage | Um item e um efeito; clamp; no_benefit não consome | consumable start/complete | Quatro operações `water`/`bread` auditadas, revisions 1/2/4/5, zero rollback/falha; stack, clamp, `no_benefit` e bandage confirmados visualmente pelo operador | APROVADO | Scheduler reduziu hunger/thirst após o clamp, como esperado. |
| STA-04 | Hunger/thirst zero | Aguardar dano crítico | Dano em lote; fatal usa transição oficial | status_critical_damage | health/revision | NÃO EXECUTADO | — |

## Downed e dead

| ID | Pré-condição | Comando/ação | Resultado esperado | Logs esperados | Evidência | Status | Observação |
| -- | -- | -- | -- | -- | -- | -- | -- |
| DD-01 | Player alive | `mz_state_down <id>` | Timer/apresentação/bloqueios; sem dirigir/atirar/interagir | transition/sync | vídeo+bags | NÃO EXECUTADO | — |
| DD-02 | Downed | Restart HUD/core client/medical e reconnect | Deadline não reinicia; apresentação recomposta | resync/rebuild | timestamps antes/depois | NÃO EXECUTADO | — |
| DD-03 | Downed perto do prazo | Aguardar e concorrer revive | Apenas CAS vencedor; dead consistente | rejection revision no perdedor | auditIds | NÃO EXECUTADO | Dois jogadores |
| DD-04 | Dead | Tentar inventário/banco/garagem/phone/emote/propriedade | Efeitos recusados; cleanup permitido | rejeições agregadas | logs+estado | NÃO EXECUTADO | — |

## Medicina

| ID | Pré-condição | Comando/ação | Resultado esperado | Logs esperados | Evidência | Status | Observação |
| -- | -- | -- | -- | -- | -- | -- | -- |
| MED-01 | Médico válido/inválido, duty/grade variados | `/treat` perto de downed | Só policy válida inicia e reserva firstaid | treatment_started ou razão fechada | operationId+reserva | NÃO EXECUTADO | — |
| MED-02 | Operação ativa | Cancelar, afastar, disconnect executor/alvo | Rollback exato; alvo continua downed | cancelled/rollback | item instance+op | NÃO EXECUTADO | — |
| MED-03 | Dois médicos, mesmo alvo | Iniciar simultâneo | Um lock/reserva/efeito | target busy | dois consoles+inventário | NÃO EXECUTADO | Dois jogadores |
| MED-04 | Operação válida 10 s | Completar/repetir complete | Uma transição/commit; replay não duplica | completed | revision+stack+ped | NÃO EXECUTADO | — |

## Respawn

| ID | Pré-condição | Comando/ação | Resultado esperado | Logs esperados | Evidência | Status | Observação |
| -- | -- | -- | -- | -- | -- | -- | -- |
| RES-01 | Dead antes/depois do prazo | Solicitar respawn | Antes recusa; depois entra respawning | respawn_started | deadline+operationId | NÃO EXECUTADO | — |
| RES-02 | Respawning | Completar spawn Pillbox/ack | Server escolhe 298.71,-584.98,43.26/68; alive 200/0 | completed | coords+ped+revision | NÃO EXECUTADO | — |
| RES-03 | Ack bloqueado ou medical reiniciado | Aguardar timeout/restart | Abort para dead; órfão recuperável | aborted/orphan recovery | diag antes/depois | NÃO EXECUTADO | — |
| RES-04 | Billing off/item loss none | Respawn | Saldo e inventário inalterados | flags disabled | saldos/stacks | NÃO EXECUTADO | — |

## Consumers

| ID | Pré-condição | Comando/ação | Resultado esperado | Logs esperados | Evidência | Status | Observação |
| -- | -- | -- | -- | -- | -- | -- | -- |
| CON-01 | Downed/dead | Abrir/usar/mover/drop/pickup/storage/hotbar | Todos recusados no servidor e UI fecha | player_state_blocked | inventário antes/depois | NÃO EXECUTADO | — |
| CON-02 | Downed/dead | Banco, garagem, propriedade, telefone, lojas | Mutations recusadas; close/cancel funcionam | rejeições com cooldown | ATM, telefone e garagem recusados em downed; saldo e veículo guardado preservados. Propriedade recusada dentro/fora em downed e fora em dead; remoção segura do interior e restauração alive aprovadas | PARCIAL | Falta testar lojas e repetir em dead os demais consumers. |
| CON-03 | Emote/progress ativos | Forçar downed | Cancelamento imediato | sem efeito tardio | vídeo+callback | NÃO EXECUTADO | — |
| CON-04 | Motorista alive | Forçar downed | Firing/control bloqueado e sai do banco do motorista | transition | vídeo+vehicle state | NÃO EXECUTADO | — |
| CON-05 | Arma canônica | Atirar/forjar ammo | Alive válido; bloqueado não usa/fire; ammo server-authoritative | weapon rejection | ammo+state | NÃO EXECUTADO | — |

## Segurança

| ID | Pré-condição | Comando/ação | Resultado esperado | Logs esperados | Evidência | Status | Observação |
| -- | -- | -- | -- | -- | -- | -- | -- |
| SEC-01 | Sessão ativa | Forjar target/extra/amount/death/fee/coords | Schema/authority recusam sem mutation | invalid_payload agregado | payload redigido+snapshot | NÃO EXECUTADO | — |
| SEC-02 | Reconnect no mesmo source | Reusar token/revision/op antiga | session/identity mismatch | stale_session | tokens mascarados | NÃO EXECUTADO | — |
| SEC-03 | Resource não allowlisted | Chamar setter/bridge protegido | not_authorized e warning de legado controlado | suspicion agregada | resource+auditId | NÃO EXECUTADO | — |
| SEC-04 | Spam sync/medical/phone/staging | Exceder janela | Custo limitado, sem log por tentativa | rate_limited cooldown | contadores+logs | NÃO EXECUTADO | — |
| SEC-05 | Bags locais manipulados | Tentar ação privilegiada | Guard server-side prevalece e resync restaura projeção | divergence/reconcile | bags+snapshot | NÃO EXECUTADO | — |

## Infra

| ID | Pré-condição | Comando/ação | Resultado esperado | Logs esperados | Evidência | Status | Observação |
| -- | -- | -- | -- | -- | -- | -- | -- |
| INF-01 | Operação controlada | Tornar MySQL indisponível/restabelecer | pending explícito, recovery sem duplicar | persistence pending/failure | logs+SQL | NÃO EXECUTADO | Janela de crash deve ser registrada |
| INF-02 | Estados conhecidos | Restart de status/HUD/inventory/medical/core | Projeções recuperam; core apenas com plano/reconnect | stop/rebuild/resync | antes/depois | NÃO EXECUTADO | — |
| INF-03 | Dois jogadores | Dano/consumo/medical simultâneos | Locks, tokens e revisions isolados | sem cross-session | dois snapshots | NÃO EXECUTADO | — |
| INF-04 | Carga de staging | Sessões e ações repetidas controladas | Sem thread/SQL/log por player-frame; métricas estáveis | counters | profiler+SQL rate | NÃO EXECUTADO | Registrar hardware e duração |

Ao terminar, execute `set mz_player_state_staging 0`, remova a ACE e anexe somente evidência redigida ao arquivo de resultados.
