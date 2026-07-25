// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AbstractModule} from "./AbstractModule.sol";

/// @title MaxHolderModule — "at most N token holders".
/// @notice Rule #3 from the plan ("Maximum 1,000 token holders"). This is the
///         STATEFUL module: it mirrors balances via the action hooks to keep an
///         accurate holder count, because a module cannot read the token's
///         balances directly.
///
/// A transfer/mint that would introduce a NEW holder while already at the cap
/// is rejected; existing holders can always receive more.
contract MaxHolderModule is AbstractModule {
    uint256 public maxHolders;
    uint256 public holderCount;

    // mirror of the token balances, maintained purely through the hooks
    mapping(address holder => uint256 balance) private _balance;

    event MaxHoldersUpdated(uint256 maxHolders);

    constructor(uint256 maxHolders_) {
        maxHolders = maxHolders_;
    }

    function setMaxHolders(uint256 maxHolders_) external onlyOwner {
        require(maxHolders_ >= holderCount, "MaxHolder: below current holder count");
        maxHolders = maxHolders_;
        emit MaxHoldersUpdated(maxHolders_);
    }

    function balanceOfMirror(address holder) external view returns (uint256) {
        return _balance[holder];
    }

    function moduleCheck(address, address to, uint256 amount) external view override returns (bool) {
        if (amount == 0) return true;
        if (_balance[to] > 0) return true; // already a holder — no new slot needed
        return holderCount < maxHolders; // new holder requires a free slot
    }

    // --- state maintenance via hooks -----------------------------------

    function _mintAction(address to, uint256 amount) internal override {
        _increase(to, amount);
    }

    function _transferAction(address from, address to, uint256 amount) internal override {
        _increase(to, amount);
        _decrease(from, amount);
    }

    function _burnAction(address from, uint256 amount) internal override {
        _decrease(from, amount);
    }

    function _increase(address holder, uint256 amount) private {
        if (amount > 0 && _balance[holder] == 0) holderCount++;
        _balance[holder] += amount;
    }

    function _decrease(address holder, uint256 amount) private {
        _balance[holder] -= amount;
        if (_balance[holder] == 0) holderCount--;
    }

    function name() external pure override returns (string memory) {
        return "MaxHolderModule";
    }
}
