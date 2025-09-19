// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILiquidityLens} from "../interfaces/ILiquidityLens.sol";

/// @title LiquidityLensMock
/// @notice Mock lens returning configurable liquidity metrics.
contract LiquidityLensMock is ILiquidityLens {
    uint256 private _L;
    uint256 private _S;
    uint256 private _sellP;

    constructor(uint256 L_, uint256 S_, uint256 sellP_) {
        _L = L_;
        _S = S_;
        _sellP = sellP_;
    }

    function metrics() external view override returns (uint256 L, uint256 S, uint256 sellP) {
        return (_L, _S, _sellP);
    }

    function setMetrics(uint256 L_, uint256 S_, uint256 sellP_) external {
        _L = L_;
        _S = S_;
        _sellP = sellP_;
    }
}
