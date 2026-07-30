# Checklist runtime do guard Staff sobre alvos

Não marcar como aprovado sem executar em staging.

## Preparação

- [ ] Reiniciar `mz_core` e `mz_admin`.
- [ ] Preparar Owner, Administrador 700, Moderador 300, dois Staff de mesmo nível e um player comum.
- [ ] Conceder manualmente `staff.players.bring` aos cargos já existentes que participarão do teste.

## Matriz

- [ ] Staff executa bring/heal/revive em player comum.
- [ ] Staff superior executa as ações em Staff inferior.
- [ ] Staff não executa as ações em Staff de mesmo nível.
- [ ] Staff inferior não executa as ações em Staff superior.
- [ ] Nenhum Staff persistente executa as ações no Owner.
- [ ] Owner executa as ações em qualquer alvo.
- [ ] Heal/revive em si continuam funcionando.
- [ ] Alvo desconectado ou contexto não carregado falha fechado.
- [ ] Chamada direta dos eventos não contorna permissão nem hierarquia.

## Logs

- [ ] Cada autorização gera `admin.player.<ação>.authorized`.
- [ ] Cada negação gera `admin.player.<ação>.denied`.
- [ ] Log contém ator, alvo, cargos, níveis, permissão, decisão e motivo.
- [ ] Log não contém coordenadas.
- [ ] Indisponibilidade simulada da auditoria cancela uma ação que seria autorizada.

## Evidência

Registrar cargos/níveis, comando, resultado esperado, resultado observado e IDs dos registros em `mz_logs`.
