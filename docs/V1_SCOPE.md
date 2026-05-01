# mz_core v1.0 Scope

## O que significa v1.0 neste projeto

Neste repositorio, `v1.0` significa:

- o coracao server-side do `mz_core` esta forte o suficiente para ser a base oficial do proprio core
- os dominios centrais ja sustentam uso real e persistencia real
- a documentacao ja descreve com honestidade o que entra e o que fica fora

`v1.0` nao significa:

- framework completo de ponta a ponta
- compatibilidade total com frameworks externas
- UI final, NUI, HUD, phone ou camada visual pronta

## O que entra oficialmente na v1.0

- prepare, bootstrap, seed padrao e readiness do core
- player, identidade, metadata, charinfo, sessao e posicao
- orgs, grades, permissoes, memberships e overrides
- dinheiro do player e org accounts
- payroll no escopo atual, com bloqueio de inconsistencias de shared account
- inventory multi-contexto base
- vehicles base persistentes
- persistencia de veiculos fora da garagem com `mz_vehicle_world_state`
- logs estruturados por dominio
- exports, callbacks e eventos suficientes para consumir o core nativo
- spawn base minimo com `spawnmanager`

## O que fica fora da v1.0

- compatibilidade completa com `qb-core`
- qualquer compatibilidade real com ESX ou vRP
- multichar
- criacao visual de personagem
- garagem visual
- NUI de inventory
- target para stash, trunk, glovebox ou world drop
- HUD, phone e sistemas de gameplay
- handlers completos de todos os itens
- suite automatizada de testes e CI

## O que ainda bloqueia uma v1.0 total, se a definicao fosse mais ampla

Se `v1.0` fosse entendida como framework completa, estes pontos ainda seriam bloqueadores:

- bridge QB ainda parcial
- ESX e vRP ainda placeholders
- payroll ainda nao atomico
- client helpers de inventory e vehicles ainda placeholders
- ausencia de testes automatizados
- ausencia de camada visual oficial

## Dividas tecnicas conscientemente aceitas na v1.0

- payroll ainda opera em passos separados entre debito de org account e credito do player
- comparacao de metadata no inventory usa regra minima com `json.encode`
- lifecycle de restart ainda nao tem rehydrate explicito em `onResourceStart`
- parte da validacao do projeto ainda depende de runtime manual
- o repositorio ainda carrega comandos de debug e probes que sao uteis para manutencao, mas nao fazem parte da promessa do produto
- proximity respawn de veiculos existe, mas fica desligado por padrao ate validacao maior

## Checklist curta para rc1

- debug geral e debug de vehicle world desligados
- comandos debug protegidos por console, ACE/admin ou modo debug
- veiculo `out` reloga sem duplicar
- lock/unlock funciona apos relog
- destroyed persiste apos relog
- guardar destroyed nao repara gratis
- veiculo destroyed volta inutilizavel
- appearance/clothing persiste
- HUD/cinto funciona por classe de veiculo

## Definicao honesta da release

A release `1.0.0` so e honesta se for lida assim:

- `mz_core` v1.0 e a base do core
- a base validada e majoritariamente server-side
- o recurso entrega infraestrutura de dominio, nao framework visual completa
- tudo que continua parcial ou placeholder precisa continuar explicitado na documentacao

## Decisao de escopo

Com esse recorte, a base do `mz_core` pode ser congelada como `v1.0` sem prometer mais do que o codigo atual sustenta.
