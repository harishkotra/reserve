// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Chain-agnostic view of one tokenized-stock asset.
/// @dev The mainnet adapter reads Chainlink's tokenized-equity feed (already multiplier-adjusted)
///      plus Coinbase's onchain multiplier/pause registry. The testnet adapter reads mocks.
///      Both return the SAME shapes, so Guard has one code path on every network.
interface IMarketData {
    /// @return multiplierWad displayed multiplier (1e18 = 1.0)
    /// @return pending a scheduled corporate action exists that is not yet applied
    /// @return effectiveAt timestamp the pending multiplier becomes effective (0 if none)
    function multiplier(address asset)
        external
        view
        returns (uint256 multiplierWad, bool pending, uint64 effectiveAt);

    /// @notice True while the issuer/oracle has the asset paused for a corporate action.
    function paused(address asset) external view returns (bool);

    /// @notice Multiplier-adjusted USD price, 8 decimals (matches Chainlink's equity feed).
    function price(address asset) external view returns (uint256 price8, uint64 updatedAt);
}
