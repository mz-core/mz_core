<p align="center">
  <img src="./assets/logo.svg" alt="mz_core logo" width="260">
</p>

<p align="center">
  Framework própria para FiveM, modular e focada em núcleo limpo.
</p>

Base modular de framework FiveM com foco em:

- player/session
- orgs (job/gang/staff/vip/business)
- permissões por grade com herança
- accounts
- vehicles ownership
- inventory persistence
- logs operacionais estruturados por domínio
- prepare automático de banco

## Dependências

- oxmysql
- ox_lib

## Requisito operacional atual de spawn

- `spawnmanager` precisa estar ativo antes do `mz_core`
- o spawn base atual usa `exports.spawnmanager:setAutoSpawn(false)` e `exports.spawnmanager:spawnPlayer(...)`
- se o servidor substituir ou desabilitar o `spawnmanager`, o fluxo atual de spawn do core deixa de valer ate existir outro adapter de spawn

## Ordem minima de start

```cfg
ensure spawnmanager
ensure oxmysql
ensure ox_lib
ensure mz_core
```

## O que esta versão já entrega

- bootstrap de tabelas e seed de `mz_org_types`
- cadastro automático de player por `license`
- criação de `citizenid`
- contas iniciais do player
- CRUD base de orgs e grades
- permissões de org e de grade
- memberships com promote/demote/duty/primary
- player overrides de permissão
- ownership básico de veículos
- flow de vehicles com `takeOut/store/impound/release` e metadata operacional mínima
- inventário multi-contexto (`main`, `personal stash`, `org stash`, `trunk`, `glovebox`, `world drop`)
- logs mais ricos em `accounts`, `vehicles` e bloco principal de `inventory`

## Estrutura

- `server/player` identidade, metadata, charinfo e sessão
- `server/orgs` orgs, grades, permissões e memberships
- `server/accounts` dinheiro do player
- `server/vehicles` posse, acesso e flow base de veículos
- `server/inventory` persistência multi-contexto de inventário
- `server/prepare.lua` schema bootstrap

## Observação

Essa versão é um esqueleto forte para evoluir. Já entrega payroll automático configurável, inventário multi-contexto e flow base de vehicles, mas ainda não implementa UI, multichar, spawn/store visual completo de garagem, compatibilidade total com scripts externos ou bridges validadas ponta a ponta.


No estado atual, o spawn base tambem assume a presenca operacional do `spawnmanager`.

## Estado atual adicional

- `player` agora mantém estado mínimo de sessão em cache (`loaded`, `loadedAt`, `lastSeenAt`)
- `mz_player_sessions` registra entrada/saída, motivo de drop e duração da sessão
- exports novos: `GetPlayerSession(source)` e `IsPlayerLoaded(source)`

## Bridge QB inicial

- `exports['mz_core']:GetCoreObject()` agora retorna uma camada inicial em estilo QB
- escopo atual: `GetPlayer`, `GetPlayerData`, `GetPlayerByCitizenId`, `GetPlayers`, `GetQBPlayers`, `GetIdentifier`, `GetSource`, `GetItems`
- wrapper de player com `PlayerData` e `Functions` para `AddMoney`, `RemoveMoney`, `SetMoney`, `GetMoney`, `AddItem`, `RemoveItem`, `HasItem`, `SetMetaData`, `GetMetaData`, `SetPlayerData`, `UpdatePlayerData`
- isso ainda não substitui `qb-core` real, mas já define um contrato de compatibilidade inicial para resources externos
