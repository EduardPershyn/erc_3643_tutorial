// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC734} from "./IERC734.sol";
import {IERC735} from "./IERC735.sol";

/// @title IIdentity — the ONCHAINID interface = keys (ERC-734) + claims (ERC-735).
/// @notice Canonical type used wherever code needs "an identity contract"
///         (e.g. the Identity Registry stores wallet -> IIdentity).
interface IIdentity is IERC734, IERC735 {}
