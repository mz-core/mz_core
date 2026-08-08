# Operação do domínio Player State

## Arquitetura e startup

`mz_core` mantém metadata/cache, revision, sessão, persistência, sync e aplicação física. `mz_status` agenda decay/dano crítico. `mz_medical` mantém operações temporárias de atendimento/respawn. `mz_inventory`, `mz_hud` e os consumers usam os contratos do core.

Ordem mínima: `oxmysql`, `ox_lib`, `spawnmanager`, `mz_core`, `mz_economy`, `mz_inventory`, `mz_status`, `mz_progress`, `mz_medical`, `mz_bank`, `mz_phone`, demais consumers, `mz_admin` e `mz_banguard` conforme a configuração local. O `mz_starter/cfg/resources.cfg` segue essa dependência.

## Produção e staging

Produção: `set mz_player_state_staging 0`, debug off, billing hospitalar off, item loss `none`, revive de dead por player off, allowlists exatas e rate limits ativos.

Staging: conceda ACE `mz.player_state.staging` somente ao operador e use `set mz_player_state_staging 1`. Remova a ACE e volte o convar a zero ao terminar.

Comandos protegidos: `mz_state_diag <source>`, `mz_state_runtime <source>`, `mz_state_bags <source>`, `mz_state_down <source>`, `mz_state_dead <source>`, `mz_state_revive <source>`, `mz_status_set <source> <status> <value>`, `mz_state_metrics`, `mz_medical_diag <source>`, `mz_medical_ops` e `mz_medical_recover <operationId>`.

O console do servidor também pode executar `mz_status_diag <source>`. Ele compara a leitura do snapshot e da identidade de sessão feita pelo próprio `mz_status`; jogadores não podem executar esse comando.

## Métricas, logs e alertas

`GetPlayerStateObservability` é read-only e permitido a `mz_admin`. Contadores incluem players por estado, transições/rejeições, sync/resync, vitais/rejeições, persistence pending/failure, ticks de status, dano crítico, consumíveis/rollback e operações médicas.

Eventos estruturados carregam `auditId`, `operationId`, source/target, resource, revision, razão, resultado e erro. Tokens, metadata e identifiers são removidos. Alertas suspeitos agregam por source+categoria em janela, têm threshold e cooldown e nunca banem automaticamente. O painel administrativo pode ler o snapshot; o BanGuard permanece autoridade de sanção e não recebe incidente forçado sem contrato público de ingestão.

## Runbooks

### Player preso ou divergente

1. Rode `mz_state_diag`, `mz_state_runtime` e `mz_state_bags`.
2. Compare deathState, revision, bags e ped.
3. Consulte `mz_state_metrics` e logs pelo auditId.
4. Peça resync/reconnect; não altere bags manualmente.
5. Se respawning estiver órfão, use `mz_medical_diag` e recovery oficial.

### Operação médica pending

1. Rode `mz_medical_ops` e localize operationId/estado/retryAt.
2. Aguarde o backoff exponencial limitado quando a dependência voltou.
3. Use `mz_medical_recover <operationId>` somente após confirmar inventário/core saudáveis.
4. Estados `commit_exhausted` e `rollback_exhausted` exigem revisão humana; não remova item via SQL.

### Persistence pending/MySQL offline

Não reinicie em cascata nem repita a ação financeira. Preserve logs/auditId, restabeleça MySQL, confirme o flush/recovery e compare metadata persistida com o snapshot. A memória pode conter o efeito enquanto a gravação está pendente. Um crash nesse intervalo ainda pode perder o último estado.

### Restart

Restart de HUD/inventory/status deve reconstruir projeções sem reset. Restart de medical cancela operações e recupera respawn órfão para dead. Restart do core requer staging, dependentes conhecidos e reconnect; capture estado antes/depois. Cleanup e rollback permanecem autorizados mesmo quando novas ações estão bloqueadas.

### Dois jogadores e carga

Use dois clients com tokens distintos. Verifique isolamento de source/revision/operação, locks sem cruzamento e ausência de SQL/log por frame. O scheduler de status é global e em lote; não existem threads server-side por player.

## Billing e item loss

Defaults são `billing.enabled=false`, `billing.policy=free` e `itemLoss.mode=none`. Embora contas tenham idempotência, não há saga médica completa de debit/refund/recovery validada em runtime; não habilite billing. Não existe adapter seguro de preview/categorias protegidas/recovery para perda de itens; mantenha `none`.

## Diagnóstico de hospital

O ponto canônico é Pillbox `298.71, -584.98, 43.26`, heading `68.0`, coerente com o IPL local `pillbox_hospital`. Client não escolhe coordenada, fee, health ou armor.
