# Contrato de compras com conta coletiva

Data: 2026-07-31.

## Objetivo

`SpendOrgAccount` e `RefundOrgAccount` representam despesa real e compensação
recuperável. Eles não reutilizam `RemoveOrgAccountBalance`, que continua sendo
um ajuste administrativo.

## Exports server-side

```lua
local ok, receiptOrError = exports['mz_core']:SpendOrgAccount(
  source,
  'mafia',
  750000,
  {
    operationKey = 'facility_purchase:purchase000001',
    purpose = 'facility_purchase',
    relatedRef = 'facility_purchase:purchase000001',
    reason = 'facility purchase'
  }
)

local refunded, refundOrError = exports['mz_core']:RefundOrgAccount(
  source,
  'mafia',
  receiptOrError.receiptId,
  {
    operationKey = 'facility_refund:purchase000001',
    reason = 'facility persistence failed'
  }
)
```

`GetOrgAccountCommerceCapabilities()` informa versão e garantias suportadas.

## Garantias

- o chamador é obtido de `GetInvokingResource`;
- `facility_purchase` aceita apenas `mz_org_activities`;
- o ator precisa de `facility.purchase` ou owner global;
- a mesma chave e os mesmos dados retornam replay sem alterar o saldo;
- reutilizar a chave com dados diferentes retorna `idempotency_conflict`;
- um recibo de débito admite no máximo um reembolso;
- saldo, estado do recibo, extrato e outbox são confirmados na mesma transação;
- falha por saldo insuficiente consome a chave como rejeitada;
- reembolso deriva organização, ator e valor do recibo original.

## Persistência

`mz_org_account_operations` é o ledger canônico das operações. A chave é única
por resource chamador; `receipt_id` e `reversal_of_operation_id` também possuem
unicidade. `mz_org_account_transactions.operation_id` liga o extrato ao recibo.

O bootstrap aditivo roda durante o prepare do `mz_core`. Reiniciar o resource é
necessário antes de qualquer teste do contrato.

## Rollout

O contrato não ativa instalações. `mz_org_activities` continua com flags falsas
e perfis reais desabilitados. O runner de staging usa débito de no máximo
R$ 1.000, reembolsa imediatamente e exige saldo final idêntico ao inicial.
