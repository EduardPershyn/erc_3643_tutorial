# Phase 3 — Claims System

> The claims system is the heart of ERC-3643.

## Deliverable

A working proof of concept for identity claims — `src/phase3/ClaimIssuer.sol`
plus the headline test
`test_aliceReceivesValidKycClaim_fromTrustedIssuer`: Alice receives a KYC
claim from a trusted issuer and it verifies on-chain. 9 passing tests in
`test/phase3/ClaimIssuer.t.sol`.

## What Phase 2 was missing

Phase 2 could *store* a claim (`topic, issuer, signature, data`) but never
checked the signature — anyone could store anything. Phase 3 adds the missing
half: **verification**. The claim's `issuer` field now points at a
`ClaimIssuer` **contract**, and that contract can answer, on-chain, "is this
signature genuine and still valid?"

## The end-to-end flow

```
KYC provider (off-chain)                 On-chain
────────────────────────                 ────────────────────────────────
1. deploy ClaimIssuer, register
   a CLAIM signing key
2. sign(  keccak256(abi.encode(
        aliceIdentity, KYC, data)) )  ─►  3. aliceId.addClaim(KYC, 1,
   with eth_sign prefix                      issuer, signature, data, "")
                                          4. issuer.isClaimValid(
                                               aliceId, KYC, sig, data) → true
```

The signature commits to **three** things: *which identity*, *which topic*,
and *what data*. Change any of them and verification fails — which is exactly
what the negative tests prove:

| Attack | Test | Result |
| --- | --- | --- |
| Signed by a wallet not registered on the issuer | `...WhenSignedByUnregisteredWallet` | invalid |
| Tamper with the claim data | `...WhenDataTampered` | invalid |
| Reuse a KYC signature as an AML claim | `...ForWrongTopic` | invalid |
| Replay Alice's claim onto Bob's identity | `...ForWrongIdentity` | invalid |
| Malformed / garbage signature | `...ForMalformedSignature` | invalid (no revert) |

## How verification works (on-chain)

`ClaimIssuer.isClaimValid` in [src/phase3/ClaimIssuer.sol](../src/phase3/ClaimIssuer.sol):

1. Reject if the signature was revoked.
2. Rebuild `keccak256(abi.encode(identity, topic, data))` and apply the
   `\x19Ethereum Signed Message` prefix (`MessageHashUtils`).
3. `ECDSA.tryRecover` the signer — `tryRecover` (not `recover`) so a malformed
   signature returns *false* instead of reverting.
4. Require the recovered wallet to hold a **CLAIM key (purpose 3)** on the
   issuer. A MANAGEMENT key implicitly satisfies this (Phase 2 rule), so the
   admin can also sign.

## Revocation

The issuer's manager can kill a specific claim with
`revokeClaimBySignature(sig)`; `isClaimValid` then returns false forever after.
This is how a KYC provider withdraws an attestation without touching the
investor's identity contract — important for Phase 10's "revoke KYC → transfer
fails" step.

## Why the issuer is a contract, not an EOA

If the `issuer` were just an address, the token could recover a signer but
couldn't ask "is this still valid?" or "was it revoked?". Making the issuer a
contract (`IClaimIssuer`) means verification and revocation are queryable
on-chain — the token/registry just calls `isClaimValid`.

## Where this plugs in next

- **Phase 4** decides *which* ClaimIssuers are trusted for *which* topics
  (Trusted Issuers Registry + Claim Topics Registry).
- **Phase 5** maps wallets → identities (Identity Registry).
- **Phase 7** ties it together: `transfer` → look up identity → for each
  required topic, find a claim whose issuer is trusted and `isClaimValid`.

## Run it

```bash
~/.foundry/bin/forge test --match-path "test/phase3/*" -vv
```
