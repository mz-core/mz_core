# mz_core Checklist Atual

Esta checklist foi revisada contra o codigo real do repositorio. Ela nao e historico de promessas. Ela e uma fotografia tecnica do que existe hoje.

## Legenda

- `VALIDADO`: existe no codigo e ja sustenta o escopo atual do core
- `PARCIAL`: existe, mas ainda tem limite conhecido, escopo incompleto ou depende de validacao adicional
- `PENDENTE`: ainda nao existe de forma real no projeto
- `CRITICO PARA V1.0`: ponto que precisa continuar explicitado para que a v1.0 seja honesta

## VALIDADO

### Base, bootstrap e persistencia

- `server/prepare.lua` cria schema base e migracoes defensivas
- `server/bootstrap.lua` espera `prepareDone`, roda seed e marca `ready`
- `server/seed/default_orgs.lua` existe e sustenta seed padrao de orgs
- `MZCoreState` controla `prepareDone`, `prepareOk`, `seedDone`, `seedOk` e `ready`

### Player, identidade e sessao

- load de player por `license`
- geracao de `citizenid`
- criacao de conta inicial em `mz_player_accounts`
- cache por `source` e `citizenid`
- persistencia de sessao em `mz_player_sessions`
- guard de reentrada em `loadPlayer`
- fechamento de sessoes ativas antigas antes de nova sessao
- cleanup no `onResourceStop`
- save e load de ultima posicao
- exports `GetPlayer`, `GetPlayerByCitizenId`, `GetSourceByCitizenId`, `GetPlayerSession`, `IsPlayerLoaded`

### Orgs e permissoes

- orgs, tipos, grades e permissoes persistidos em banco
- heranca entre grades
- memberships com `primary`, `duty`, `promote`, `demote` e `remove`
- overrides de permissao por player
- reload de orgs do player online
- exports e comandos administrativos de orgs

### Accounts e economy base

- `GetMoney`, `SetMoney`, `AddMoney`, `RemoveMoney`
- `mz_org_accounts` e service dedicado
- payroll manual e tick automatico existem
- payroll nao faz mais mint silencioso quando faltar shared account valida
- inconsistencias de payroll entram como `skipped` e log estruturado

### Inventory

- persistencia por slot em `mz_inventory_items`
- contextos `main`, `personal stash`, `org stash`, `trunk`, `glovebox`, `world drop`
- peso por contexto
- add, remove, move, split, swap e merge
- metadata por slot com `merge` e `replace`
- add de item unico com pre-checagem de slots livres
- stack metadata-aware alinhado entre lookup, add, auto-stack de move parcial e merge explicito
- use item com handlers registrados
- handlers base reais para `water` e `radio`
- comandos administrativos para inventory e contextos

### Vehicles

- ownership de player e org
- validacao de acesso
- registro, busca, listagem e mutacoes de veiculo
- `garage`, `state`, `metadata`, `props`, `fuel`, `engine`, `body`
- flow base `takeOut`, `store`, `impound`, `release`
- integracao suficiente para trunk e glovebox
- exports, eventos e comandos administrativos

### Logs

- `mz_logs` existe
- `MZLogService.create` e `createDetailed` existem
- logs reais em player, orgs, accounts, payroll, inventory e vehicles

### Surface client minima

- cache client de `PlayerData` e `PlayerSession`
- spawn base via `spawnmanager`
- exports client de player e orgs

## PARCIAL

### Player e lifecycle

- reconnect e restart ampliados ainda dependem de validacao mais longa
- `onResourceStart` ainda nao faz rehydrate explicito de players online
- modelo de character continua basico, sem fluxo real de criacao/selecionador

### Accounts e payroll

- payroll continua nao atomico entre debito de org account e credito no player
- logs de economy estao bons, mas ainda nao totalmente uniformizados

### Inventory

- comparacao de metadata usa `json.encode` sem canonicalizacao
- `server/inventory/events.lua` continua placeholder
- handlers de `cellphone`, `id_card`, `weapon_*` e outros itens ainda nao existem como comportamento real
- o comando `minv_give_meta` existe apenas para validacao tecnica temporaria

### Vehicles

- surface client de vehicles ainda nao existe
- flow visual de garagem e spawn/store final esta fora do recurso
- modulo esta forte como base persistente, mas depende de consumer externo para UX final

### Logs

- o padrao de payload esta bom, mas ainda nao totalmente padronizado em todos os casos

### Bridges e compatibilidade

- bridge QB existe, mas continua parcial
- wrapper de player da bridge QB ainda tem limitacao real de call style
- o contrato atual da bridge QB nao deve ser tratado como compatibilidade total com `qb-core`

### Seed e docs operacionais

- seed padrao nao faz reconciliacao inteligente completa de orgs ja existentes
- repositorio ainda depende de validacao manual; nao ha testes automatizados

## PENDENTE

- bridge ESX real
- bridge vRP real
- multichar
- UI ou NUI oficial do core
- garagem visual
- target ou interacao visual de inventory/world drop
- suite automatizada de testes
- CI

## CRITICO PARA V1.0

- `v1.0` precisa significar base do core server-side, nao framework completo
- bridge QB deve continuar documentada como parcial
- ESX e vRP devem continuar documentados como placeholders
- payroll nao atomico deve continuar explicitado como divida tecnica aceita
- `client/vehicles.lua` e `client/inventory.lua` devem continuar marcados como placeholders
- comandos de debug, probes e utilitarios administrativos nao devem ser tratados como contrato oficial do produto
