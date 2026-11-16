// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Guard} from "../src/Guard.sol";
import {ReserveVault} from "../src/ReserveVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockB20} from "../src/mocks/MockB20.sol";
import {MockMarketData} from "../src/mocks/MockMarketData.sol";
import {MockRouter} from "../src/mocks/MockRouter.sol";
import {MockSpoke} from "../src/mocks/MockSpoke.sol";
import {IERC20Like} from "../src/ReserveVault.sol";

contract GuardTest is Test {
    MockERC20 usdc;
    MockB20 tsla;
    MockMarketData market;
    MockRouter router;
    MockSpoke spoke;
    ReserveVault vault;
    Guard guard;

    address agent = address(0xA11CE);
    uint256 constant PRICE = 250e8;      // $250.00 per share
    uint256 constant START = 1_760_000_000; // fixed clock

    function setUp() public {
        vm.warp(START);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        tsla = new MockB20("Tesla", "TSLAc");
        market = new MockMarketData();
        router = new MockRouter();
        spoke = new MockSpoke(usdc);

        market.register(address(tsla), tsla, PRICE, uint64(START));
        router.setAsk(address(tsla), 250e6);

        vault = new ReserveVault(
            IERC20Like(address(usdc)),
            market,
            spoke,
            router,
            agent,
            20e8 // $20 operating reserve that may never be spent
        );
        guard = new Guard(market, vault, address(usdc), 15 minutes, 5_000); // 50% max LTV
        vault.setGuard(guard);
        vault.addAsset(address(tsla));

        usdc.mint(address(vault), 100e6); // $100 cash
        usdc.mint(address(spoke), 5_000e6);
        tsla.mint(address(vault), 10e8); // $2,500 of stock, unencumbered for now
    }

    function _buy(uint256 usdcIn) internal returns (bool ok, bytes32 reason) {
        vm.prank(agent);
        return vault.execute(Guard.Action.BuyStock, address(tsla), usdcIn);
    }

    // ---------------------------------------------------------- refusal cases

    function test_refuses_buy_while_multiplier_pending() public {
        tsla.scheduleMultiplier(1.05e18, uint64(START + 1 days));
        (bool ok, bytes32 reason) = _buy(10e6);
        assertFalse(ok);
        assertEq(reason, guard.MULTIPLIER_PENDING());
        assertEq(tsla.balanceOf(address(vault)), 10e8, "no stock acquired on refusal");
    }

    function test_refuses_buy_while_paused() public {
        tsla.setPaused(true);
        (, bytes32 reason) = _buy(10e6);
        assertEq(reason, guard.PAUSED_CORPORATE_ACTION());
    }

    function test_refuses_buy_on_stale_feed() public {
        market.touch(address(tsla), uint64(START - 20 minutes));
        (, bytes32 reason) = _buy(10e6);
        assertEq(reason, guard.FEED_STALE());
    }

    function test_refuses_buy_that_breaks_reserve_floor() public {
        // $100 cash, $20 floor => at most $80 deployable
        (, bytes32 reason) = _buy(85e6);
        assertEq(reason, guard.RESERVE_FLOOR_BREACH());
    }

    function test_refuses_borrow_above_ltv() public {
        // book is $2,600; 50% LTV caps debt at $1,300
        vm.prank(agent);
        (, bytes32 reason) = vault.execute(Guard.Action.Borrow, address(usdc), 1_400e6);
        assertEq(reason, guard.LTV_EXCEEDED());
    }

    function test_refuses_withdraw_that_breaks_ltv() public {
        vm.prank(agent);
        (bool borrowed, ) = vault.execute(Guard.Action.Borrow, address(usdc), 1_000e6);
        assertTrue(borrowed);
        assertEq(spoke.debt(address(usdc)), 1_000e6);
        vm.prank(agent);
        (bool ok, bytes32 reason) = vault.execute(Guard.Action.WithdrawCollateral, address(tsla), 9e8);
        assertFalse(ok);
        assertEq(reason, guard.LTV_EXCEEDED());
        assertEq(tsla.balanceOf(address(vault)), 10e8, "collateral untouched");
    }

    // ---------------------------------------------------------- approval cases

    function test_approves_buy_within_floor_and_swaps() public {
        (bool ok, bytes32 reason) = _buy(25e6);
        assertTrue(ok);
        assertEq(reason, guard.OK());
        assertEq(tsla.balanceOf(address(vault)), 10.1e8); // 10 shares + 4.4/100... i.e. $25 at $250
        assertEq(usdc.balanceOf(address(vault)), 75e6);
    }

    function test_approves_borrow_within_ltv() public {
        vm.prank(agent);
        (bool ok, ) = vault.execute(Guard.Action.Borrow, address(usdc), 1_000e6);
        assertTrue(ok);
        assertEq(spoke.debt(address(usdc)), 1_000e6);
    }

    function test_repay_is_always_allowed_even_when_paused() public {
        vm.prank(agent);
        vault.execute(Guard.Action.Borrow, address(usdc), 1_000e6);
        tsla.setPaused(true);
        tsla.scheduleMultiplier(2e18, uint64(START + 1 days));
        vm.prank(agent);
        (bool ok, bytes32 reason) = vault.execute(Guard.Action.Repay, address(usdc), 400e6);
        assertTrue(ok);
        assertEq(reason, guard.OK());
        assertEq(spoke.debt(address(usdc)), 600e6);
    }

    function test_guard_unblocks_when_multiplier_lands() public {
        tsla.scheduleMultiplier(1.5e18, uint64(START + 1 hours));
        (, bytes32 r1) = _buy(10e6);
        assertEq(r1, guard.MULTIPLIER_PENDING());

        vm.warp(START + 2 hours);
        market.touch(address(tsla), uint64(START + 2 hours));
        tsla.applyMultiplier();

        (bool ok, ) = _buy(10e6);
        assertTrue(ok, "same intent clears after the action lands");
        // price is now multiplier-adjusted: 250 * 1.5
        assertEq(vault.stockValueUsd8(), (10.04e8 * 375e8) / 1e8); // 10 + 0.04 shares at the new price
    }

    function test_refusal_is_emitted_for_counting() public {
        tsla.setPaused(true);
        vm.expectEmit(true, true, false, true, address(vault));
        emit ReserveVault.IntentRefused(uint8(Guard.Action.BuyStock), address(tsla), 10e6, guard.PAUSED_CORPORATE_ACTION());
        _buy(10e6);
    }

    function test_only_agent_can_move_money() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(ReserveVault.NotAgent.selector);
        vault.execute(Guard.Action.BuyStock, address(tsla), 10e6);
    }
}
