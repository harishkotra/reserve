// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MockERC20} from "./MockERC20.sol";

/// @notice B20-shaped tokenized stock: balance never moves on a corporate action, the multiplier does.
/// @dev Mirrors docs.base.org B20 "UI Multipliers" semantics, which is the whole reason Guard exists.
contract MockB20 is MockERC20 {
    uint256 public uiMultiplierWad = 1e18;
    bool public paused;
    bool public multiplierPending;
    uint64 public effectiveAt;
    uint256 public pendingMultiplierWad;

    /// @dev Real Coinbase tokenized stocks use 8 decimals (verified on RKTc). Mocks must match.
    constructor(string memory n, string memory s) MockERC20(n, s, 8) {}

    /// @notice Issuer announces a corporate action; nothing applies until effectiveAt.
    function scheduleMultiplier(uint256 mWad, uint64 at) external {
        pendingMultiplierWad = mWad;
        effectiveAt = at;
        multiplierPending = true;
    }

    function applyMultiplier() external {
        require(multiplierPending, "nothing pending");
        require(uint64(block.timestamp) >= effectiveAt, "too early");
        uiMultiplierWad = pendingMultiplierWad;
        multiplierPending = false;
    }

    function setPaused(bool p) external {
        paused = p;
    }
}
