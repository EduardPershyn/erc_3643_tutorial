# Phase 6 — Compliance Engine

> The compliance engine is what differentiates ERC-3643 from ERC-20.

## Deliverable

A modular compliance contract plus **three** transfer-restriction modules:

- `src/phase6/ModularCompliance.sol` — aggregates modules; `canTransfer` = AND
- `src/phase6/modules/TransferLockModule.sol` — no transfers before a time
- `src/phase6/modules/CountryAllowModule.sol` — receiver must be in an allowed country
- `src/phase6/modules/MaxHolderModule.sol` — at most N holders (stateful)

10 passing tests in `test/phase6/Compliance.t.sol`.

## Identity vs. compliance — an important split

The plan lists "Must have KYC" and "Must be an EU resident" together, but in
ERC-3643 they live in **different** places:

| Question | Answered by | Phase |
| --- | --- | --- |
| Is the holder a verified identity (KYC/AML)? | `IdentityRegistry.isVerified` | 5 |
| Does this *transfer* obey the rules (caps, geography, timing)? | `Compliance.canTransfer` | 6 |

The token (Phase 7) calls **both**. Compliance is about the *transfer*, not the
*identity*. (Country sits on the line — here it's a compliance module that
*reads* the country stored in the identity registry.)

## Modular architecture

```
        ModularCompliance  (bound to one token)
        ├─ canTransfer(from,to,amt)  = AND over all modules.moduleCheck
        └─ transferred/created/destroyed  → each module's action hook
             │
   ┌─────────┼──────────────┐
TransferLock  CountryAllow   MaxHolder
(stateless)   (stateless)    (stateful: mirrors balances via hooks)
```

Two method families:

- **`moduleCheck` (view)** — the decision, aggregated by `canTransfer`. Any
  single module returning false blocks the transfer.
- **action hooks (`*Action`)** — called by the token *after* value moves, so a
  stateful module can update. `MaxHolderModule` uses them to keep a holder
  count, since a module can't read the token's balances directly.

## The three rules

| Module | Rule | Stateful? | Key detail |
| --- | --- | --- | --- |
| `TransferLockModule` | `block.timestamp >= releaseTime` | no | only gates transfers; minting still works during lock-up |
| `CountryAllowModule` | receiver's country ∈ allow-list | no | reads `identityRegistry.investorCountry(to)` |
| `MaxHolderModule` | ≤ `maxHolders` holders | **yes** | new holder at cap is blocked; freeing a balance frees a slot |

`MaxHolderModule` is the instructive one: it mirrors balances through the hooks,
increments `holderCount` when an address goes 0→positive, decrements on
positive→0. `test_maxHolders_blocksNewHolderAtCap_freesSlotOnExit` proves the
full lifecycle including a freed slot.

## Access control (two separate bindings)

- **Token → compliance**: only the `bindToken` address may call the action
  hooks (`onlyToken`). Prevents anyone spoofing "a transfer happened".
- **Compliance → module**: a module only accepts action calls from the
  compliance it was bound to (`onlyCompliance`). Prevents state corruption.
- **owner**: manages modules (`addModule`/`removeModule`) and module config.

## Simplification vs. T-REX

Real T-REX routes module config through `compliance.callModuleFunction` and
supports one module shared across many compliances (per-compliance state). Here
each module is a single-compliance instance configured directly by its owner —
clearer for study; the `moduleCheck` + hook contract is identical.

## Where this plugs in next

**Phase 7** the token's transfer path becomes:

```
transfer(to, amount):
    require(identityRegistry.isVerified(to))          // Phase 5
    require(compliance.canTransfer(from, to, amount)) // Phase 6
    _transfer(...)
    compliance.transferred(from, to, amount)          // update module state
```

## Run it

```bash
~/.foundry/bin/forge test --match-path "test/phase6/*" -vv
```
