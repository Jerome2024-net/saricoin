# SARI – Speculative Adaptive Resonance Instrument

SARI is an experimental ERC-20 token that models a cyclic market dynamic. Holders accumulate "frequency" based on transfer
activity; once their local oscillation crosses a threshold the protocol triggers an **impact** that burns part of their balance,
energises the global resonance variable `F`, and optionally routes freshly minted rewards to a vesting vault. A keeper maintains
the system with periodic `tick()` calls that dissipate energy into an accumulated buffer `E`, and a lightweight pricing heuristic
derives an indicative reference price from mocked oracle feeds.

The repository ships as a complete Hardhat + TypeScript project with extensive test coverage, mocks for all external
integration points, and deployment utilities suitable for local experimentation.

## Key Concepts

- **Cyclic activity tracking** – user transfers update their personal frequency `freq[user]` in 1e6 precision. Impacts reset the
  user to `fBase`, increase the resonance `F`, and apply burn and reward tokenomics.
- **Anti-manipulation guard rails** – per-block impact caps, per-user cooldowns, a circuit breaker, dynamic surcharge fees when `F`
  overheats, and pausability mitigate abusive behaviour.
- **Reward vesting vault** – the `RewardVault` contract escrows mint-on-impact rewards and releases them linearly over 30 days.
- **Reference pricing** – `refPrice()` mixes oracle data with oscillatory premiums using an on-chain sine approximation to yield
  a pseudo price in 1e6 precision.
- **Role separation** – the deployer receives `DEFAULT_ADMIN_ROLE`, `PARAM_ROLE`, and `KEEPER_ROLE` for governance, parameter
  management, and upkeep tasks respectively.

## Contract Topology

```
contracts/
  SARI.sol                   Core ERC20 logic with cyclic impact model
  RewardVault.sol            Linear vesting vault for impact rewards
  interfaces/
    IPriceOracle.sol         Mockable oracle returning prices in 1e8 precision
    ILiquidityLens.sol       Liquidity metrics provider (L, S, sell pressure)
  mocks/
    PriceOracleMock.sol      Simple configurable price feed for tests
    LiquidityLensMock.sol    Mock liquidity metrics
    ImpactHelper.sol         Test helper batching transfers in a single tx
```

SARI relies on OpenZeppelin's `ERC20`, `ERC20Permit`, `Ownable2Step`, `Pausable`, `ReentrancyGuard`, and `AccessControl`
primitives. The reward vault and mocks are pure Solidity contracts with no external dependencies beyond OpenZeppelin.

## Default Parameter Set

The deployment script (`scripts/deploy_sari.ts`) configures the protocol with the following values:

| Parameter | Value | Units |
|-----------|-------|-------|
| `fBase` | 1,000,000 | frequency (1e6) |
| `fMax` | 10,000,000 | frequency (1e6) |
| `gamma` | 50,000 | ppm (1e6 base) |
| `alpha` | 800,000 | ppm (1e6 base) |
| `beta` | 100,000 | ppm (1e6 base) |
| `delta` | 100,000 | ppm (1e6 base) |
| `kappa` | 300,000 | resonance impulse (1e6) |
| `burnBps` | 100 | basis points (1e4) |
| `rewardPerImpact` | 0 | 18-decimal tokens |
| `epochBlocks` | 200 | blocks |
| `maxImpactsPerBlock` | 5 | impacts |
| `impactCooldownBlocks` | 40 | blocks |
| `Fhigh` | 50,000,000 | resonance (1e6) |
| `surchargeFeeBps` | 25 | basis points (1e4) |

Price parameters are initialised with moderate oscillation coefficients, oracle mocks default to a $1.00 feed (1e8 precision),
and the liquidity lens reports unit liquidity/supply with no sell pressure.

## Scripts

- `scripts/deploy_sari.ts` – deploys oracle mocks, the reward vault, and the SARI token with default parameters, then wires the
  vault to the token.
- `scripts/set_params.ts` – updates the SARI contract with the baseline parameter set. Provide the target address via the
  `SARI_ADDRESS` environment variable or as the first positional argument.

Run a script with Hardhat:

```bash
npx hardhat run scripts/deploy_sari.ts
SARI_ADDRESS=0xTokenAddress npx hardhat run scripts/set_params.ts
```

## Testing & Coverage

Install dependencies (Node.js 18+ recommended) and execute the TypeScript test suites:

```bash
npm install
npm run build
npm test
npm run coverage
```

The tests cover:

- Impact emission, burn mechanics, and reward vault accrual
- Keeper `tick()` decay behaviour
- Parameter updates, pausing, and circuit breaker logic
- Anti-abuse restrictions (impact cap, cooldown, surcharge)
- Reward vault vesting and claims
- Reference pricing responsiveness to oracle inputs

## Security Notes

- The circuit breaker, pausing, and parameter management functions should be delegated to multisig or hardware wallets.
- Oracle and liquidity lens addresses are mocks in this repository; real deployments must integrate robust feeds.
- Reward minting is disabled by default (`rewardPerImpact = 0`). Carefully review the economic implications before enabling.
- Impact logic leverages pseudo-random noise derived from `block.prevrandao` and should not be considered tamper-proof.
