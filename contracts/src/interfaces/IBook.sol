// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice The vault's financial state, in USD with 8 decimals, as Guard needs to see it.
interface IBook {
    function liquidUsdcUsd8() external view returns (uint256);
    function totalBookUsd8() external view returns (uint256);
    function debtUsd8() external view returns (uint256);
    function reserveFloorUsd8() external view returns (uint256);
}
