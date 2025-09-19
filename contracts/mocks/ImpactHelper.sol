// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ImpactHelper
/// @notice Helper contract used in tests to batch transfers within a single transaction.
contract ImpactHelper {
    function doubleTransfer(address token, address to, uint256 amount) external {
        IERC20(token).transfer(to, amount);
        IERC20(token).transfer(to, amount);
    }
}
