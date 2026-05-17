// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IPriceOracle} from "./IPriceOracle.sol";

/// @title  PriceOracle
/// @notice Chainlink-backed price oracle with configurable staleness enforcement. The owner may
///         update the underlying Chainlink feed and the default maximum price age at any time.
///
/// @dev    All external calls go through two internal helpers so staleness logic is never
///         duplicated. `getLatestPrice` never applies a staleness check; callers that want one
///         should use `getPriceWithStalenessCheck` or the zero-config `getPrice` shorthand.
contract PriceOracle is IPriceOracle, Ownable {
    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice The Chainlink aggregator feed this oracle reads from.
    AggregatorV3Interface public priceFeed;

    /// @notice Default maximum acceptable age of the price in seconds (e.g. 3600 = 1 hour).
    uint256 public defaultMaxAge;

    /// @notice Human-readable label for the feed (e.g. "ETH/USD").
    string public description;

    // ─── Errors ───────────────────────────────────────────────────────────────

    /// @notice Thrown when a required address argument is the zero address.
    error ZeroAddress();

    /// @notice Thrown when a staleness check fails.
    /// @param updatedAt   Unix timestamp of the last oracle update.
    /// @param currentTime Current block timestamp.
    /// @param maxAge      Caller-supplied maximum acceptable age.
    error StalePrice(uint256 updatedAt, uint256 currentTime, uint256 maxAge);

    /// @notice Thrown when the oracle reports a non-positive price.
    /// @param price The invalid price returned by the feed.
    error InvalidPrice(int256 price);

    /// @notice Thrown when the oracle round is flagged incomplete (answeredInRound < roundId)
    ///         or when updatedAt is zero.
    error IncompleteRound();

    /// @notice Thrown when a zero value is supplied for a maximum-age parameter.
    error InvalidMaxAge();

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted when the owner replaces the underlying Chainlink feed.
    /// @param oldFeed Previous aggregator address.
    /// @param newFeed New aggregator address.
    event PriceFeedUpdated(address indexed oldFeed, address indexed newFeed);

    /// @notice Emitted when the owner changes the default staleness window.
    /// @param oldMaxAge Previous value in seconds.
    /// @param newMaxAge New value in seconds.
    event DefaultMaxAgeUpdated(uint256 oldMaxAge, uint256 newMaxAge);

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @notice Deploys the oracle and binds it to a Chainlink aggregator.
    /// @param _priceFeed    Address of the Chainlink AggregatorV3Interface feed.
    /// @param _defaultMaxAge Default staleness window in seconds (must be > 0).
    /// @param _description  Human-readable feed label (e.g. "ETH/USD").
    /// @param _owner        Address that will own this contract.
    constructor(address _priceFeed, uint256 _defaultMaxAge, string memory _description, address _owner)
        Ownable(_owner)
    {
        if (_priceFeed == address(0) || _owner == address(0)) revert ZeroAddress();
        if (_defaultMaxAge == 0) revert InvalidMaxAge();

        priceFeed = AggregatorV3Interface(_priceFeed);
        defaultMaxAge = _defaultMaxAge;
        description = _description;
    }

    // ─── IPriceOracle ─────────────────────────────────────────────────────────

    /// @notice Returns the raw latest round data from the Chainlink feed without a staleness check.
    /// @return price     The latest reported price (in the feed's native unit).
    /// @return decimals  Number of decimals the price is expressed in.
    /// @return updatedAt Unix timestamp of the last oracle update.
    function getLatestPrice() external view override returns (int256 price, uint8 decimals, uint256 updatedAt) {
        (uint80 roundId, int256 _price,, uint256 _updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

        if (answeredInRound < roundId) revert IncompleteRound();
        if (_updatedAt == 0) revert IncompleteRound();
        if (_price <= 0) revert InvalidPrice(_price);

        return (_price, priceFeed.decimals(), _updatedAt);
    }

    /// @notice Returns the latest price only if it is fresher than `maxAge` seconds.
    /// @param maxAge Maximum acceptable age of the price in seconds.
    /// @return price The validated, fresh price.
    function getPriceWithStalenessCheck(uint256 maxAge) external view override returns (int256 price) {
        return _fetchWithStaleness(maxAge);
    }

    /// @notice Convenience wrapper that applies the {defaultMaxAge} staleness check.
    /// @return price The validated, fresh price.
    function getPrice() external view returns (int256 price) {
        return _fetchWithStaleness(defaultMaxAge);
    }

    // ─── Owner Functions ──────────────────────────────────────────────────────

    /// @notice Replaces the underlying Chainlink price feed.
    /// @param _newFeed Address of the new AggregatorV3Interface.
    function setPriceFeed(address _newFeed) external onlyOwner {
        if (_newFeed == address(0)) revert ZeroAddress();
        address old = address(priceFeed);
        priceFeed = AggregatorV3Interface(_newFeed);
        emit PriceFeedUpdated(old, _newFeed);
    }

    /// @notice Updates the default staleness window.
    /// @param _newMaxAge New maximum acceptable age in seconds (must be > 0).
    function setDefaultMaxAge(uint256 _newMaxAge) external onlyOwner {
        if (_newMaxAge == 0) revert InvalidMaxAge();
        uint256 old = defaultMaxAge;
        defaultMaxAge = _newMaxAge;
        emit DefaultMaxAgeUpdated(old, _newMaxAge);
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    /// @dev Shared staleness-checked fetch logic used by {getPriceWithStalenessCheck} and {getPrice}.
    function _fetchWithStaleness(uint256 maxAge) private view returns (int256 price) {
        (uint80 roundId, int256 _price,, uint256 _updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

        if (answeredInRound < roundId) revert IncompleteRound();
        if (_updatedAt == 0) revert IncompleteRound();
        if (_price <= 0) revert InvalidPrice(_price);
        if (block.timestamp - _updatedAt > maxAge) revert StalePrice(_updatedAt, block.timestamp, maxAge);

        return _price;
    }
}
