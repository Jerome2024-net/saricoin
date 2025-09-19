import { expect } from "chai";
import { ethers } from "hardhat";

describe("RewardVault", () => {
  const coreParams = () => ({
    fBase: 1_000_000,
    fMax: 10_000_000,
    gamma: 50_000,
    alpha: 800_000,
    beta: 100_000,
    delta: 100_000,
    kappa: 300_000,
    burnBps: 100,
    rewardPerImpact: ethers.parseEther("5"),
    epochBlocks: 200,
    maxImpactsPerBlock: 5,
    impactCooldownBlocks: 40,
    Fhigh: 50_000_000,
    surchargeFeeBps: 25,
    surchargeEnabled: false,
  });

  const priceParams = () => ({
    lambda: 1_000_000,
    eta: 100_000,
    Eref: 1_000_000,
    chi: 50_000n,
    omega: 8_000n,
    phi: 0n,
    psi: 2_000n,
    mu: 400_000,
    nu: 150_000,
  });

  async function deployFixture() {
    const [deployer, user] = await ethers.getSigners();
    const PriceOracleMock = await ethers.getContractFactory("PriceOracleMock");
    const oracle = await PriceOracleMock.deploy(100_000_000n);
    await oracle.waitForDeployment();
    const LiquidityLensMock = await ethers.getContractFactory("LiquidityLensMock");
    const lens = await LiquidityLensMock.deploy(1_000_000, 1_000_000, 0);
    await lens.waitForDeployment();
    const RewardVault = await ethers.getContractFactory("RewardVault");
    const vault = await RewardVault.deploy(deployer.address);
    await vault.waitForDeployment();
    const SARI = await ethers.getContractFactory("SARI");
    const sari = await SARI.deploy(
      vault.getAddress(),
      oracle.getAddress(),
      lens.getAddress(),
      deployer.address,
      ethers.parseEther("500000"),
      coreParams(),
      priceParams()
    );
    await sari.waitForDeployment();
    await vault.configureSari(await sari.getAddress());
    return { sari, vault, deployer, user };
  }

  it("credits rewards on impact and releases after vesting", async () => {
    const { sari, vault, deployer, user } = await deployFixture();
    await sari.transfer(user.address, ethers.parseEther("200"));

    await expect(sari.connect(user).transfer(deployer.address, ethers.parseEther("150")))
      .to.emit(sari, "Impact");

    const entries = await vault.vestingEntries(user.address);
    expect(entries.length).to.equal(1);
    expect(entries[0].amount).to.equal(ethers.parseEther("5"));

    const claimableBefore = await vault.claimable(user.address);
    expect(claimableBefore).to.equal(0n);

    await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60]);
    await ethers.provider.send("evm_mine", []);

    const claimableAfter = await vault.claimable(user.address);
    expect(claimableAfter).to.equal(ethers.parseEther("5"));

    const balanceBefore = await sari.balanceOf(user.address);
    await expect(vault.connect(user).claim()).to.emit(sari, "Transfer");
    const balanceAfter = await sari.balanceOf(user.address);
    expect(balanceAfter - balanceBefore).to.equal(ethers.parseEther("5"));
  });

  it("prevents double configuration", async () => {
    const { vault, sari } = await deployFixture();
    await expect(vault.configureSari(await sari.getAddress())).to.be.revertedWith("Already configured");
  });
});
