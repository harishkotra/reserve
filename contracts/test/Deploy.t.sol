// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Deployer} from "../script/Deploy.s.sol";
import {Guard} from "../src/Guard.sol";
import {ReserveVault, IERC20Like} from "../src/ReserveVault.sol";
import {MockMarketData} from "../src/mocks/MockMarketData.sol";
import {MockB20} from "../src/mocks/MockB20.sol";

/// @notice Runs the EXACT testnet deploy sequence on a Base Sepolia fork, then exercises the money
///         path with real Circle testnet USDC. If this is green, broadcasting is the only step left.
contract DeployTestnetForkTest is Test {
    address constant SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address agent = address(0xA11CE);

    function setUp() public {
        vm.createSelectFork("base_sepolia");
        vm.deal(agent, 1 ether);
    }

    function test_full_deploy_then_buy_then_refuse() public {
        Deployer.Deployed memory d = Deployer.deployTestnet(SEPOLIA_USDC, agent);

        // fund the vault with real testnet USDC, as the operator would out of band
        deal(SEPOLIA_USDC, d.vault, 100e6);
        ReserveVault vault = ReserveVault(d.vault);
        assertEq(vault.liquidUsdcUsd8(), 100e8, "real USDC recognised as $100");

        // the stock the vault will hold is an 8-decimals B20-shaped mock
        assertEq(IERC20Like(d.stock).decimals(), 8);

        // agent buys $25 of the stock through the guarded vault
        vm.prank(agent);
        (bool ok, ) = vault.execute(Guard.Action.BuyStock, d.stock, 25e6);
        assertTrue(ok, "buy approved");
        assertGt(IERC20Like(d.stock).balanceOf(d.vault), 0, "stock acquired");
        assertEq(vault.liquidUsdcUsd8(), 75e8);

        // corporate action lands on the market-data source -> the same intent is refused
        MockB20(d.stock).setPaused(true); // corporate action lands on the token itself
        vm.prank(agent);
        (bool ok2, bytes32 reason) = vault.execute(Guard.Action.BuyStock, d.stock, 25e6);
        assertFalse(ok2, "must refuse while paused");
        assertEq(reason, Guard(d.guard).PAUSED_CORPORATE_ACTION());
        assertEq(vault.liquidUsdcUsd8(), 75e8, "no cash left the vault on refusal");
    }
}
