---
title: mz_core — Repository README
status: REFERENCE
authority: LEVEL_4_REFERENCE
owner: mz_core
last_reviewed: 2026-08-09
applies_to: [mz_core, contributors]
related_contracts: [MZ-CORE-BOUNDARY-v1, MZ-DOCS-v1]
---

# `mz_core`

Fundação da MZ Framework para bootstrap/readiness, identity, session, player lifecycle, estado fundamental necessário ao spawn, autorização global e audit essencial.

O repository ainda contém código CURRENT de org, economy, inventory, vehicles, bridges e tooling que pertence a outros boundaries TARGET. Essa localização transitória não transfere ownership e somente será alterada em waves próprias.

## Dependências e start

O manifest declara:

- `oxmysql`;
- `ox_lib`.

O fluxo CURRENT de spawn também usa `spawnmanager`. Garanta essas dependências antes do core:

```cfg
ensure oxmysql
ensure ox_lib
ensure spawnmanager
ensure mz_core
```

Cada owner/produto adicional deve declarar e respeitar suas próprias dependências. Não use o core como agregador de readiness de features.

## Documentação oficial

- [Portal da MZ Framework](../mz_docs/README.md)
- [Documentação do core](../mz_docs/core/README.md)
- [Player lifecycle](../mz_docs/core/PLAYER_LIFECYCLE.md)
- [Autorização global](../mz_docs/core/AUTHORIZATION.md)
- [Guia de integração](../mz_docs/guides/CORE_INTEGRATION.md)
- [API documentation](../mz_docs/api/README.md)

Os arquivos em `docs/` e `reports/` incluem contratos anteriores, planos, auditorias, worklogs e resultados datados. Eles permanecem preservados para classificação/revisão na Wave 1A, mas não constituem automaticamente a documentação oficial vigente.

## Desenvolvimento e testes

- Não altere public API, ownership ou persistence sem revisar rules/ADRs e consumers.
- Harnesses locais permanecem em `tests/` até a Wave 1B e podem ser executados individualmente com Lua 5.4.
- Harness offline, análise estática e runtime FiveM/OneSync/MySQL são classes distintas de evidência.
- Nenhum probe/debug helper define autorização ou contrato de produto.

Versão declarada pelo manifest: `1.0.0`.
