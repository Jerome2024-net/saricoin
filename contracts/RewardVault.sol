// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title RewardVault
/// @notice Stores impact rewards with linear vesting for SARI token holders.
contract RewardVault is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Duration of vesting for each credited reward (30 days).
    uint64 public constant VESTING_DURATION = 30 days;

    /// @notice SARI token associated with the vault.
    IERC20 public sari;
    /// @notice Flag set once the SARI contract is authorized.
    bool public sariConfigured;

    /// @notice Vesting entry for a user.
    struct VestingEntry {
        uint256 amount;
        uint256 claimed;
        uint64 start;
    }

    /// @notice Mapping of user to array of vesting entries.
    mapping(address => VestingEntry[]) private vestings;

    /// @notice Thrown when attempting to interact before SARI is configured.
    error SariNotConfigured();

    /// @param owner_ Admin address allowed to configure the vault.
    constructor(address owner_) {
        _transferOwnership(owner_);
    }

    /// @notice Sets the SARI contract as the only account allowed to credit rewards.
    /// @param sariAddress Address of the deployed SARI token.
    function configureSari(address sariAddress) external onlyOwner {
        require(!sariConfigured, "Already configured");
        require(sariAddress != address(0), "Invalid SARI");
        sari = IERC20(sariAddress);
        sariConfigured = true;
    }

    /// @notice Credits a new vesting entry for a user. Callable by SARI only.
    /// @param user Recipient of the vesting entry.
    /// @param amount Amount of tokens vested.
    function credit(address user, uint256 amount) external nonReentrant {
        if (!sariConfigured || msg.sender != address(sari)) {
            revert SariNotConfigured();
        }
        require(user != address(0), "Invalid user");
        require(amount > 0, "Invalid amount");
        vestings[user].push(VestingEntry({amount: amount, claimed: 0, start: uint64(block.timestamp)}));
    }

    /// @notice Returns the total claimable amount for a user at the current block timestamp.
    /// @param user Address to query.
    function claimable(address user) public view returns (uint256 total) {
        VestingEntry[] memory entries = vestings[user];
        uint256 len = entries.length;
        for (uint256 i = 0; i < len; i++) {
            VestingEntry memory entry = entries[i];
            total += _vestedAmount(entry) - entry.claimed;
        }
    }

    /// @notice Claims available vested rewards for the caller.
    function claim() external nonReentrant {
        uint256 amount = _consumeClaimable(msg.sender);
        require(amount > 0, "Nothing to claim");
        sari.safeTransfer(msg.sender, amount);
    }

    /// @notice Allows the owner to sweep excess tokens (excluding vested balances).
    /// @param token ERC20 token to sweep.
    /// @param to Recipient address for the sweep.
    /// @param amount Amount to transfer.
    function sweep(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        IERC20(token).safeTransfer(to, amount);
    }

    /// @notice Returns the vesting entries for a user.
    /// @param user Address to inspect.
    function vestingEntries(address user) external view returns (VestingEntry[] memory) {
        return vestings[user];
    }

    function _consumeClaimable(address user) internal returns (uint256 total) {
        VestingEntry[] storage entries = vestings[user];
        uint256 len = entries.length;
        for (uint256 i = 0; i < len; i++) {
            VestingEntry storage entry = entries[i];
            uint256 vested = _vestedAmount(entry);
            uint256 releasable = vested - entry.claimed;
            if (releasable > 0) {
                entry.claimed += releasable;
                total += releasable;
            }
        }
    }

    function _vestedAmount(VestingEntry memory entry) internal view returns (uint256) {
        if (block.timestamp <= entry.start) {
            return 0;
        }
        uint256 elapsed = block.timestamp - entry.start;
        if (elapsed >= VESTING_DURATION) {
            return entry.amount;
        }
        return (entry.amount * elapsed) / VESTING_DURATION;
    }
}
