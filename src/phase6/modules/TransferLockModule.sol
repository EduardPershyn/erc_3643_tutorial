// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AbstractModule} from "./AbstractModule.sol";

/// @title TransferLockModule — "no transfers before <releaseTime>".
/// @notice Stateless rule (rule #1 from the plan: "No transfers before 2027").
///         Only gates holder-to-holder transfers — minting distributes tokens
///         through the token's mint path (which does not call `canTransfer`),
///         so the issuer can still allocate during the lock-up.
contract TransferLockModule is AbstractModule {
    uint256 public releaseTime;

    event ReleaseTimeUpdated(uint256 releaseTime);

    constructor(uint256 releaseTime_) {
        releaseTime = releaseTime_;
    }

    function setReleaseTime(uint256 releaseTime_) external onlyOwner {
        releaseTime = releaseTime_;
        emit ReleaseTimeUpdated(releaseTime_);
    }

    function moduleCheck(address, address, uint256) external view override returns (bool) {
        return block.timestamp >= releaseTime;
    }

    function name() external pure override returns (string memory) {
        return "TransferLockModule";
    }
}
