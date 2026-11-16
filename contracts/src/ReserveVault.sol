// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Guard} from "./Guard.sol";
import {IBook} from "./interfaces/IBook.sol";
import {IMarketData} from "./interfaces/IMarketData.sol";
import {IReserveSpoke} from "./interfaces/IReserveSpoke.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint8);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

/// @title ReserveVault
/// @notice Holds the agent's USDC and its tokenized-stock book. Nothing leaves without a Guard
///         verdict. Identical implementation on testnet and mainnet; only addresses change.
contract ReserveVault is IBook {
    uint256 public constant BPS = 10_000;

    IERC20Like public immutable usdc;
    IMarketData public immutable market;
    IReserveSpoke public immutable spoke;
    ISwapRouter public immutable router;
    address public owner;
    address public agent;
    Guard public guard;

    uint256 public floorUsd8;
    address[] public assets;
    mapping(address => bool) public isAsset;

    event RevenueBooked(address indexed from, uint256 amount);
    event IntentApproved(uint8 indexed action, address indexed asset, uint256 amount);
    event IntentRefused(uint8 indexed action, address indexed asset, uint256 amount, bytes32 reason);
    event GuardSet(address guard);
    event FloorSet(uint256 usd8);
    event AgentSet(address agent);

    error NotOwner();
    error NotAgent();
    error GuardAlreadySet();

    constructor(
        IERC20Like usdc_,
        IMarketData market_,
        IReserveSpoke spoke_,
        ISwapRouter router_,
        address agent_,
        uint256 floorUsd8_
    ) {
        usdc = usdc_;
        market = market_;
        spoke = spoke_;
        router = router_;
        agent = agent_;
        floorUsd8 = floorUsd8_;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyAgent() {
        if (msg.sender != agent) revert NotAgent();
        _;
    }

    // ---------------------------------------------------------------- admin

    function setGuard(Guard guard_) external onlyOwner {
        if (address(guard) != address(0)) revert GuardAlreadySet();
        guard = guard_;
        emit GuardSet(address(guard_));
    }

    function setAgent(address agent_) external onlyOwner {
        agent = agent_;
        emit AgentSet(agent_);
    }

    function setFloor(uint256 floorUsd8_) external onlyOwner {
        floorUsd8 = floorUsd8_;
        emit FloorSet(floorUsd8_);
    }

    function addAsset(address asset) external onlyOwner {
        if (!isAsset[asset]) {
            isAsset[asset] = true;
            assets.push(asset);
        }
    }

    // ------------------------------------------------------------- IBook view

    function liquidUsdcUsd8() public view returns (uint256) {
        return usdc.balanceOf(address(this)) * 1e2;
    }

    function stockValueUsd8() public view returns (uint256 total) {
        uint256 n = assets.length;
        for (uint256 k; k < n; ++k) {
            address a = assets[k];
            uint256 bal = IERC20Like(a).balanceOf(address(this));
            if (bal == 0) continue;
            (uint256 p8, ) = market.price(a);
            total += (bal * p8) / (10 ** IERC20Like(a).decimals());
        }
    }

    function totalBookUsd8() public view returns (uint256) {
        return liquidUsdcUsd8() + stockValueUsd8();
    }

    function debtUsd8() public view returns (uint256) {
        return spoke.debt(address(usdc)) * 1e2;
    }

    function reserveFloorUsd8() external view returns (uint256) {
        return floorUsd8;
    }

    // ------------------------------------------------------------ money path

    /// @notice The only way value moves. Returns false instead of reverting when Guard says no:
    ///         a refusal is a normal outcome, not an error.
    function execute(Guard.Action action, address asset, uint256 amount)
        external
        onlyAgent
        returns (bool ok, bytes32 reason)
    {
        uint256 usd8 = _toUsd8(action, asset, amount);
        (ok, reason) = guard.check(Guard.Intent({action: action, asset: asset, amountUsd8: usd8}));
        if (!ok) {
            emit IntentRefused(uint8(action), asset, amount, reason);
            return (false, reason);
        }
        _run(action, asset, amount);
        emit IntentApproved(uint8(action), asset, amount);
    }

    /// @notice x402 receipts land here. Free money in, guarded money out.
    function bookRevenue(uint256 amount) external {
        require(usdc.transferFrom(msg.sender, address(this), amount), "usdc pull failed");
        emit RevenueBooked(msg.sender, amount);
    }

    function _toUsd8(Guard.Action action, address asset, uint256 amount)
        internal
        view
        returns (uint256)
    {
        // BuyStock / Borrow / Repay amounts are USDC base units; everything else is stock units.
        if (
            action == Guard.Action.BuyStock || action == Guard.Action.Borrow
                || action == Guard.Action.Repay || asset == address(usdc)
        ) {
            return amount * 1e2;
        }
        (uint256 p8, ) = market.price(asset);
        return (amount * p8) / (10 ** IERC20Like(asset).decimals());
    }

    function _run(Guard.Action action, address asset, uint256 amount) internal {
        if (action == Guard.Action.BuyStock) {
            usdc.approve(address(router), amount);
            router.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: address(usdc),
                    tokenOut: asset,
                    fee: 3000,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amount,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        } else if (action == Guard.Action.SupplyCollateral) {
            IERC20Like(asset).approve(address(spoke), amount);
            spoke.supply(asset, amount);
        } else if (action == Guard.Action.Borrow) {
            spoke.borrow(address(usdc), amount);
        } else if (action == Guard.Action.Repay) {
            usdc.approve(address(spoke), amount);
            spoke.repay(address(usdc), amount);
        } else {
            spoke.withdraw(asset, amount);
        }
    }
}
