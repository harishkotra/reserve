// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IMarketData} from "./interfaces/IMarketData.sol";

interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function decimals() external view returns (uint8);
}

/// @notice The B20 token surface that matters, verified against a live Base mainnet token
///         (RKTc 0xb200000000000000000000000D3176ee4af1102d on 2026-11-16):
///         decimals()=8, uiMultiplier()=1e18, effectiveAt()=0, pausedFeatures()=[].
/// @dev paused() and isPaused() both revert on that token, so pause state is read as
///      pausedFeatures().length > 0. Do not "simplify" this back to paused().
interface IB20Token {
    function uiMultiplier() external view returns (uint256);
    function effectiveAt() external view returns (uint64);
    function pausedFeatures() external view returns (string[] memory);
}

/// @title BaseMainnetMarketData
/// @notice Mainnet adapter: multiplier/pause from the token itself, USD price from Chainlink's
///         tokenized-equity feed (already multiplier-adjusted, 8 decimals).
/// @dev Deploy this with the same Guard and ReserveVault bytes used on testnet. Only addresses change.
contract BaseMainnetMarketData is IMarketData {
    struct Feed {
        address token;
        address chainlink;
    }

    mapping(address => Feed) public feeds;
    address public owner;

    error NotOwner();

    constructor() {
        owner = msg.sender;
    }

    function setFeed(address asset, address token, address chainlink) external {
        if (msg.sender != owner) revert NotOwner();
        feeds[asset] = Feed(token, chainlink);
    }

    function multiplier(address asset)
        public
        view
        returns (uint256 multiplierWad, bool pending, uint64 effectiveAt)
    {
        IB20Token t = IB20Token(feeds[asset].token);
        uint64 eff = t.effectiveAt();
        return (t.uiMultiplier(), eff > block.timestamp, eff);
    }

    function paused(address asset) public view returns (bool) {
        return IB20Token(feeds[asset].token).pausedFeatures().length > 0;
    }

    function price(address asset) public view returns (uint256 price8, uint64 updatedAt) {
        IAggregatorV3 feed = IAggregatorV3(feeds[asset].chainlink);
        (, int256 answer,, uint256 ts,) = feed.latestRoundData();
        require(answer > 0, "bad price");
        uint8 d = feed.decimals();
        uint256 p = uint256(answer);
        price8 = d >= 8 ? p / (10 ** (d - 8)) : p * (10 ** (8 - d));
        updatedAt = uint64(ts);
    }
}
