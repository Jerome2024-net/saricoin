// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title SariCoin Stablecoin (SARI)
/// @notice A fiat pegged ERC20 token with role based minting and pausing controls.
/// @dev The contract relies on OpenZeppelin implementations for security hardened primitives.
contract SariCoin is ERC20, ERC20Burnable, Pausable, AccessControl {
    /// @notice Role that allows accounts to mint new tokens.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role that allows accounts to pause and unpause token transfers.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Creates the token and optionally mints an initial supply to a treasury wallet.
    /// @param admin The address that will receive the default admin, minter and pauser roles.
    /// @param treasury The address that will receive the initial token supply.
    /// @param initialSupply The amount of tokens (in wei) minted to the treasury address.
    constructor(address admin, address treasury, uint256 initialSupply) ERC20("Sari USD", "SARI") {
        require(admin != address(0), "SariCoin: admin is zero address");
        require(treasury != address(0), "SariCoin: treasury is zero address");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        if (initialSupply > 0) {
            _mint(treasury, initialSupply);
        }
    }

    /// @notice Mints new stablecoins to the specified account.
    /// @dev Callable only by addresses with the MINTER_ROLE when the token is not paused.
    function mint(address to, uint256 amount) external whenNotPaused onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice Pauses all token transfers, minting and burning.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resumes token transfers, minting and burning after a pause.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20) whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, ERC20) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
