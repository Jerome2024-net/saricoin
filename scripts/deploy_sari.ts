import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();

  const PriceOracleMock = await ethers.getContractFactory("PriceOracleMock");
  const priceOracle = await PriceOracleMock.deploy(100_000_000n);
  await priceOracle.waitForDeployment();

  const LiquidityLensMock = await ethers.getContractFactory("LiquidityLensMock");
  const liquidityLens = await LiquidityLensMock.deploy(1_000_000, 1_000_000, 0);
  await liquidityLens.waitForDeployment();

  const RewardVault = await ethers.getContractFactory("RewardVault");
  const rewardVault = await RewardVault.deploy(deployer.address);
  await rewardVault.waitForDeployment();

  const coreParams = {
    fBase: 1_000_000,
    fMax: 10_000_000,
    gamma: 50_000,
    alpha: 800_000,
    beta: 100_000,
    delta: 100_000,
    kappa: 300_000,
    burnBps: 100,
    rewardPerImpact: 0n,
    epochBlocks: 200,
    maxImpactsPerBlock: 5,
    impactCooldownBlocks: 40,
    Fhigh: 50_000_000,
    surchargeFeeBps: 25,
    surchargeEnabled: true,
  };

  const priceParams = {
    lambda: 1_000_000,
    eta: 100_000,
    Eref: 1_000_000,
    chi: 100_000n,
    omega: 10_000n,
    phi: 0n,
    psi: 1_000n,
    mu: 500_000,
    nu: 200_000,
  };

  const SARI = await ethers.getContractFactory("SARI");
  const sari = await SARI.deploy(
    rewardVault.getAddress(),
    priceOracle.getAddress(),
    liquidityLens.getAddress(),
    deployer.address,
    ethers.parseEther("1000000"),
    coreParams,
    priceParams
  );
  await sari.waitForDeployment();

  await rewardVault.configureSari(await sari.getAddress());

  console.log("SARI deployed to:", await sari.getAddress());
  console.log("RewardVault deployed to:", await rewardVault.getAddress());
  console.log("PriceOracle mock deployed to:", await priceOracle.getAddress());
  console.log("Liquidity lens mock deployed to:", await liquidityLens.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
