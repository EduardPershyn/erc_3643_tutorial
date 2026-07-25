// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Topics — well-known ERC-3643 claim topic ids.
/// @notice Shared across phases so the token/compliance can require e.g. KYC.
library Topics {
    uint256 internal constant KYC = 1;
    uint256 internal constant AML = 2;
    uint256 internal constant COUNTRY = 3;
    uint256 internal constant ACCREDITED = 4;
}
