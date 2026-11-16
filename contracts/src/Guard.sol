// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IMarketData} from "./interfaces/IMarketData.sol";
import {IBook} from "./interfaces/IBook.sol";

/// @title Guard
/// @notice The product. Every money movement in the vault passes through here first, and the
///         default answer is no.
/// @dev Identical bytecode runs on Base mainnet and on the testnet build. Only the IMarketData
///      adapter behind it changes (Chainlink feed + Coinbase registry vs. mocks). Refusals are
///      emitted by the vault as events, which is what makes them countable.
contract Guard {
    enum Action {
        BuyStock,
        SupplyCollateral,
        Borrow,
        Repay,
        WithdrawCollateral
    }

    struct Intent {
        Action action;
        address asset;
        uint256 amountUsd8;
    }

    bytes32 public constant OK = bytes32(0);
    bytes32 public constant PAUSED_CORPORATE_ACTION = keccak256("PAUSED_CORPORATE_ACTION");
    bytes32 public constant MULTIPLIER_PENDING = keccak256("MULTIPLIER_PENDING");
    bytes32 public constant FEED_STALE = keccak256("FEED_STALE");
    bytes32 public constant RESERVE_FLOOR_BREACH = keccak256("RESERVE_FLOOR_BREACH");
    bytes32 public constant LTV_EXCEEDED = keccak256("LTV_EXCEEDED");

    uint256 public constant BPS = 10_000;

    IMarketData public immutable market;
    IBook public immutable book;
    /// @notice The cash leg (USDC). Intents on cash are never gated on stock-market state.
    address public immutable cash;
    /// @notice A price older than this is not a price.
    uint64 public immutable feedHeartbeat;
    /// @notice Debt ceiling as a fraction of the book, in bps.
    uint16 public immutable maxLtvBps;

    error ZeroAddress();

    constructor(
        IMarketData market_,
        IBook book_,
        address cash_,
        uint64 feedHeartbeat_,
        uint16 maxLtvBps_
    ) {
        if (address(market_) == address(0) || address(book_) == address(0)) revert ZeroAddress();
        market = market_;
        book = book_;
        cash = cash_;
        feedHeartbeat = feedHeartbeat_;
        maxLtvBps = maxLtvBps_;
    }

    /// @notice Verdict for one intent. View-only: nothing here can be bypassed by reentrancy.
    function check(Intent calldata intent) public view returns (bool ok, bytes32 reason) {
        // Repaying debt is always allowed. A guard that can block de-risking is a hazard.
        if (intent.action == Action.Repay) return (true, OK);

        // Only stock legs carry corporate-action and oracle risk. Cash is cash.
        if (intent.asset != cash) {
            if (market.paused(intent.asset)) return (false, PAUSED_CORPORATE_ACTION);

            (, bool pending, uint64 effectiveAt) = market.multiplier(intent.asset);
            // An announced-but-unapplied multiplier means the price the book carries is wrong.
            if (pending && effectiveAt > block.timestamp) return (false, MULTIPLIER_PENDING);

            (, uint64 updatedAt) = market.price(intent.asset);
            if (updatedAt == 0 || block.timestamp > uint256(updatedAt) + feedHeartbeat) {
                return (false, FEED_STALE);
            }
        }

        if (intent.action == Action.Borrow) {
            uint256 postDebt = book.debtUsd8() + intent.amountUsd8;
            if (postDebt * BPS > book.totalBookUsd8() * maxLtvBps) return (false, LTV_EXCEEDED);
        }

        if (intent.action == Action.BuyStock) {
            if (book.liquidUsdcUsd8() < book.reserveFloorUsd8() + intent.amountUsd8) {
                return (false, RESERVE_FLOOR_BREACH);
            }
        }

        if (intent.action == Action.WithdrawCollateral) {
            uint256 postBook = book.totalBookUsd8() > intent.amountUsd8
                ? book.totalBookUsd8() - intent.amountUsd8
                : 0;
            if (book.debtUsd8() * BPS > postBook * maxLtvBps) return (false, LTV_EXCEEDED);
        }

        return (true, OK);
    }

    /// @notice Human-readable reason for the UI and for post-mortems.
    function reasonName(bytes32 reason) external pure returns (string memory) {
        if (reason == OK) return "OK";
        if (reason == PAUSED_CORPORATE_ACTION) return "PAUSED_CORPORATE_ACTION";
        if (reason == MULTIPLIER_PENDING) return "MULTIPLIER_PENDING";
        if (reason == FEED_STALE) return "FEED_STALE";
        if (reason == RESERVE_FLOOR_BREACH) return "RESERVE_FLOOR_BREACH";
        if (reason == LTV_EXCEEDED) return "LTV_EXCEEDED";
        return "UNKNOWN";
    }
}
