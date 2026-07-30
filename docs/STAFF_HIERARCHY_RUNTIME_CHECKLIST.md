# Checklist runtime da hierarquia Staff

Itens nao executados permanecem desmarcados.

## Preparacao

- [ ] Usar staging descartavel, sem VPS ou producao.
- [ ] Reiniciar `mz_core` e confirmar a criacao das tres tabelas Staff.
- [ ] Confirmar os cargos padrão `suporte`, `moderador`, `administrador` e `gerente_staff`.
- [ ] Confirmar que não existe cargo persistido para Owner/Staff Supremo.
- [ ] Reiniciar `mz_admin`.
- [ ] Preparar owner ACE, dois players de teste e seus CitizenIDs.

## Owner

- [ ] Owner abre `/admin` e ve `Gerenciar equipe Staff`.
- [ ] Editar um cargo padrão e confirmar que a alteração permanece após restart.
- [ ] Criar um cargo adicional com nível distinto.
- [ ] Codigo duplicado e nivel duplicado sao recusados.
- [ ] Definir permissoes pelo catalogo.
- [ ] Atribuir cargo a player online e offline.

## Staff delegado

- [ ] Player atribuido recebe `/admin` conforme `staff.panel.open`.
- [ ] Permissoes entram em vigor sem reconnect.
- [ ] `staff.roles.manage` permite listar apenas cargos/alvos inferiores.
- [ ] Staff cria e edita cargo inferior.
- [ ] Staff nao cria cargo igual ou superior ao proprio nivel.
- [ ] Staff nao concede permissao que nao possui.
- [ ] Staff nao altera a propria atribuicao.
- [ ] Staff nao altera owner ou Staff igual/superior.

## Ciclo de vida

- [ ] Revogar remove as permissoes sem apagar historico.
- [ ] Cargo com atribuicao ativa nao pode ser desativado.
- [ ] Depois de revogar todas as atribuicoes, cargo pode ser desativado.
- [ ] Reinicio preserva cargos, permissoes e atribuicoes.
- [ ] Membership organizacional com `staff.*` legado continua ignorada.
- [ ] Criacao/edicao de cargo, permissoes, atribuicao e revogacao geram registros `staff.*` em `mz_logs` com ator, alvo e motivo.

## Evidencia

Registrar ator, nivel, alvo, nivel do alvo, acao, resultado esperado, resultado observado e trecho de console. Nao aprovar runtime sem executar.
