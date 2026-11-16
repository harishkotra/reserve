// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IMarketData} from "../interfaces/IMarketData.sol";
import {MockB20} from "./MockB20.sol";

contract MockMarketData is IMarketData {
    struct Entry {
        MockB20 token;
        uint256 rawPrice8; // underlying USD per share, 8 decimals
        uint64 updatedAt;
        bool known;
    }

    mapping(address => Entry) public entries;

    function register(address asset, MockB20 token, uint256 rawPrice8, uint64 updatedAt) external {
        entries[asset] = Entry(token, rawPrice8, updatedAt, true);
    }

    function touch(address asset, uint64 updatedAt) external {
        entries[asset].updatedAt = updatedAt;
    }

    function multiplier(address asset)
        external
        view
        returns (uint256 multiplierWad, bool pending, uint64 eff)
    {
        MockB20 t = entries[asset].token;
        return (t.uiMultiplierWad(), t.multiplierPending(), t.effectiveAt());
    }

    function paused(address asset) external view returns (bool) {
        return entries[asset].token.paused();
    }

    /// @dev Multiplier-adjusted, exactly like Chainlink's tokenized-equity feed.
    function price(address asset) external view returns (uint256 price8, uint64 updatedAt) {
        Entry memory e = entries[asset];
        return ((e.rawPrice8 * e.token.uiMultiplierWad()) / 1e18, e.updatedAt);
    }
}
