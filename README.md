<p align="center">
  <img src="./assets/logo.svg" alt="mz_core logo" width="260">
</p>

<p align="center">
  Framework própria para FiveM, modular e focada em núcleo limpo.
</p>

Esta versao documenta o estado real do recurso como base v1.0 do core. Isso nao significa framework completo, compatibilidade total com recursos externos ou ecossistema pronto. Significa que os modulos centrais do proprio `mz_core` ja sustentam uma base tecnica coerente para bootstrap, player, orgs, accounts, inventory, vehicles, logs e API publica do core.

## Filosofia do projeto

- O core deve ser dono da base tecnica do servidor: identidade, sessao, orgs, economy base, inventory base, vehicles base, logs e persistencia.
- O banco e a fonte de verdade. `config.lua` define parametros operacionais, nao o estado real do servidor.
- A organizacao do codigo e por dominio. Cada dominio deve concentrar service, repository, exports, events e commands quando fizer sentido.
- UI, HUD, phone, garagem visual, targets e gameplay especifico devem ficar fora do coracao do core.
- Bridges sao adaptadores opcionais. O core nao deve ser moldado pelos contratos de frameworks externos.

## Escopo real atual

| Area                              | Status                 | Observacao                                                                                     |
| --------------------------------- | ---------------------- | ---------------------------------------------------------------------------------------------- |
| Prepare / bootstrap / seed        | Validado               | Schema, migracoes defensivas, seed padrao e gate de readiness existem                          |
| Player / identidade / sessao      | Validado com ressalvas | Load, unload, cache, sessao e posicao existem; multichar nao existe                            |
| Orgs / grades / permissoes        | Validado               | Dominio forte e funcional no escopo atual                                                      |
| Accounts / org accounts / payroll | Validado com ressalvas | Core funciona; payroll ainda nao e atomico                                                     |
| Inventory multi-contexto          | Validado               | Main, personal stash, org stash, trunk, glovebox e world drop existem                          |
| Vehicles base                     | Validado com ressalvas | Ownership, acesso, estado e flow base existem; camada visual e externa                         |
| Logs estruturados                 | Validado com ressalvas | Existe padrao util, mas ainda pode ser refinado                                                |
| Surface client minima             | Parcial                | Spawn base, cache client e exports simples existem; helpers de vehicles/inventory estao vazios |
| Bridge QB                         | Parcial                | Existe contrato inicial, mas nao e bridge fechada nem validada como compatibilidade total      |
| Bridge ESX / vRP                  | Placeholder            | Arquivos existem, contrato real nao                                                            |
| Comandos de debug e prova         | Temporario             | Utilitarios de validacao fazem parte do repositorio, nao do contrato do produto                |

## Modulos existentes

- `server/prepare.lua`: schema bootstrap e migracoes defensivas
- `server/bootstrap.lua`: seed final e readiness do core
- `server/player`: identidade, metadata, charinfo, sessao, posicao, exports e lifecycle
- `server/orgs`: orgs, grades, permissoes, memberships e overrides
- `server/accounts`: dinheiro do player, org accounts e payroll
- `server/inventory`: persistencia e regra multi-contexto
- `server/vehicles`: ownership, acesso, estado, metadata e flow base
- `server/logs`: log estruturado por dominio
- `server/bridges`: adapters de compatibilidade
- `client/main.lua`, `client/spawn.lua`, `client/player.lua`, `client/orgs.lua`: camada client minima do core
- `shared/utils.lua`, `shared/items.lua`, `shared/constants.lua`, `shared/version.lua`: utilitarios e definicoes compartilhadas

## Dependencias

- `oxmysql`
- `ox_lib`
- `spawnmanager` para o spawn base atual

## Ordem minima de start

```cfg
ensure spawnmanager
ensure oxmysql
ensure ox_lib
ensure mz_core
```

## O que a v1.0 cobre

- prepare, bootstrap, seed padrao e readiness do core
- bootstrap de player por `license`, `citizenid`, metadata, charinfo e conta inicial
- persistencia de sessao em `mz_player_sessions`
- ciclo base de `load`, `unload`, `playerDropped` e save de posicao
- orgs, grades, permissoes, memberships, duty, primary, promote e demote
- dinheiro do player, org accounts e payroll com bloqueio de inconsistencias de shared account
- inventory multi-contexto com regras de stack, metadata, peso e uso de item
- vehicles base com ownership, acesso, garage, state, impound e release
- logs estruturados por dominio
- exports, callbacks e eventos suficientes para consumir o core nativo

## O que a v1.0 nao promete

- compatibilidade total com `qb-core`
- qualquer compatibilidade real com ESX ou vRP
- multichar ou character selector
- HUD, phone, NUI, target ou camada visual de gameplay
- garagem visual ou flow de spawn/store final de veiculo fora do escopo base
- handlers completos para todos os itens do inventario
- suite automatizada de testes ou pipeline de CI

## Limites conhecidos no estado atual

- `server/bridges/qb.lua` ainda nao pode ser tratado como bridge totalmente fechada. O wrapper atual ainda tem limitacao real de call style.
- `server/bridges/esx.lua` e `server/bridges/vrp.lua` continuam placeholders.
- `server/accounts/payroll.lua` ainda nao faz debito da org e credito do player de forma atomica.
- `server/inventory/events.lua` continua reservado para evolucao futura e nao representa uma surface publica fechada.
- `client/vehicles.lua` e `client/inventory.lua` continuam placeholders.
- Os comandos administrativos e probes do repositorio existem para validacao e operacao tecnica. Eles nao definem o contrato oficial do produto.

## Status atual do core

O `mz_core` esta pronto para ser tratado como base v1.0 do proprio core, desde que a leitura de v1.0 seja a correta:

- v1.0 do coracao server-side do projeto
- nao v1.0 do ecossistema completo
- nao v1.0 de bridges externas
- nao v1.0 de UI/gameplay final

Em outras palavras, o que esta estabilizado e a base nativa do recurso. O que continua parcial ou fora de escopo precisa continuar explicitado como tal.

## Proximos passos apos a v1.0

- hardening da bridge QB
- definicao real do que sera suportado ou nao em bridges externas
- melhoria de atomicidade em economy, principalmente payroll
- refinamento final de padrao de logs
- testes automatizados e CI
- docs de consumo para resources externas

## Documentacao relacionada

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/V1_SCOPE.md](docs/V1_SCOPE.md)
- [docs/checklist.md](docs/checklist.md)
