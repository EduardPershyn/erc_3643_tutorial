// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title OpenToken — a plain, unrestricted ERC-20.
/// @notice Phase 1 demonstrator: this is what institutions CANNOT use.
///
/// The point of this contract is everything it is missing:
///   - Any address can receive tokens. There is no notion of "who" holds them.
///   - The wallet IS the identity: whoever controls the private key controls
///     the value. Lose the key and the value is gone forever — no recovery.
///   - Transfers are unconditional. The issuer cannot enforce KYC, residency,
///     holder caps, lock-ups, or sanctions screening.
///
/// Later phases replace each of these gaps: an Identity Registry answers
/// "who", a Compliance engine answers "is this transfer allowed", and
/// ONCHAINID lets the identity survive a lost wallet.
contract OpenToken is ERC20 {
    constructor() ERC20("Open Token", "OPEN") {}

    /// @dev Public mint on purpose — anyone can create supply to anyone.
    ///      A real security has none of this freedom.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
