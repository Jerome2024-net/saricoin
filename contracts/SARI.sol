// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {RewardVault} from "./RewardVault.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {ILiquidityLens} from "./interfaces/ILiquidityLens.sol";

/// @title SARI speculative cyclic token
/// @notice ERC20 token with programmatic burn and cyclic impact dynamics.
contract SARI is ERC20, ERC20Permit, Ownable2Step, Pausable, ReentrancyGuard, AccessControl {
    /// @notice Role governing parameter changes.
    bytes32 public constant PARAM_ROLE = keccak256("PARAM_ROLE");
    /// @notice Role allowed to trigger periodic ticks.
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    /// @notice Local frequency per participant f_i (scale 1e6).
    mapping(address => uint256) public freq;
    /// @notice Network resonance F (scale 1e6).
    uint256 public F;
    /// @notice Cumulative energy E (scale 1e6).
    uint256 public E;

    /// @notice Reset threshold for frequency (scale 1e6).
    uint256 public fMax;
    /// @notice Base frequency after reset (scale 1e6).
    uint256 public fBase;

    /// @notice Dissipation coefficient gamma (parts per million, base 1e6).
    uint256 public gamma;
    /// @notice Activity coupling coefficient alpha (ppm, base 1e6).
    uint256 public alpha;
    /// @notice Resonance coupling coefficient beta (ppm, base 1e6).
    uint256 public beta;
    /// @notice Global dissipation applied during tick (ppm, base 1e6).
    uint256 public delta;
    /// @notice Impact impulse applied to F (scale 1e6).
    uint256 public kappa;

    /// @notice Burn applied during impact in basis points (1e4 = 100%).
    uint256 public burnBps;
    /// @notice Mint per impact credited to reward vault (token units, 18 decimals).
    uint256 public rewardPerImpact;
    /// @notice Number of blocks per epoch tick.
    uint256 public epochBlocks;

    /// @notice Maximum impacts allowed per block.
    uint256 public maxImpactsPerBlock;
    /// @notice Mapping of impacts that occurred per block number.
    mapping(uint256 => uint256) public impactsInBlock;

    /// @notice Block number after which an address may trigger another impact.
    mapping(address => uint256) public nextImpactBlock;
    /// @notice Cooldown in blocks enforced between impacts per address.
    uint256 public impactCooldownBlocks;

    /// @notice High resonance threshold enabling surcharge.
    uint256 public Fhigh;
    /// @notice Optional surcharge applied on transfers when F >= Fhigh (basis points).
    uint256 public surchargeFeeBps;
    /// @notice Flag enabling surcharge fee collection.
    bool public surchargeEnabled;

    /// @notice Price oracle providing external reference price.
    IPriceOracle public priceOracle;
    /// @notice Liquidity lens providing market metrics.
    ILiquidityLens public liquidityLens;
    /// @notice Reward vault handling vesting of impact rewards.
    RewardVault public rewardVault;

    /// @notice Last block number at which tick was executed.
    uint256 public lastTickBlock;
    /// @notice Flag blocking impacts when circuit breaker is active.
    bool public circuitBroken;

    /// @notice Parameters for internal reference price calculations.
    struct PriceParams {
        uint256 lambda; // scale 1e6
        uint256 eta; // scale 1e6
        uint256 Eref; // scale 1e6
        int256 chi; // scale 1e6
        int256 omega; // rad per second, scale 1e6
        int256 phi; // phase, scale 1e6
        int256 psi; // coupling with F, scale 1e6
        uint256 mu; // scale 1e6
        uint256 nu; // scale 1e6
    }

    PriceParams public priceParams;

    /// @notice Emitted when an impact occurs and tokenomics are applied.
    event Impact(address indexed user, uint256 burned, uint256 reward, uint256 newF);
    /// @notice Emitted when the periodic tick is executed.
    event Tick(uint256 newF, uint256 newE);
    /// @notice Emitted when the core parameters are updated.
    event ParamsUpdated(
        uint256 fBase,
        uint256 fMax,
        uint256 gamma,
        uint256 alpha,
        uint256 beta,
        uint256 delta,
        uint256 kappa,
        uint256 burnBps,
        uint256 rewardPerImpact,
        uint256 epochBlocks,
        uint256 maxImpactsPerBlock,
        uint256 impactCooldownBlocks,
        uint256 Fhigh,
        uint256 surchargeFeeBps,
        bool surchargeEnabled
    );
    /// @notice Emitted when the price parameters are updated.
    event PriceParamsUpdated(
        uint256 lambda,
        uint256 eta,
        uint256 Eref,
        int256 chi,
        int256 omega,
        int256 phi,
        int256 psi,
        uint256 mu,
        uint256 nu
    );
    /// @notice Emitted when circuit breaker status changes.
    event CircuitBreakerUpdated(bool active);

    /// @notice Core parameters struct used during initialization and updates.
    struct CoreParams {
        uint256 fBase;
        uint256 fMax;
        uint256 gamma;
        uint256 alpha;
        uint256 beta;
        uint256 delta;
        uint256 kappa;
        uint256 burnBps;
        uint256 rewardPerImpact;
        uint256 epochBlocks;
        uint256 maxImpactsPerBlock;
        uint256 impactCooldownBlocks;
        uint256 Fhigh;
        uint256 surchargeFeeBps;
        bool surchargeEnabled;
    }

    /// @param rewardVault_ Reward vault address handling vested emissions.
    /// @param priceOracle_ Oracle providing reference prices (mocked).
    /// @param liquidityLens_ Liquidity metrics lens (mocked).
    /// @param initialRecipient Address receiving the genesis supply.
    /// @param initialSupply Genesis supply minted to the initial recipient.
    /// @param core Core system parameters.
    /// @param price Price model parameters.
    constructor(
        RewardVault rewardVault_,
        IPriceOracle priceOracle_,
        ILiquidityLens liquidityLens_,
        address initialRecipient,
        uint256 initialSupply,
        CoreParams memory core,
        PriceParams memory price
    ) ERC20("SARI", "SARI") ERC20Permit("SARI") {
        require(address(rewardVault_) != address(0), "Invalid vault");
        require(address(priceOracle_) != address(0), "Invalid oracle");
        require(address(liquidityLens_) != address(0), "Invalid lens");
        rewardVault = rewardVault_;
        priceOracle = priceOracle_;
        liquidityLens = liquidityLens_;

        _setCoreParams(core);
        _setPriceParams(price);

        lastTickBlock = block.number;

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(PARAM_ROLE, _msgSender());
        _grantRole(KEEPER_ROLE, _msgSender());

        if (initialRecipient != address(0) && initialSupply > 0) {
            _mint(initialRecipient, initialSupply);
        }
    }

    // ---------------------------------------------------------------------
    // External admin functions
    // ---------------------------------------------------------------------

    /// @notice Updates the core dynamic parameters controlling impacts.
    /// @param core New core parameters to set.
    function setParams(CoreParams calldata core) external onlyRole(PARAM_ROLE) {
        _setCoreParams(core);
    }

    /// @notice Updates parameters used by the internal pricing heuristic.
    /// @param params New price parameters.
    function setPriceParams(PriceParams calldata params) external onlyRole(PARAM_ROLE) {
        _setPriceParams(params);
    }

    /// @notice Updates oracle addresses used by the contract.
    /// @param priceOracle_ New price oracle address.
    /// @param liquidityLens_ New liquidity lens address.
    function setOracles(IPriceOracle priceOracle_, ILiquidityLens liquidityLens_)
        external
        onlyRole(PARAM_ROLE)
    {
        require(address(priceOracle_) != address(0), "Invalid oracle");
        require(address(liquidityLens_) != address(0), "Invalid lens");
        priceOracle = priceOracle_;
        liquidityLens = liquidityLens_;
    }

    /// @notice Grants keeper permissions to a new address.
    /// @param keeper Address receiving keeper role.
    function grantKeeper(address keeper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(KEEPER_ROLE, keeper);
    }

    /// @notice Revokes keeper permissions from an address.
    /// @param keeper Keeper address to revoke.
    function revokeKeeper(address keeper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(KEEPER_ROLE, keeper);
    }

    /// @notice Mints new tokens to the given address (admin only).
    /// @param to Recipient of the minted tokens.
    /// @param amount Amount of tokens to mint (18 decimals).
    function mint(address to, uint256 amount) external onlyRole(PARAM_ROLE) {
        _mint(to, amount);
    }

    /// @notice Pauses transfers and impact dynamics.
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses transfers and impact dynamics.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Enables or disables the circuit breaker to stop impacts.
    /// @param active True to disable impacts, false to resume.
    function circuitBreaker(bool active) external onlyRole(DEFAULT_ADMIN_ROLE) {
        circuitBroken = active;
        emit CircuitBreakerUpdated(active);
    }

    // ---------------------------------------------------------------------
    // Token overrides
    // ---------------------------------------------------------------------

    /// @inheritdoc ERC20
    function transfer(address to, uint256 value)
        public
        override
        whenNotPaused
        returns (bool)
    {
        bool success = super.transfer(to, value);
        _afterActivity(_msgSender(), to, value);
        return success;
    }

    /// @inheritdoc ERC20
    function transferFrom(address from, address to, uint256 value)
        public
        override
        whenNotPaused
        returns (bool)
    {
        bool success = super.transferFrom(from, to, value);
        _afterActivity(_msgSender(), to, value);
        return success;
    }

    /// @inheritdoc ERC20
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && surchargeEnabled && F >= Fhigh && value > 0) {
            uint256 fee = (value * surchargeFeeBps) / 10_000;
            if (fee > 0) {
                value -= fee;
                super._update(from, address(0), fee);
            }
        }
        super._update(from, to, value);
    }

    /// @inheritdoc AccessControl
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // ---------------------------------------------------------------------
    // External functions
    // ---------------------------------------------------------------------

    /// @notice Executes the periodic tick, decaying F and accruing energy.
    function tick() external nonReentrant onlyRole(KEEPER_ROLE) whenNotPaused {
        require(block.number >= lastTickBlock + epochBlocks, "Epoch not elapsed");
        F = (F * (1_000_000 - delta)) / 1_000_000;
        E += F;
        lastTickBlock = block.number;
        emit Tick(F, E);
    }

    /// @notice Returns the internal reference price in 1e6 scale.
    function refPrice() external view returns (uint256) {
        PriceParams memory params = priceParams;
        uint256 Pelec = priceOracle.latestPrice();
        (uint256 L, uint256 S, uint256 sellP) = liquidityLens.metrics();
        require(S > 0, "Invalid liquidity state");

        uint256 saturation = params.Eref == 0 ? 0 : (E * 1_000_000) / params.Eref;
        if (saturation > 1_000_000) {
            saturation = 1_000_000;
        }
        uint256 Pfloor = (params.lambda * Pelec * (1_000_000 + ((params.eta * saturation) / 1_000_000))) / 1_000_000;

        int256 angle = ((params.omega * int256(uint256(block.timestamp))) / int256(1_000_000)) + params.phi
            + ((params.psi * int256(uint256(F))) / int256(1_000_000));
        int256 oscillation = 1_000_000 + ((params.chi * _approxSin(angle)) / int256(1_000_000));
        if (oscillation < 0) {
            oscillation = 0;
        }
        uint256 Pi_osc = uint256(oscillation);

        uint256 Pi_mkt = 1_000_000 + ((params.mu * ((L * 1_000_000) / S)) / 1_000_000);
        if (sellP > 0) {
            uint256 penalty = (params.nu * sellP) / 1_000_000;
            if (penalty > Pi_mkt) {
                Pi_mkt = 0;
            } else {
                Pi_mkt -= penalty;
            }
        }

        uint256 price = ((Pfloor * Pi_osc) / 1_000_000);
        price = (price * Pi_mkt) / 1_000_000;
        return price;
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

    function _afterActivity(address actor, address to, uint256 value) internal {
        if (value == 0) {
            return;
        }
        _pumpActivity(actor, value);
        if (to != address(0)) {
            uint256 secondary = value / 10 + 1;
            _pumpActivity(to, secondary);
        }
    }

    function _pumpActivity(address user, uint256 activity) internal {
        if (user == address(0)) {
            return;
        }
        uint256 fi = freq[user];
        if (fi == 0) {
            fi = fBase;
        }
        uint256 noise = uint256(keccak256(abi.encodePacked(block.prevrandao, user, E))) % 1000;
        uint256 scaledActivity = activity / 1e12;
        if (scaledActivity > 10_000_000) {
            scaledActivity = 10_000_000;
        }
        fi = (fi * (1_000_000 - gamma)) / 1_000_000;
        fi += (alpha * scaledActivity) / 1_000_000;
        fi += (beta * F) / 1_000_000;
        fi += noise;

        if (fi >= fMax) {
            _handleImpact(user);
        } else {
            freq[user] = fi;
        }
    }

    function _handleImpact(address user) internal {
        require(!circuitBroken, "Impacts disabled");
        uint256 currentCount = impactsInBlock[block.number];
        require(currentCount < maxImpactsPerBlock, "Impact cap reached");
        require(block.number >= nextImpactBlock[user], "Impact cooldown active");

        impactsInBlock[block.number] = currentCount + 1;
        nextImpactBlock[user] = block.number + impactCooldownBlocks;
        freq[user] = fBase;
        F += kappa;

        (uint256 burned, uint256 reward) = _applyImpactTokenomics(user);
        emit Impact(user, burned, reward, F);
    }

    function _applyImpactTokenomics(address user) internal returns (uint256 burned, uint256 reward) {
        uint256 balance = balanceOf(user);
        if (balance > 0 && burnBps > 0) {
            burned = (balance * burnBps) / 10_000;
            if (burned > 0) {
                _burn(user, burned);
            }
        }
        if (rewardPerImpact > 0) {
            reward = rewardPerImpact;
            _mint(address(rewardVault), reward);
            rewardVault.credit(user, reward);
        }
    }

    function _setCoreParams(CoreParams memory core) internal {
        require(core.fBase > 0, "Invalid fBase");
        require(core.fMax > core.fBase, "Invalid fMax");
        require(core.gamma <= 1_000_000, "Gamma out of bounds");
        require(core.alpha <= 2_000_000, "Alpha out of bounds");
        require(core.beta <= 1_000_000, "Beta out of bounds");
        require(core.delta <= 500_000, "Delta out of bounds");
        require(core.burnBps <= 10_000, "Burn too high");
        require(core.epochBlocks > 0, "Epoch zero");
        require(core.maxImpactsPerBlock > 0, "Max impacts zero");
        require(core.impactCooldownBlocks > 0, "Cooldown zero");
        require(core.surchargeFeeBps <= 1_000, "Surcharge too high");

        fBase = core.fBase;
        fMax = core.fMax;
        gamma = core.gamma;
        alpha = core.alpha;
        beta = core.beta;
        delta = core.delta;
        kappa = core.kappa;
        burnBps = core.burnBps;
        rewardPerImpact = core.rewardPerImpact;
        epochBlocks = core.epochBlocks;
        maxImpactsPerBlock = core.maxImpactsPerBlock;
        impactCooldownBlocks = core.impactCooldownBlocks;
        Fhigh = core.Fhigh;
        surchargeFeeBps = core.surchargeFeeBps;
        surchargeEnabled = core.surchargeEnabled;

        emit ParamsUpdated(
            fBase,
            fMax,
            gamma,
            alpha,
            beta,
            delta,
            kappa,
            burnBps,
            rewardPerImpact,
            epochBlocks,
            maxImpactsPerBlock,
            impactCooldownBlocks,
            Fhigh,
            surchargeFeeBps,
            surchargeEnabled
        );
    }

    function _setPriceParams(PriceParams memory params) internal {
        require(params.lambda > 0, "Lambda zero");
        require(params.eta <= 1_000_000, "Eta too high");
        require(params.mu <= 5_000_000, "Mu too high");
        require(params.nu <= 5_000_000, "Nu too high");

        priceParams = params;
        emit PriceParamsUpdated(
            params.lambda,
            params.eta,
            params.Eref,
            params.chi,
            params.omega,
            params.phi,
            params.psi,
            params.mu,
            params.nu
        );
    }

    function _approxSin(int256 angle) internal pure returns (int256) {
        int256 twoPi = 6_283_185; // 2 * pi scaled by 1e6
        angle %= twoPi;
        if (angle < 0) {
            angle += twoPi;
        }
        int256 x = angle;
        int256 x2 = (x * x) / 1_000_000;
        int256 x3 = (x2 * x) / 1_000_000;
        int256 x5 = (x3 * x2) / 1_000_000;
        return x - (x3 / 6) + (x5 / 120);
    }
}
