# Phase 5 — Identity Registry

## Deliverable

`src/phase5/IdentityRegistry.sol` implementing:

- `registerIdentity(wallet, identity, country)`
- `deleteIdentity(wallet)`
- `contains(wallet)`

...plus the verification method the token relies on, `isVerified(wallet)`.
14 passing tests in `test/phase5/IdentityRegistry.t.sol`.

## The mapping

```
Wallet                Identity Registry           ONCHAINID
0xAAA (Alice)   ──►   wallet → identity      ──►  Identity #1  (+ claims)
0xBBB (Bob)     ──►                          ──►  Identity #2
```

The registry is the bridge from an ordinary wallet address to its ONCHAINID.
It also stores the investor's `country` (used by some compliance rules in
Phase 6). Agents (not the owner) do the day-to-day registering — see
`src/common/AgentRole.sol`, a reusable owner→agents role that the token will
share in Phase 7.

## `isVerified` — where Phases 2–4 come together

This is the real payoff. `isVerified(wallet)` returns true only if the wallet
is registered **and**, for every required topic, its identity holds a claim
that is trusted and valid:

```
isVerified(wallet):
  id = registry[wallet]                       (Phase 5)
  if id == 0: return false
  for topic in ClaimTopicsRegistry.getClaimTopics():        (Phase 4)
      ok = false
      for claimId in id.getClaimIdsByTopic(topic):           (Phase 2)
          (_, _, issuer, sig, data, _) = id.getClaim(claimId)
          if TrustedIssuersRegistry.hasClaimTopic(issuer, topic):   (Phase 4)
              if IClaimIssuer(issuer).isClaimValid(id, topic, sig, data):  (Phase 3)
                  ok = true; break
      if not ok: return false
  return true
```

The tests prove each failure mode independently:

| Scenario | Result |
| --- | --- |
| Not registered | `false` |
| Registered, no required topics | `true` |
| Required KYC claim missing | `false` |
| Valid claim from a trusted KYC issuer | `true` |
| Same claim, but issuer not in trusted registry | `false` |
| Issuer trusted for AML, claim is KYC | `false` |
| Claim later revoked by the issuer | `false` |
| Two topics required, only one satisfied | `false` |

## Design notes

- **`try/catch` around `isClaimValid`** — a claim stored with a non-issuer
  address (e.g. an EOA) must be *ignored*, not revert the whole check. So a
  bogus claim can never brick verification of a legitimate one.
- **Per-topic AND, per-claim OR** — every required topic must be satisfied, but
  any single trusted+valid claim satisfies a topic.
- **Agent role, not owner** — mirrors ERC-3643's split of governance (owner)
  from operations (agents). `registerIdentity` is `onlyAgent`.
- **Registries are swappable** (`setTopicsRegistry` / `setIssuersRegistry`,
  `onlyOwner`) so requirements can evolve without redeploying the registry.

## This replaces Phase 1 for good

Phase 1's `RestrictedToken._verified[wallet]` bool is now fully realised:
`IdentityRegistry.isVerified(wallet)` computes that boolean from real identities,
signed claims, and a trusted-issuer allow-list — no manual flag anywhere.

## Where this plugs in next

- **Phase 6** builds the compliance engine (`canTransfer`) — rules *beyond*
  identity, like holder caps and country limits.
- **Phase 7** the token's `transfer` calls
  `identityRegistry.isVerified(to) && compliance.canTransfer(from, to, amount)`.

## Run it

```bash
~/.foundry/bin/forge test --match-path "test/phase5/*" -vv
```
