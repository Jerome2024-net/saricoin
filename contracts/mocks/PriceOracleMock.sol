// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/// @title PriceOracleMock
/// @notice Mock oracle returning configurable prices for testing.
contract PriceOracleMock is IPriceOracle {
    uint256 private _price;

    constructor(uint256 price_) {
        _price = price_;
    }

    function latestPrice() external view override returns (uint256) {
        return _price;
    }

    function setPrice(uint256 price_) external {
        _price = price_;
    }
}
