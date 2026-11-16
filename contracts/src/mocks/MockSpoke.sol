// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IReserveSpoke} from "../interfaces/IReserveSpoke.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockSpoke is IReserveSpoke {
    MockERC20 public immutable usdc;
    mapping(address => uint256) public supplied;
    mapping(address => uint256) public debtOf;

    constructor(MockERC20 _usdc) {
        usdc = _usdc;
    }

    function supply(address asset, uint256 amount) external returns (uint256) {
        MockERC20(asset).transferFrom(msg.sender, address(this), amount);
        supplied[asset] += amount;
        return amount;
    }

    function withdraw(address asset, uint256 amount) external returns (uint256) {
        supplied[asset] -= amount;
        MockERC20(asset).transfer(msg.sender, amount);
        return amount;
    }

    function borrow(address asset, uint256 amount) external returns (uint256) {
        debtOf[asset] += amount;
        MockERC20(asset).transfer(msg.sender, amount);
        return amount;
    }

    function repay(address asset, uint256 amount) external returns (uint256) {
        uint256 d = debtOf[asset];
        uint256 pay = amount > d ? d : amount;
        MockERC20(asset).transferFrom(msg.sender, address(this), pay);
        debtOf[asset] = d - pay;
        return pay;
    }

    function debt(address asset) external view returns (uint256) {
        return debtOf[asset];
    }

    function collateralUsd8() external view returns (uint256) {
        return 0; // testnet mocks value collateral through the vault book
    }
}
