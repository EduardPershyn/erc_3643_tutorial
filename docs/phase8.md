# Phase 8 — Wallet Recovery

## Deliverable

`src/phase8/RecoverableToken.sol` — the Phase 7 token plus
`recoverWallet(oldWallet, newWallet)`. 7 passing tests in
`test/phase8/Recovery.t.sol`.

## Why this matters (the institutional argument)

On a plain ERC-20, `wallet = owner`. Lose the private key and the assets are
gone forever. No bank, fund, or registrar can operate on those terms — they
must be able to reissue a holder's position to a new key after a loss, exactly
like replacing a lost share certificate.

ERC-3643 makes this possible because the **ONCHAINID owns the position**, not
the wallet:

```
Old Wallet ─┐
            ├─► ONCHAINID  (holds the KYC claims + the value's "true" owner)
New Wallet ─┘
```

Recovery just re-points the identity at a new wallet and moves the tokens.

## The flow

```
recoverWallet(oldWallet, newWallet)   [token agent]
   → require balanceOf(oldWallet) > 0
   → id = identityRegistry.identity(oldWallet)
   → require newWallet is a MANAGEMENT key on id     ← the crucial proof
   → registry.registerIdentity(newWallet, id, country)   (new wallet ↔ same id)
   → forcedTransfer(oldWallet, newWallet, balance)        (moves frozen too)
   → re-apply partial-freeze / wallet-freeze to newWallet
   → registry.deleteIdentity(oldWallet)                   (retire lost wallet)
```

## The one check that makes it safe

```solidity
require(id.keyHasPurpose(keccak256(abi.encode(newWallet)), MANAGEMENT_KEY),
        "Recovery: new wallet is not a management key on the identity");
```

Recovery is not "an agent can move anyone's tokens anywhere." The new wallet
must **already be a MANAGEMENT key on the investor's ONCHAINID** — which only an
existing manager of that identity could have added. That is the cryptographic
proof that the new wallet belongs to the **same person**. Without it, recovery
reverts (`test_recover_requiresNewWalletIsManagementKey`).

In practice the investor adds the new wallet to their identity *before* (or as
part of) reporting the loss, using another management key or with help from
their identity issuer.

## Built entirely from Phase 7 primitives

`RecoverableToken` extends `Token` and adds **no** new low-level powers. It
reuses:

- `forcedTransfer` — to move tokens past freeze/compliance, including frozen ones
- `keyHasPurpose` — the ERC-734 proof of ownership
- `freezePartialTokens` / `setAddressFrozen` — to preserve enforcement state

That's the lesson: recovery is a *composition* of existing security-token
features, not a special backdoor. (Production T-REX puts this method directly in
`Token`; here it's a subclass to keep Phase 7 untouched.)

## Preserved through recovery

| Property | Result |
| --- | --- |
| Full balance | moved to new wallet (`test_recover_movesPositionToNewWallet`) |
| Partial freeze amount | re-applied to new wallet (`...preservesPartialFreeze`) |
| Whole-wallet freeze (e.g. sanctioned) | re-applied — you can't shed a freeze by "recovering" (`...preservesWalletFreeze`) |
| Verification | new wallet is instantly verified — same identity, same claims |
| Old wallet | removed from registry; can no longer receive (`...oldWalletCannotReceive`) |

## Prerequisites (setup)

- The token must be an **agent on the identity registry** (to re-register /
  delete): `registry.addAgent(address(token))`.
- The caller must be a **token agent**.

## Run it

```bash
~/.foundry/bin/forge test --match-path "test/phase8/*" -vv
```
