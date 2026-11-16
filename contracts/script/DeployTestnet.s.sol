// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Deployer} from "./Deploy.s.sol";
import {IERC20Like} from "../src/ReserveVault.sol";

/// @notice Broadcasts the same sequence proven in contracts/test/Deploy.t.sol.
///         forge script contracts/script/DeployTestnet.s.sol --rpc-url base_sepolia --broadcast
contract DeployTestnet is Script {
    function run() external returns (Deployer.Deployed memory d) {
        uint256 pk = vm.envUint("AGENT_PRIVATE_KEY");
        address agent = vm.addr(pk);
        address usdc = vm.envOr("USDC", address(0x036CbD53842c5426634e7929541eC2318f3dCF7e));
        uint256 seed = vm.envOr("SEED_USDC", uint256(20e6));
        uint256 floorUsd8 = vm.envOr("FLOOR_USD8", uint256(5e8)); // operating reserve kept idle

        uint256 balBefore = IERC20Like(usdc).balanceOf(agent);
        console2.log("agent", agent);
        console2.log("usdc held by agent (6dp)", balBefore);

        vm.startBroadcast(pk);
        d = Deployer.deployTestnet(usdc, agent, floorUsd8);
        if (seed > 0) require(IERC20Like(usdc).transfer(d.vault, seed), "seed failed");
        vm.stopBroadcast();

        console2.log("VAULT      ", d.vault);
        console2.log("GUARD      ", d.guard);
        console2.log("MARKETDATA ", d.marketData);
        console2.log("STOCK      ", d.stock);
        console2.log("seed moved to vault (6dp)", seed);
    }
}
