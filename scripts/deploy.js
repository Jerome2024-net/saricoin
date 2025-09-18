const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  const treasury = deployer.address;

  const initialSupply = ethers.parseUnits("1000000", 18);

  const sariCoin = await ethers.deployContract("SariCoin", [deployer.address, treasury, initialSupply]);
  await sariCoin.waitForDeployment();

  console.log(`SariCoin deployed to: ${await sariCoin.getAddress()}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
