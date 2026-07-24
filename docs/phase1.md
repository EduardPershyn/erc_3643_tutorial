# Phase 1 — Security Token Fundamentals

## Deliverable: Explain ERC-3643 in two paragraphs (no Solidity)

A security token is a blockchain representation of a regulated financial
asset — a share, a bond, a fund unit, a slice of a building. Because those
assets are regulated, the people who can hold and trade them are restricted
by law: only investors who have passed identity and KYC/AML checks, who live
in permitted countries, or who qualify as accredited, may own them, and even
then only within limits like holder caps or lock-up periods. A plain ERC-20
cannot express any of this. On an ERC-20, a token is just a number attached
to an address, anyone can receive it, and the issuer loses all control the
moment it leaves their hands. For a regulated security that is a
non-starter — the issuer remains legally responsible for who ends up on the
cap table.

ERC-3643 solves this by separating *identity* from *wallet* and by checking
every transfer against a set of rules before it is allowed. Each investor is
represented by an on-chain identity (ONCHAINID) that carries verifiable
"claims" — attestations such as "KYC passed" or "resident of France" — issued
and signed by trusted parties like a KYC provider. The token itself asks, on
every transfer, two questions: *is this wallet a known, verified identity?*
and *does this specific transfer satisfy the compliance rules?* If either
answer is no, the transfer simply does not happen. Because value is bound to
the identity rather than to a single private key, an investor who loses their
wallet can have their holdings recovered to a new one — the identity persists,
the wallet is only an access mechanism. That combination — permissioned
holders, enforced-at-the-protocol compliance, and recoverable identity-owned
assets — is what makes ERC-3643 suitable for real-world regulated securities
where a plain ERC-20 is not.

## The three questions, answered in code

Phase 1 is conceptual, but the repo turns each question into a passing test
(`test/phase1/Phase1.t.sol`):

| Question | Where it's proven |
| --- | --- |
| Why can't institutions simply use ERC-20? | `test_Q1_openToken_sendsToAnyoneUnconditionally` — `OpenToken` lets Alice send to a random wallet with no check. |
| Why is `wallet = identity` a problem? | `test_Q2_*` — `OpenToken` has no recovery (lost key = lost value); `RestrictedToken.recover` moves the balance to a new wallet. |
| Why must transfers be restricted? | `test_Q3_*` — `RestrictedToken` reverts a transfer to an unverified/frozen holder, and succeeds only after verification. |

## How Phase 1 seeds the later phases

`RestrictedToken` deliberately crams into one contract what real ERC-3643
splits apart. Each crude piece is a placeholder you will replace:

| Crude in Phase 1 | Becomes | Phase |
| --- | --- | --- |
| `_verified` mapping | Identity Registry | 5 |
| the check inside `_update` | `Compliance.canTransfer` | 6 |
| `agent` address | Agent role | 7 |
| `recover()` | ONCHAINID-based recovery | 8 |
| (implicit) "who may attest KYC" | Trusted Issuers + Claim Topics registries | 3–4 |

## Run it

```bash
~/.foundry/bin/forge test -vv
```
