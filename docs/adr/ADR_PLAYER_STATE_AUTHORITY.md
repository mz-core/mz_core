# ADR — autoridade do Player State

- Status: aceito para Lote 6
- Data: 2026-08-08

## Decisão

O `mz_core` é a única autoridade para vitais, death state, revision, sessão, metadata persistida e aplicação física. O client observa o ped e apresenta o estado, mas só envia candidatos fechados. `mz_status` e `mz_medical` permanecem separados porque possuem políticas e ciclos operacionais próprios, consumindo APIs canônicas.

Metadata continua no objeto player/cache para preservar persistência e compatibilidade do ecossistema. Leitores novos recebem cópia por `GetPlayerSnapshot`; o objeto mutável legado permanece temporariamente com warning. Aliases QB e flags `isdead/inlaststand` são projeções de compatibilidade, não fontes de verdade.

Não existe transação distribuída total entre core, inventário, efeito médico e contas. Operações usam CAS/revision, reservation/commit/rollback, operationId, cache terminal, retry com backoff e recovery administrativo. Isso reduz duplicação e perda silenciosa, mas não elimina a janela de crash entre efeitos em memória.

Billing hospitalar e item loss ficam off por default. Billing só poderá ser habilitado após uma saga debit/refund/replay validada com MySQL real. Item loss exige adapter com preview determinístico, categorias protegidas, idempotência e recovery; esse contrato não existe.

## Consequências

Consumers precisam de guard server-side e não podem escrever vitais/bags diretamente. State bags e HUD são eventualmente consistentes. Spawnmanager continua aprovado para bootstrap, seguido pela reaplicação do core. BanGuard recebe apenas integração read-only/operacional até existir contrato explícito de ingestão.

## Remoções futuras

`GetPlayer` mutável, evento HUD legado, `SetMetaData`, flags QB e aliases só podem ser removidos após inventário de zero consumers em duas versões de staging e anúncio de versão major. Spawnmanager só sai quando houver substituto de bootstrap validado em runtime.

