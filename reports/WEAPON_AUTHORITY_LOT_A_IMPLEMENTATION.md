# Lote A - contrato server-only de arma equipada

## Resultado

O `mz_core` agora publica dois exports somente no runtime do servidor. Ambos leem o estado autoritativo que ja existia em memoria no inventario; nao consultam SQL, nao alteram slot, municao, durabilidade ou nonce e retornam uma copia sanitizada.

```lua
local state, reason = exports['mz_core']:GetEquippedWeaponState(source)
local allowed, authReason, sameState = exports['mz_core']:IsWeaponAuthorized(source, weaponHash)
```

## Respostas estaveis

- `invalid_source`: source ausente ou invalido.
- `player_not_loaded`: sessao ainda nao carregada ou ja encerrada.
- `weapon_not_equipped`: sessao carregada sem arma oficial equipada.
- `weapon_authorized`: o hash normalizado coincide com o estado oficial.
- `weapon_hash_mismatch`: existe arma oficial, mas o hash informado diverge.
- `invalid_weapon_hash`: hash ausente, fora de faixa ou nao numerico.

Hashes assinados do runtime sao normalizados para `uint32`. Um estado valido pode conter apenas escalares: `source`, `citizenid`, `itemName`, `weaponName`, `weaponHash`, `slot`, `instanceUid`, `serial`, `ammo`, `ammoRevision`, `durability`, `equippedAt` e `lastTransitionAt`. Nonces internos e referencias mutaveis nunca saem pelo export.

## Semantica de transicao

`lastTransitionAt` usa o relogio monotono do servidor (`GetGameTimer`) e e atualizado no equip e no desequip oficiais. Ele permite ao observador distinguir uma divergencia persistente de uma pequena janela de troca. No `playerDropped`, o estado equipado e limpo e o mapa de transicao da source e removido; uma source reconectada nao herda autoridade anterior.

## Verificacao

Execute a partir de `mz_core`:

```powershell
lua tests/weapon_authority_contract_harness.lua
```

O harness cobre sessao inexistente, nao carregada, sem arma, equip, hash correto/incorreto, copia imutavel, leituras repetidas sem efeito colateral, remocao e reconexao.
