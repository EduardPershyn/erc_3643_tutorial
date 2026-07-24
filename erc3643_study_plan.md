# ERC-3643 + ONCHAINID Study Plan

## Overview

For an experienced Solidity developer, ERC-3643 is best understood as:

> ERC-20 + ERC-734/735 Identity + Compliance Engine + Security Token
> Regulations

The goal of this study plan is to incrementally build an understanding
of every major concept, from security tokens and identity to compliance
and the complete ERC-3643 ecosystem.

------------------------------------------------------------------------

## Phase 0 --- Prerequisites (1--2 days)

### Topics

-   ERC-20
-   ERC-165
-   ERC-721 (for comparison)
-   Upgradeable contracts
-   AccessControl / Ownable
-   Proxy patterns (UUPS, Transparent)

### Goal

You should already be comfortable with \~90% of these topics.

------------------------------------------------------------------------

## Phase 1 --- Security Token Fundamentals (1 day)

### Learn

-   What is a security token?
-   Difference between utility, security, and payment tokens.
-   Real-world asset (RWA) use cases:
    -   Shares
    -   Bonds
    -   Funds
    -   Real estate

### Questions to Answer

-   Why can't institutions simply use ERC-20?
-   Why is `wallet = identity` a problem?
-   Why must transfers be restricted?

### Deliverable

Explain ERC-3643 in two paragraphs without mentioning Solidity.

------------------------------------------------------------------------

## Phase 2 --- Identity Standards (2--3 days)

### Study

-   ERC-734 (Key Management)
-   ERC-735 (Claims)
-   ONCHAINID implementation

### Concept

``` text
Person
   |
Wallet A
Wallet B
Wallet C
   |
ONCHAINID
```

### Learn

-   Management keys
-   Action keys
-   Claim signer keys
-   Claim topics

### Deliverable

Implement a simplified ONCHAINID contract supporting:

-   `addKey()`
-   `removeKey()`
-   `addClaim()`
-   `removeClaim()`

------------------------------------------------------------------------

## Phase 3 --- Claims System (1--2 days)

### Learn

The claims system is the heart of ERC-3643.

Example structure:

``` solidity
struct Claim {
    uint256 topic;
    address issuer;
    bytes signature;
    bytes data;
}
```

### Example Topics

-   Topic 1 → KYC
-   Topic 2 → AML
-   Topic 3 → Country
-   Topic 4 → Accredited Investor

### Exercise

Create a Hardhat or Foundry test where Alice receives a KYC claim from a
trusted issuer.

### Deliverable

Build a working proof of concept for identity claims.

------------------------------------------------------------------------

## Phase 4 --- Trusted Issuers (1 day)

### Learn

Who is allowed to issue claims?

### Study

-   Trusted Issuers Registry
-   Claim Topics Registry

### Example

### Trusted

-   Deloitte
-   Chainalysis

### Not Trusted

-   Random MetaMask wallet

### Deliverable

Implement:

``` solidity
function isTrustedIssuer(address issuer)
    external
    view
    returns (bool);
```

Build a minimal Trusted Issuers Registry contract.

------------------------------------------------------------------------

## Phase 5 --- Identity Registry (1 day)

### Study

``` text
Wallet
   ↓
Identity Registry
   ↓
ONCHAINID
```

### Example

``` text
0xAAA -> ONCHAINID #1
0xBBB -> ONCHAINID #2
```

### Deliverable

Implement:

-   `registerIdentity()`
-   `deleteIdentity()`
-   `contains()`

------------------------------------------------------------------------

## Phase 6 --- Compliance Engine (2--3 days)

### Learn

The compliance engine is what differentiates ERC-3643 from ERC-20.

### Example Rules

-   Must have KYC.
-   Must be an EU resident.
-   Maximum 1,000 token holders.
-   No transfers before 2027.

### Example Interface

``` solidity
function canTransfer(
    address from,
    address to,
    uint256 amount
) external view returns (bool);
```

### Deliverable

Build a compliance contract implementing at least three transfer
restrictions.

------------------------------------------------------------------------

## Phase 7 --- ERC-3643 Token (2 days)

### Combine Everything

``` text
ERC3643 Token
     |
Identity Registry
Trusted Issuers Registry
Claim Topics Registry
Compliance Engine
```

### Transfer Flow

``` text
transfer()
    ↓
Identity lookup
    ↓
Claim checks
    ↓
Compliance checks
    ↓
Execute transfer
```

### Deliverable

Implement a minimal ERC-3643 token from scratch.

------------------------------------------------------------------------

## Phase 8 --- Wallet Recovery (1 day)

### Study

``` text
Old Wallet
    ↓
ONCHAINID
    ↓
New Wallet
```

### Exercise

Implement:

``` solidity
function recoverWallet(
    address oldWallet,
    address newWallet
);
```

### Goal

Understand why wallet recovery is a major feature for institutions.

------------------------------------------------------------------------

## Phase 9 --- Official Contracts Review (2--3 days)

### Clone and Review

-   ERC-3643 contracts
-   ONCHAINID contracts

### For Every Contract, Answer

1.  What problem does it solve?
2.  Who owns it?
3.  Who can modify it?
4.  What external calls does it make?
5.  What happens if it is compromised?

### Key Contracts

-   Token
-   Compliance
-   Identity Registry
-   Trusted Issuers Registry
-   Claim Topics Registry

------------------------------------------------------------------------

## Phase 10 --- Complete Demo Project (3--5 days)

### Actors

-   Issuer
-   KYC Provider
-   Investor A
-   Investor B

### Workflow

1.  Deploy ONCHAINID.
2.  Register investors.
3.  Add KYC claims.
4.  Deploy ERC-3643 token.
5.  Mint shares.
6.  Transfer Investor A → Investor B.
7.  Attempt transfer to an unverified wallet.
8.  Revoke KYC.
9.  Verify transfer fails.
10. Recover a wallet.

### Deliverable

Build a complete end-to-end demo application.

------------------------------------------------------------------------

## Phase 11 --- Regulatory Layer (Optional)

### Read About

-   MiCA
-   MiFID II
-   SEC regulations
-   Transfer Agents
-   Accredited Investors
-   Transfer Restrictions

This material is useful for interviews and understanding the business
side of ERC-3643.

------------------------------------------------------------------------

## Suggested Timeline

  Week   Topics
  ------ -----------------------------------
  1      Security Tokens, ERC-734, ERC-735
  1      ONCHAINID
  2      Claims and Trusted Issuers
  2      Identity Registry
  3      Compliance Engine
  3      ERC-3643 Token
  4      Official Codebase Review
  4      End-to-End Demo Project

------------------------------------------------------------------------

## Final Mental Model

The most important conceptual shift is:

### Traditional ERC-20

``` text
Address owns tokens.
```

### ERC-3643

``` text
Identity owns tokens.
Wallets are merely access mechanisms.
```

Once this model clicks, the rest of ERC-3643 becomes significantly
easier to understand and implement.
