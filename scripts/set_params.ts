import { ethers } from "hardhat";

async function main() {
  const sariAddress = process.env.SARI_ADDRESS || process.argv[2];
  if (!sariAddress) {
    throw new Error("SARI address must be provided as env SARI_ADDRESS or argv[2]");
  }

  const sari = await ethers.getContractAt("SARI", sariAddress);

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

  const tx = await sari.setParams(coreParams);
  await tx.wait();
  const priceTx = await sari.setPriceParams(priceParams);
  await priceTx.wait();

  console.log("Parameters initialized for SARI at", sariAddress);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
