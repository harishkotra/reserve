// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockRouter is ISwapRouter {
    /// @dev ask in USDC (6dp) per whole share (18dp)
    mapping(address => uint256) public askUsdcPerShare;

    function setAsk(address tokenOut, uint256 usdcPerShare6) external {
        askUsdcPerShare[tokenOut] = usdcPerShare6;
    }

    function exactInputSingle(ExactInputSingleParams calldata p)
        external
        payable
        returns (uint256 amountOut)
    {
        MockERC20(p.tokenIn).transferFrom(msg.sender, address(this), p.amountIn);
        uint256 ask = askUsdcPerShare[p.tokenOut];
        require(ask > 0, "no market");
        uint8 dec = MockERC20(p.tokenOut).decimals();
        amountOut = (p.amountIn * (10 ** dec)) / ask;
        require(amountOut >= p.amountOutMinimum, "slippage");
        MockERC20(p.tokenOut).mint(p.recipient, amountOut);
    }
}
