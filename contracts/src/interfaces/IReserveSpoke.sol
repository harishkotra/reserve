// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Subset of an Aave-V4 spoke used by the vault.
/// @dev Mainnet: the Coinbase Stocks spoke on Base. Testnet: MockSpoke with identical signatures.
interface IReserveSpoke {
    function supply(address asset, uint256 amount) external returns (uint256 supplied);
    function withdraw(address asset, uint256 amount) external returns (uint256 withdrawn);
    function borrow(address asset, uint256 amount) external returns (uint256 borrowed);
    function repay(address asset, uint256 amount) external returns (uint256 repaid);
    function debt(address asset) external view returns (uint256);
    function collateralUsd8() external view returns (uint256);
}
