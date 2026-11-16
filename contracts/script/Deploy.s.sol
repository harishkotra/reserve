// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {Guard} from "../src/Guard.sol";
import {ReserveVault, IERC20Like} from "../src/ReserveVault.sol";
import {IMarketData} from "../src/interfaces/IMarketData.sol";
import {IReserveSpoke} from "../src/interfaces/IReserveSpoke.sol";
import {ISwapRouter} from "../src/interfaces/ISwapRouter.sol";
import {BaseMainnetMarketData} from "../src/BaseMainnetMarketData.sol";
import {MockB20} from "../src/mocks/MockB20.sol";
import {MockMarketData} from "../src/mocks/MockMarketData.sol";
import {MockRouter} from "../src/mocks/MockRouter.sol";
import {MockSpoke} from "../src/mocks/MockSpoke.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/// @notice Deploys Reserve. Guard and ReserveVault are byte-identical on every network;
///         only the market-data adapter and the referenced addresses change.
/// @dev Testnet path is simulated in contracts/test/Deploy.t.sol, which is why "testnet" does not
///      mean "untested": the exact deploy sequence runs on a Sepolia fork before it is broadcast.
library Deployer {
    struct Deployed {
        address vault;
        address guard;
        address marketData;
        address stock;
    }

    function deployTestnet(address usdc, address agent, uint256 floorUsd8)
        internal
        returns (Deployed memory d)
    {
        MockB20 stock = new MockB20("Tesla", "TSLAc");
        MockMarketData market = new MockMarketData();
        MockRouter router = new MockRouter();
        MockSpoke spoke = new MockSpoke(MockERC20(usdc));

        market.register(address(stock), stock, 250e8, uint64(block.timestamp)); // $250
        router.setAsk(address(stock), 250e6);

        ReserveVault vault = new ReserveVault(
            IERC20Like(usdc), market, IReserveSpoke(address(spoke)), ISwapRouter(address(router)), agent, floorUsd8
        );
        Guard guard = new Guard(market, vault, usdc, 24 hours, 5_000);
        vault.setGuard(guard);
        vault.addAsset(address(stock)); // without this the stock leg values at zero

        // On Sepolia the cash leg is real Circle testnet USDC, funded out of band (faucet / transfer).
        d = Deployed(address(vault), address(guard), address(market), address(stock));
    }

    function deployMainnet(
        address usdc,
        address agent,
        address stock,
        address chainlinkFeed,
        address spoke,
        address router
    ) internal returns (Deployed memory d) {
        BaseMainnetMarketData market = new BaseMainnetMarketData();
        market.setFeed(stock, stock, chainlinkFeed);

        ReserveVault vault = new ReserveVault(
            IERC20Like(usdc), market, IReserveSpoke(spoke), ISwapRouter(router), agent, 20e8
        );
        Guard guard = new Guard(market, vault, usdc, 24 hours, 5_000);
        vault.setGuard(guard);

        d = Deployed(address(vault), address(guard), address(market), stock);
    }
}
