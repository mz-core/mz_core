---
title: mz_core — Repository README
status: REFERENCE
authority: LEVEL_4_REFERENCE
owner: mz_core
last_reviewed: 2026-10-08
applies_to: [mz_core, contributors]
related_contracts: [MZ-CORE-BOUNDARY-v1, MZ-DOCS-v1]
---

# `mz_core`

Fundação da MZ Framework para bootstrap/readiness, identity, session, player lifecycle, estado fundamental necessário ao spawn, autorização global e audit essencial.

Organization, Inventory, Vehicles e Economy já foram extraídos para seus owners canônicos. O core não contém implementação, schema, repository, facade ou writer financeiro. `mz_accounts` continua sendo Identity Account; saldos de Character vivem exclusivamente em `mz_economy`.

## Dependências e start

O manifest declara:

- `oxmysql`;
- `ox_lib`;
- `spawnmanager`.

O fluxo de spawn também usa `spawnmanager`. Garanta essas dependências antes do core:

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
- [Referências detalhadas do core](../mz_docs/core/reference/README.md)
- [Player lifecycle](../mz_docs/core/PLAYER_LIFECYCLE.md)
- [Account, character and session](../mz_docs/core/ACCOUNT_CHARACTER_SESSION.md)
- [Core architectural freeze](../mz_docs/core/CORE_ARCHITECTURAL_FREEZE.md)
- [Identity API](../mz_docs/api/IDENTITY_API.md)
- [Autorização global](../mz_docs/core/AUTHORIZATION.md)
- [Guia de integração](../mz_docs/guides/CORE_INTEGRATION.md)
- [API documentation](../mz_docs/api/README.md)

## Desenvolvimento e testes

- Não altere public API, ownership ou persistence sem revisar rules/ADRs e consumers.
- Harnesses do resource ficam em [`mz_testkit/tests/mz_core`](../mz_testkit/tests/mz_core/) e são executados pelo runner central preservando o working directory do resource.
- Harness offline, análise estática e runtime FiveM/OneSync/MySQL são classes distintas de evidência.
- Nenhum probe/debug helper define autorização ou contrato de produto.

Versão declarada pelo manifest: `1.0.0`.
