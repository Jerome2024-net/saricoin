# SariCoin Stablecoin

SariCoin (**SARI**) is an ERC-20 compatible stablecoin aimed at tracking the value of one United States Dollar. The contract is built on top of OpenZeppelin primitives to provide audited token, access-control, and pausability features. Governance wallets with the correct roles can mint and burn supply in order to keep the token fully collateralised.

## Features

- **Role based access control** – an administrator can delegate minting and pausing permissions to other wallets.
- **Pausable transfers** – minting, burning, and transfers can be halted in emergency scenarios.
- **Configurable initial supply** – the constructor mints an optional starting supply to a treasury wallet.
- **Deployment script and tests** – Hardhat scripts show how to deploy and validate the contract.

## Project Structure

```
contracts/        Solidity smart contracts
scripts/          Hardhat deployment utilities
test/             Mocha/Chai based unit tests
hardhat.config.js Hardhat configuration file
```

## Getting Started

1. Install dependencies (requires Node.js 18+):
   ```bash
   npm install
   ```
2. Compile the contracts:
   ```bash
   npx hardhat compile
   ```
3. Run the test suite:
   ```bash
   npx hardhat test
   ```
4. Deploy to a local Hardhat network:
   ```bash
   npx hardhat run scripts/deploy.js
   ```

## Contract Constructor Arguments

```solidity
constructor(address admin, address treasury, uint256 initialSupply)
```

- `admin` – receives the admin, minter, and pauser roles.
- `treasury` – receives the optional initial supply.
- `initialSupply` – amount of tokens to mint (use 18 decimals).

## Security Considerations

- Always secure the admin wallet with hardware-backed key management.
- Review minting policies to ensure the circulating supply remains fully backed by reserves.
- Pause functionality should only be used to react to security incidents or severe market stress.
