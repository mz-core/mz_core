---
title: mz_core — Repository README
status: REFERENCE
authority: LEVEL_4_REFERENCE
owner: mz_core
last_reviewed: 2026-10-08
applies_to: [mz_core, contributors]
related_contracts: [MZ-CORE-BOUNDARY-v1, MZ-DOCS-v1]
---

<div align="center">
  <a href="https://github.com/mz-core">
    <img src="https://github.com/mz-core/mz_core/blob/main/assets/logo.svg" alt="MZ Core — logo centralizada" width="400" />
  </a>

  <p><strong>O núcleo do ecossistema MZ Core para servidores FiveM.</strong></p>

  <p>
    Identidade &nbsp;·&nbsp; Sessões &nbsp;·&nbsp; Ciclo de vida &nbsp;·&nbsp; Spawn &nbsp;·&nbsp; Autorização &nbsp;·&nbsp; Auditoria
  </p>

  <p>
    <code>v1.0.0</code> &nbsp;·&nbsp; <code>FiveM</code> &nbsp;·&nbsp; <code>Lua</code>
  </p>

  <p>
    <a href="#-visão-geral">Visão geral</a> &nbsp;·&nbsp;
    <a href="#-instalação">Instalação</a> &nbsp;·&nbsp;
    <a href="#-arquitetura">Arquitetura</a> &nbsp;·&nbsp;
    <a href="#-documentação">Documentação</a> &nbsp;·&nbsp;
    <a href="#-desenvolvimento-e-testes">Desenvolvimento</a>
  </p>
</div>

---

## ✦ Visão geral

O **`mz_core`** é a fundação do **MZ Core**. Ele concentra os serviços essenciais para iniciar e manter o ciclo de vida de um jogador, sem absorver funcionalidades que pertencem a outros resources.

| Responsabilidade          | O que pertence ao Core                          |
| :------------------------ | :---------------------------------------------- |
| **Bootstrap e readiness** | Inicialização e estado de prontidão essenciais  |
| **Identidade e sessão**   | Identidade, sessão e ciclo de vida do jogador   |
| **Spawn**                 | Estado fundamental necessário ao fluxo de spawn |
| **Autorização**           | Verificações globais de autorização             |
| **Auditoria**             | Registro essencial de eventos do Core           |

> **Princípio de arquitetura:** cada resource mantém a responsabilidade pelo próprio domínio. O Core não é um agregador de readiness de funcionalidades externas.

## ◈ Instalação

### Requisitos

Instale e inicie estas dependências antes do `mz_core`:

| Resource       | Finalidade                         |
| :------------- | :--------------------------------- |
| `oxmysql`      | Acesso ao banco de dados           |
| `ox_lib`       | Biblioteca utilizada pelo resource |
| `spawnmanager` | Integração com o fluxo de spawn    |

### Ordem de inicialização

Adicione ao arquivo de configuração do servidor:

```cfg
ensure oxmysql
ensure ox_lib
ensure spawnmanager
ensure mz_core
```

Coloque a pasta `mz_core` no diretório de resources do servidor e mantenha o nome da pasta. Outros resources devem declarar e respeitar suas próprias dependências.

> **Distribuição:** o ZIP de release contém os arquivos de execução do `mz_core`; as dependências acima devem ser instaladas separadamente. A homologação final requer validação em FXServer real.

## ⬡ Arquitetura

O Core é responsável pelas capacidades fundamentais. Os sistemas de produto continuam em seus owners dedicados:

| Domínio                          | Resource responsável |
| :------------------------------- | :------------------- |
| Organizações                     | `mz_org`             |
| Inventário                       | `mz_inventory`       |
| Veículos                         | `mz_vehicles`        |
| Economia e saldos de personagens | `mz_economy`         |

**Limites importantes**

- O `mz_core` não contém implementação, schema, repository, facade ou writer financeiro.
- `mz_accounts` permanece como _Identity Account_; saldos de personagens pertencem exclusivamente ao `mz_economy`.
- Mudanças em APIs públicas, ownership ou persistência exigem revisão dos contratos, das decisões de arquitetura e dos consumers.

## 📚 Documentação

A documentação detalhada é mantida no workspace `mz_docs`.

| Assunto            | Referência                                                                     |
| :----------------- | :----------------------------------------------------------------------------- |
| Visão geral        | [Portal de documentação](../mz_docs/README.md)                                 |
| Core               | [Documentação do Core](../mz_docs/core/README.md)                              |
| Referências        | [Referências detalhadas](../mz_docs/core/reference/README.md)                  |
| Jogador            | [Player lifecycle](../mz_docs/core/PLAYER_LIFECYCLE.md)                        |
| Conta e personagem | [Account, character and session](../mz_docs/core/ACCOUNT_CHARACTER_SESSION.md) |
| Arquitetura        | [Core architectural freeze](../mz_docs/core/CORE_ARCHITECTURAL_FREEZE.md)      |
| Identidade         | [Identity API](../mz_docs/api/IDENTITY_API.md)                                 |
| Autorização        | [Autorização global](../mz_docs/core/AUTHORIZATION.md)                         |
| Integrações        | [Guia de integração](../mz_docs/guides/CORE_INTEGRATION.md)                    |
| APIs               | [API documentation](../mz_docs/api/README.md)                                  |

> **Nota para repositórios separados:** os links acima seguem a estrutura do monorepo. Antes da publicação em um repositório GitHub independente, ajuste-os para os endereços publicados de `mz_docs`.

## 🧪 Desenvolvimento e testes

- Os harnesses do Core ficam em [`mz_testkit/tests/mz_core`](../mz_testkit/tests/mz_core/) e são executados pelo runner central preservando o diretório de trabalho do resource.
- Testes offline, análise estática e execução em **FiveM / OneSync / MySQL** são evidências distintas; um resultado local não substitui a homologação em jogo.
- Helpers de diagnóstico e debug não definem autorização nem contratos de produto.
- Antes de alterar uma API pública, revise os contratos e seus consumidores.

---

<div align="center">
  <p><strong>MZ.CORE</strong></p>
  <p><sub>Fundação modular para o ecossistema FiveM · Versão declarada no manifesto: <code>1.0.0</code></sub></p>
</div>
