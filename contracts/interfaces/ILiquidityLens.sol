// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ILiquidityLens
/// @notice Interface exposing liquidity metrics for reference pricing.
interface ILiquidityLens {
    /// @notice Returns liquidity (L), supply (S), and sell pressure metric (sellP), all 1e6 scale.
    function metrics() external view returns (uint256 L, uint256 S, uint256 sellP);
}
