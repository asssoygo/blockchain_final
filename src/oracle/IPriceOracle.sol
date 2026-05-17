// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title  IPriceOracle
/// @notice Minimal interface for a Chainlink-backed price oracle with optional staleness enforcement.
interface IPriceOracle {
    /// @notice Returns the raw latest price data from the underlying Chainlink feed.
    /// @return price     The latest answer (in the feed's native unit).
    /// @return decimals  Number of decimals the answer is expressed in.
    /// @return updatedAt Unix timestamp of the last successful oracle update.
    function getLatestPrice() external view returns (int256 price, uint8 decimals, uint256 updatedAt);

    /// @notice Returns the latest price only if it is fresher than `maxAge` seconds.
    /// @param maxAge Maximum acceptable age of the price in seconds.
    /// @return price The latest price if not stale.
    function getPriceWithStalenessCheck(uint256 maxAge) external view returns (int256 price);
}
