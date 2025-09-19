// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IPriceOracle
/// @notice Simplified oracle returning an external reference price.
interface IPriceOracle {
    /// @notice Returns the latest price in 1e8 precision.
    function latestPrice() external view returns (uint256);
}
