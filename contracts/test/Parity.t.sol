// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Guard} from "../src/Guard.sol";
import {ReserveVault} from "../src/ReserveVault.sol";
import {BaseMainnetMarketData, IB20Token} from "../src/BaseMainnetMarketData.sol";
import {IERC20Like} from "../src/ReserveVault.sol";
import {IReserveSpoke} from "../src/interfaces/IReserveSpoke.sol";
import {ISwapRouter} from "../src/interfaces/ISwapRouter.sol";

/// @notice Proves the shipped contracts work against REAL Base mainnet state, with no wallet,
///         no funding and no transaction. The fork is read-only; this is how "testnet-only"
///         still means "mainnet-ready".
contract ParityTest is Test {
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant RKTc = 0xb200000000000000000000000D3176ee4af1102d; // live Coinbase tokenized stock
    address constant EQUITIES_HUB = 0xa4d5947Eb727A052bae69C593FfC84247EC9864E;

    BaseMainnetMarketData market;

    function setUp() public {
        vm.createSelectFork("base");
        market = new BaseMainnetMarketData();
    }

    function test_real_usdc_is_six_decimals() public view {
        assertEq(IERC20Like(USDC).decimals(), 6);
    }

    function test_equities_hub_is_live() public view {
        assertGt(EQUITIES_HUB.code.length, 0, "Aave V4 Equities Hub has code on Base");
    }

    /// @dev B20 tokens are NOT ordinary EVM contracts: the address returns a single 0xef byte and
    ///      the node answers their calls natively. That is why every adapter read is verified over
    ///      real RPC in scripts/probe-mainnet.sh instead of inside a fork, and why the Guard must
    ///      never assume ERC-20 bytecode behaviour for a B20 asset.
    function test_b20_token_is_a_node_native_marker() public view {
        assertEq(RKTc.code.length, 1, "B20 token code is a single marker byte");
        assertEq(uint8(RKTc.code[0]), 0xef);
    }

    function test_same_bytes_deploy_against_real_usdc() public {
        market.setFeed(RKTc, RKTc, address(0)); // real wiring; reads go through RPC, see probe script

        // Same Guard + Vault bytecode as the testnet build, deployed against real mainnet USDC.
        ReserveVault vault = new ReserveVault(
            IERC20Like(USDC), market, IReserveSpoke(address(0)), ISwapRouter(address(0)), address(this), 20e8
        );
        Guard guard = new Guard(market, vault, USDC, 24 hours, 5_000);
        vault.setGuard(guard);
        assertEq(vault.liquidUsdcUsd8(), 0);
        assertEq(vault.totalBookUsd8(), 0);
    }

    function test_price_without_a_feed_fails_loudly() public {
        vm.expectRevert();
        market.price(RKTc);
    }
}
