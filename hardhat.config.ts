import * as dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "solidity-coverage";

dotenv.config();

const sharedDeployerKey = process.env.DEPLOYER_PRIVATE_KEY;

const sepoliaAccounts = process.env.SEPOLIA_PRIVATE_KEY
  ? [process.env.SEPOLIA_PRIVATE_KEY]
  : sharedDeployerKey
    ? [sharedDeployerKey]
    : [];

const bscTestnetAccounts = process.env.BSC_TESTNET_PRIVATE_KEY
  ? [process.env.BSC_TESTNET_PRIVATE_KEY]
  : sharedDeployerKey
    ? [sharedDeployerKey]
    : [];

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  networks: {
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: sepoliaAccounts,
    },
    bsctestnet: {
      url: process.env.BSC_TESTNET_RPC_URL || process.env.BSC_RPC_URL || "",
      chainId: 97,
      accounts: bscTestnetAccounts,
    },
  },
  mocha: {
    timeout: 400000,
  },
};

export default config;
