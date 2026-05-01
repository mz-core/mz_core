# mz_core Architecture

## Objetivo da arquitetura

`mz_core` foi organizado para manter o coracao tecnico do servidor em um recurso proprio, desacoplado de frameworks externas e de camadas visuais.

O foco da arquitetura atual e:

- bootstrap e persistencia do core
- identidade e sessao de player
- orgs e permissoes
- accounts e org accounts
- inventory multi-contexto
- vehicles base persistentes
- persistencia de veiculos fora da garagem
- logs estruturados
- surface publica minima via exports, callbacks e eventos

## Principios do projeto

- Banco como fonte de verdade
- Separacao por dominio, nao por feature visual
- Services para regra de negocio
- Repositories para acesso a banco
- Exports, callbacks e eventos como surface publica
- UI e gameplay especifico fora do coracao do core
- Bridges como adaptadores, nao como centro da arquitetura

## Estrutura real de pastas

```text
mz_core/
  assets/
  client/
    main.lua
    player.lua
    spawn.lua
    orgs.lua
    vehicles.lua
    inventory.lua
  docs/
    checklist.md
    ARCHITECTURE.md
    V1_SCOPE.md
  server/
    bootstrap.lua
    cache.lua
    main.lua
    prepare.lua
    accounts/
    bridges/
    inventory/
    logs/
    orgs/
    player/
    seed/
    vehicles/
  shared/
    constants.lua
    items.lua
    utils.lua
    version.lua
  config.lua
  fxmanifest.lua
```

## Separacao entre client, server e shared

### `server/`

Concentra estado autoritativo, regras de negocio, persistencia e APIs publicas do core.

### `client/`

Mantem a camada minima de estado do player, spawn base, exports client simples e runtime client necessario para veiculos persistentes. Nao existe arquitetura visual de gameplay aqui.

### `shared/`

Mantem utilitarios, definicoes compartilhadas, item definitions e versao do recurso.

## Padrao por dominio

O padrao dominante do projeto hoje e:

- `service.lua`: regra de negocio e orchestracao do dominio
- `repository.lua`: leitura e escrita em banco
- `exports.lua`: API publica de consumo externo
- `events.lua`: surface via eventos ou callbacks quando faz sentido
- `commands.lua`: comandos administrativos e de validacao

Nem todo dominio usa todos os arquivos. Onde algum arquivo existe mas nao carrega contrato real, ele deve ser tratado como placeholder.

## Responsabilidades por dominio

### Base do core

- [server/prepare.lua](../server/prepare.lua): schema bootstrap, migracoes defensivas e seed basico de `mz_org_types`
- [server/bootstrap.lua](../server/bootstrap.lua): espera `prepare`, roda `default_orgs` e marca readiness do core
- [server/cache.lua](../server/cache.lua): cache em memoria do estado online
- [server/main.lua](../server/main.lua): callbacks centrais de player e spawn

### Player

- bootstrap por `license`
- `citizenid`
- metadata e charinfo
- sessao em `mz_player_sessions`
- posicao persistida
- lifecycle de `load`, `touch`, `unload`

### Orgs

- tipos de org
- orgs
- grades
- permissoes por org e por grade
- membership do player
- `primary`, `duty`, promote, demote e overrides

### Accounts

- dinheiro pessoal do player
- org accounts
- payroll

### Inventory

- inventario principal do player
- personal stash
- org stash
- trunk
- glovebox
- world drop
- peso
- stack, split, swap, metadata e use item

### Vehicles

- ownership de player e org
- controle de acesso
- garage e state
- props, metadata e condition
- `takeOut`, `store`, `impound`, `release`
- `mz_vehicle_world_state` como fonte de verdade para veiculos fora da garagem
- restore de veiculos `out` por placa normalizada, sem confiar em `net_id` antigo
- state bags para placa, lock, owner, condition e destroyed
- `metadata_json.condition` para preservar condicao quando um veiculo danificado/destruido e guardado

### Runtime client de vehicles

- [client/vehicles.lua](../client/vehicles.lua) aplica state bags de veiculos persistentes
- executa fallback de restore quando o server nao consegue criar entidade diretamente
- envia snapshots de veiculos persistentes com validacao server-side
- reforca veiculo destroyed como inutilizavel, sem controlar UI ou garagem visual
- proximity respawn existe como caminho experimental, mas fica desligado por padrao em release candidate

### Logs

- persistencia de eventos estruturados por dominio
- payload com `actor`, `target`, `context`, `before`, `after` e `meta`

### Bridges

- adapter para transformar a estrutura interna em contratos externos
- implementacao parcial atual para QB
- placeholders para ESX e vRP

## API publica vs implementacao interna

### API publica atual

- exports por dominio em `server/player/exports.lua`, `server/orgs/exports.lua`, `server/accounts/exports.lua`, `server/inventory/exports.lua`, `server/vehicles/exports.lua`
- callbacks centrais em `server/main.lua` e `server/orgs/events.lua`
- eventos de vehicles em `server/vehicles/events.lua`
- eventos client `mz_core:client:playerLoaded` e `mz_core:client:spawnPlayer`

### API que nao deve ser tratada como contrato oficial

- comandos administrativos em `server/*/commands.lua`
- probes e arquivos de debug como `server/bridges/qb_probe.lua` e `server/vehicles/debug.lua`
- placeholders de `events.lua` ou `client/*.lua` que nao sustentam contrato real
- comandos de restore/debug de veiculos sao operacionais e devem ficar protegidos por console, ACE/admin ou `Config.Debug`

### Implementacao interna

- `MZCache`
- services e repositories
- `MZBridgeAdapter`
- helpers locais e tabelas internas de runtime

## Fluxo base de runtime

1. `fxmanifest.lua` carrega `config.lua`, `shared/*` e os dominios server
2. `server/prepare.lua` cria schema e migracoes
3. `server/bootstrap.lua` espera `prepareDone`, roda seed padrao e marca `ready`
4. `playerJoining` chama `MZPlayerService.loadPlayer`
5. `MZOrgService.loadPlayerOrgs` hidrata orgs do player
6. o client recebe `playerLoaded`
7. `client/spawn.lua` resolve spawn via callback `getSpawnData`

## Riscos atuais e limites conhecidos

- bridge QB ainda parcial, com limitacao real no wrapper publico
- ESX e vRP ainda sao placeholders
- payroll ainda nao e atomico
- `client/vehicles.lua` e runtime real de veiculos persistentes
- `client/inventory.lua` ainda e placeholder
- `server/inventory/events.lua` ainda e placeholder
- nao existe suite automatizada de testes nem CI
- o recurso depende de `spawnmanager` para o spawn base atual

## Ordem recomendada de ensure

```cfg
ensure oxmysql
ensure ox_lib
ensure spawnmanager
ensure mapmanager
ensure sessionmanager
ensure mz_core
ensure mz_vehicles
ensure mz_garagem
ensure mz_hud
ensure mz_creator
ensure mz_clothing
```

## Diretrizes para expansao futura

- novos modulos devem seguir a separacao por dominio
- regra de negocio deve ficar em service, nao em command ou event
- acesso a banco deve ficar em repository
- surface publica deve ser deliberada e pequena
- debug e validacao runtime devem continuar separados do contrato oficial
- UI, NUI, targets e sistemas de gameplay devem consumir o core, nao morar dentro dele
- compatibilidade externa deve passar por bridges claras, nao por acoplamento do core a contratos de terceiros
