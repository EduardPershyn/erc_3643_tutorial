# Phase 7 — ERC-3643 Token

## Deliverable

A minimal ERC-3643 token, `src/phase7/Token.sol`, that assembles the whole
system, with a 15-test full-stack integration suite in `test/phase7/Token.t.sol`.

```
                    ERC-3643 Token  (ERC-20 + AgentRole + Pausable)
                          │
        ┌─────────────────┼──────────────────┐
 IdentityRegistry   ModularCompliance   agent controls
 (Phase 5)          (Phase 6)           (freeze/forced/mint/burn/pause)
   │
 TrustedIssuers + ClaimTopics (Phase 4) ── ClaimIssuer (Phase 3) ── ONCHAINID (Phase 2)
```

## The transfer flow (the whole point)

`transfer` / `transferFrom` are overridden to run the plan's pipeline before
moving any value:

```
transfer(to, amount)
   → whenNotPaused
   → sender & recipient wallets not frozen
   → amount ≤ balance − frozenTokens        (partial-freeze check)
   → identityRegistry.isVerified(to)         ← identity + claim checks (Phases 2–5)
   → compliance.canTransfer(from, to, amount)← compliance checks       (Phase 6)
   → _transfer(from, to, amount)             ← execute
   → compliance.transferred(from, to, amount)← update module state
```

If any gate fails the transfer reverts and nothing moves. This is the line that
separates a security token from an ERC-20.

## Two classes of operation

| | User path | Agent path |
| --- | --- | --- |
| Functions | `transfer`, `transferFrom` | `mint`, `burn`, `forcedTransfer`, freeze, `pause` |
| Gated by | all four gates above | `onlyAgent` + targeted rules |
| Purpose | normal trading | issuance & legal control |

- **`mint`** — `onlyAgent`, requires `isVerified(to)`, then `compliance.created`.
  Deliberately *not* gated by `canTransfer`, so the issuer can distribute during
  a lock-up (see `TransferLockModule`).
- **`forcedTransfer`** — moves tokens *bypassing* pause / wallet-freeze /
  compliance (court orders, recovery), and can pull from **frozen** balance.
  Still requires a verified recipient. This is also the primitive Phase 8 builds
  wallet recovery on.
- **`burn`** — eats into frozen tokens if the free balance is insufficient.
- **freeze** — whole-wallet (`setAddressFrozen`) or partial
  (`freeze/unfreezePartialTokens`). Free balance = `balance − frozenTokens`.
- **`pause`** — halts all user transfers; agent paths still work.

## Roles

- **owner** — governance: `setIdentityRegistry`, `setCompliance`, appoint agents.
- **agent** — operations: mint/burn/freeze/forcedTransfer/pause (reuses
  `common/AgentRole` from Phase 5).

## How the pieces connect at construction

```solidity
token = new Token("Acme Share", "ACME", 0, identityRegistry, compliance);
compliance.bindToken(address(token)); // so only the token may call the hooks
token.addAgent(agent);
```

`decimals = 0` models a share (indivisible units) — ERC-3643 tokens routinely
use custom decimals.

## Highlight test: revoke KYC → transfer fails

`test_revokingKyc_blocksFurtherTransfersToHolder` walks the Phase 10 headline:
Alice transfers to Bob successfully; the KYC provider then revokes Bob's claim
(`ClaimIssuer.revokeClaimBySignature`); `isVerified(bob)` flips to false; the
next transfer to Bob reverts. No token state was touched — the revocation
propagated all the way from an off-chain signature to a blocked on-chain
transfer, through every layer built in Phases 2–6.

## Simplifications vs. production T-REX

- Not upgradeable (T-REX uses proxies); no `onchainID`/version metadata setters.
- No batch operations, no `recoveryAddress` yet (Phase 8).
- Compliance modules are single-instance (see Phase 6 notes).

## Run it

```bash
~/.foundry/bin/forge test --match-path "test/phase7/*" -vv
```
