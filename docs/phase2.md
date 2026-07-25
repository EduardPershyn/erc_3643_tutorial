# Phase 2 — Identity Standards (ERC-734 / ERC-735 / ONCHAINID)

## Deliverable

A simplified ONCHAINID, `src/phase2/Identity.sol`, implementing:

- `addKey()` / `removeKey()` — ERC-734 key management
- `addClaim()` / `removeClaim()` — ERC-735 claims

with 16 passing tests in `test/phase2/Identity.t.sol`.

## The mental model

```
        Person
   ┌──────┼───────┐
Wallet A  Wallet B  Wallet C     (many keys)
   └──────┼───────┘
      ONCHAINID (one Identity contract)
   ├─ keys   (ERC-734): who may control this identity
   └─ claims (ERC-735): what has been attested about it
```

An identity is **not** an address — it is a contract. Wallets are registered
as *keys* on it, so a person can rotate or add wallets without losing their
identity (this is what makes Phase 8 wallet recovery possible).

## ERC-734 — keys

A key is `keccak256(abi.encode(walletAddress))` mapped to one or more
**purposes**:

| Purpose | Name | Can do |
| --- | --- | --- |
| 1 | MANAGEMENT | add/remove keys and claims (admin) |
| 2 | ACTION | act on behalf of the identity |
| 3 | CLAIM | attach claims to this identity |
| 4 | ENCRYPTION | hold an encryption key (data only) |

Key design rule copied from ONCHAINID: **a MANAGEMENT key implicitly
satisfies `keyHasPurpose` for every purpose**, so the manager can also add
claims without a separate CLAIM key. Dedicated ACTION/CLAIM keys let you
delegate narrowly.

Safety addition over the base standard: `removeKey` refuses to remove the
**last** MANAGEMENT key, so an identity can never be bricked.

## ERC-735 — claims

A claim is a signed attestation *about* the identity:

```solidity
Claim { uint256 topic; uint256 scheme; address issuer; bytes signature; bytes data; string uri; }
```

- Stored under `claimId = keccak256(abi.encode(issuer, topic))`, so one issuer
  holds at most one claim per topic (re-adding updates in place → `ClaimChanged`).
- The **signature is produced off-chain by the issuer** over the identity +
  topic + data. This contract only *stores* claims.
- Example topics: `1 KYC`, `2 AML`, `3 Country`, `4 Accredited`.

**Not verified here on purpose.** Whether a stored claim is actually valid
(issuer is trusted, signature checks out) is Phase 3 (claim verification) and
Phase 4 (trusted issuers). Phase 2 is only the identity container.

## How this replaces Phase 1

| Phase 1 (crude) | Phase 2 (real) |
| --- | --- |
| `RestrictedToken._verified[wallet]` bool | an `Identity` contract per investor, holding a KYC **claim** |
| issuer = the token's `agent` | claim `issuer` = an external KYC provider (trusted in Phase 4) |
| wallet == the holder | wallet is just one **key** on the identity |

## Simplifications vs. production ONCHAINID

- No proxy / upgradeability (production uses a factory + proxies).
- No ERC-734 `execute()` / `approve()` transaction-execution model.
- Claim signatures stored but not validated (Phase 3).

## Run it

```bash
~/.foundry/bin/forge test --match-path "test/phase2/*" -vv
```
