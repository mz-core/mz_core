# Segurança do Player State

## Fronteiras de confiança

MySQL e serviços server-side do core são confiáveis dentro de seus contratos. Resources server-side são autorizados por allowlist exata via `GetInvokingResource`. Client, NUI, state bags replicados e qualquer payload de evento são não confiáveis. BanGuard e staff são autoridades separadas; um alerta de player state não é prova automática de abuso.

## Eventos e exports

Eventos client usam source implícito, schema fechado, tipos/limites, rate limit e validações de sessão, token, revision, estado, target, bucket, ped e distância. Complete/ack exigem operação server-owned. Não há evento livre de revive, complete respawn, fee, coordenadas hospitalares ou effect amount.

Exports mutáveis exigem allowlist. `GetPlayerSnapshot` é o contrato de leitura. `GetPlayer` mutável e aliases QB são compatibilidade deprecada; metadata protegida continua bloqueada e warnings são emitidos uma vez por consumer.

## Sessão, revision e source reutilizado

Token identifica a sessão atual e nunca deve ser logado. Revision faz CAS/ordenação; payload stale é recusado. OperationId/token amarram atendimento e respawn. Ao disconnect, runtime, rate windows e operações são limpos/cancelados. Callback antigo entregue a um source reutilizado falha por sessão/identity/revision.

## State bags e client candidates

Bags são projeções server-owned e `mz:stateRevision` é o commit marker. Consumers podem antecipar bloqueio visual, mas precisam repetir o guard no servidor. Observações físicas de health/armor e atividade são candidatos limitados; o servidor impede aumento observado, target arbitrário e transições incompatíveis.

## Rate limits e abuso

Há limites por source/ação em sync/resync, medical, status, phone e staging. Rejeições são agregadas e logs têm cooldown. Evidência de alta cardinalidade é truncada: profundidade 4, até 32 campos, strings até 256 caracteres e eventos/categorias em allowlist.

## Alertas e resposta

Categorias como sessão stale, payload inválido, rate limit, observação impossível, metadata protegida e recovery exaurido agregam source, contagem, janela, severidade e resumo redigido. O operador deve correlacionar auditId, revision, operação, logs do consumer e incidentes do BanGuard. Falsos positivos possíveis: lag, troca de modelo, restart e atraso OneSync; confirme antes de sancionar.

Resposta recomendada: preservar evidência, limitar o endpoint se necessário, verificar sessão/source, reproduzir em staging e somente então usar o fluxo de incidente/sanção do BanGuard. O domínio não chama auto-ban.

## Limitações aceitas

- state bags são visíveis e eventualmente consistentes;
- OneSync pode atrasar ped/distância, gerando rejeição conservadora;
- spawnmanager é vendor aprovado apenas para bootstrap; o core reaplica verdade canônica;
- não há transação distribuída total entre metadata, inventário e efeitos médicos;
- reservas médicas ficam em memória, com terminal cache e recovery, mas crash de processo ainda abre janela;
- runtime FiveM/MySQL real não é provado por harness offline.

## Revisão de produção

Staging/debug off; billing off; item loss none; dead revive off; allowlists sem wildcard; comandos protegidos por convar+ACE; tokens redigidos; cleanup estreito; nenhum SQL de estado fora do core; nenhum native físico fora do client canônico/vendor aprovado.

