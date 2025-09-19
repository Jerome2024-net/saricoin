import { expect } from "chai";
import { ethers } from "hardhat";

describe("SARI.antiabuse", () => {
  const coreParams = () => ({
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
    const [deployer, user, recipient] = await ethers.getSigners();
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
      ethers.parseEther("1000000"),
      coreParams(),
      priceParams()
    );
    await sari.waitForDeployment();
    await vault.configureSari(await sari.getAddress());
    return { sari, deployer, user, recipient, vault };
  }

  function overrideCore(base: any, overrides: Record<string, any>) {
    return { ...base, ...overrides };
  }

  it("enforces max impacts per block", async () => {
    const { sari, deployer, recipient } = await deployFixture();
    const ImpactHelper = await ethers.getContractFactory("ImpactHelper");
    const helper = await ImpactHelper.deploy();

    const params = overrideCore(coreParams(), { maxImpactsPerBlock: 1 });
    await sari.setParams(params);

    const helperAddr = await helper.getAddress();
    await sari.transfer(helperAddr, ethers.parseEther("1000"));

    await expect(
      helper.doubleTransfer(await sari.getAddress(), recipient.address, ethers.parseEther("400"))
    ).to.be.revertedWith("Impact cap reached");
  });

  it("respects cooldown before consecutive impacts", async () => {
    const { sari, deployer, user } = await deployFixture();
    await sari.transfer(user.address, ethers.parseEther("200"));

    await expect(sari.connect(user).transfer(deployer.address, ethers.parseEther("150")))
      .to.emit(sari, "Impact");

    await expect(
      sari.connect(user).transfer(deployer.address, ethers.parseEther("150"))
    ).to.be.revertedWith("Impact cooldown active");
  });

  it("blocks impacts when circuit breaker is enabled", async () => {
    const { sari, deployer, user } = await deployFixture();
    await sari.transfer(user.address, ethers.parseEther("150"));
    await sari.circuitBreaker(true);

    await expect(
      sari.connect(user).transfer(deployer.address, ethers.parseEther("120"))
    ).to.be.revertedWith("Impacts disabled");
  });

  it("applies surcharge burn when F exceeds threshold", async () => {
    const { sari, deployer, recipient } = await deployFixture();
    const params = overrideCore(coreParams(), { Fhigh: 100_000, surchargeFeeBps: 100 });
    await sari.setParams(params);

    await expect(sari.transfer(recipient.address, ethers.parseEther("100")))
      .to.emit(sari, "Impact");

    const preBalance = await sari.balanceOf(deployer.address);
    await sari.transfer(recipient.address, ethers.parseEther("10"));
    const postBalance = await sari.balanceOf(deployer.address);

    const diff = preBalance - postBalance;
    expect(diff).to.be.gt(ethers.parseEther("10"));
  });
});
