# Phase 4 — Trusted Issuers

## Deliverable

Two registry contracts plus the required `isTrustedIssuer`:

- `src/phase4/ClaimTopicsRegistry.sol` — the topics required to hold the token.
- `src/phase4/TrustedIssuersRegistry.sol` — the per-topic allow-list of issuers,
  including `isTrustedIssuer(address) returns (bool)`.

16 passing tests in `test/phase4/Registries.t.sol`.

## The gap Phase 4 closes

Phase 3 proved a claim's signature is *genuine*. But genuine is not enough:

```
Random MetaMask wallet  --signs a "KYC passed" claim-->  signature is genuine
                                                          ...but who cares?
```

Anyone can spin up a `ClaimIssuer` and sign "KYC passed". The token must only
accept claims from issuers **it** trusts. That's this registry.

| | Trusted | Not trusted |
| --- | --- | --- |
| Example | Deloitte, Chainalysis | a random MetaMask wallet |
| `isTrustedIssuer` | `true` | `false` |

## Two registries, two questions

```
ClaimTopicsRegistry     →  WHICH claims are required?      e.g. {KYC, Country}
TrustedIssuersRegistry  →  WHO may attest each of them?    KYC → {Deloitte},
                                                           AML → {Chainalysis}
```

Trust is **scoped per topic**: registering Deloitte for `{KYC, Country}` does
*not* make it a trusted AML issuer (`hasClaimTopic(deloitte, AML) == false`).
This mirrors reality — an auditor you trust for identity is not automatically
one you trust for sanctions screening.

## Key views (used by the token in Phase 7)

| Function | Answers |
| --- | --- |
| `isTrustedIssuer(addr)` | Is this issuer trusted for anything? |
| `hasClaimTopic(issuer, topic)` | Is this issuer trusted for *this* topic? |
| `getTrustedIssuersForClaimTopic(topic)` | Which issuers can attest this topic? |
| `getClaimTopics()` | Which topics must a holder satisfy? |

`getTrustedIssuersForClaimTopic` is a maintained reverse index (topic → issuers)
so the token can, per required topic, iterate only the relevant issuers instead
of scanning every issuer.

## Design notes

- **`Ownable`** — the token issuer owns both registries; all mutations are
  `onlyOwner`. (OZ v5 reverts with `OwnableUnauthorizedAccount`.)
- **Bounded loops** — `MAX_CLAIM_TOPICS` / `MAX_TOPICS_PER_ISSUER` (15, as in
  T-REX) keep the per-transfer verification loop from growing unbounded.
- **Index consistency** — `remove`/`update` unwind the `topic → issuers`
  reverse index before rewriting it, so the two mappings never drift
  (`test_updateIssuerClaimTopics_rewiresPerTopicLookup`,
  `test_removeTrustedIssuer_clearsEverything`).
- **`removeTrustedIssuer` via `_issuerTopics[...].length`** — presence is
  tracked by whether an issuer has any topics, avoiding a separate bool map.

## Where this plugs in next

- **Phase 5** maps wallets → identities (Identity Registry).
- **Phase 7** verification per required topic becomes:
  ```
  for each topic in ClaimTopicsRegistry.getClaimTopics():
      for each issuer in TrustedIssuersRegistry.getTrustedIssuersForClaimTopic(topic):
          claim = identity.getClaim(keccak256(issuer, topic))
          if claim exists && issuer.isClaimValid(identity, topic, sig, data): OK, next topic
  ```

## Run it

```bash
~/.foundry/bin/forge test --match-path "test/phase4/*" -vv
```
