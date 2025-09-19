import { expect } from "chai";
import { ethers } from "hardhat";
import { ContractTransactionResponse } from "ethers";

describe("SARI.behavior", () => {
  const initialSupply = ethers.parseEther("1000000");

  const coreParams = () => ({
    fBase: 1_000_000,
    fMax: 10_000_000,
    gamma: 50_000,
    alpha: 800_000,
    beta: 100_000,
    delta: 100_000,
    kappa: 300_000,
    burnBps: 100,
    rewardPerImpact: ethers.parseEther("1"),
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
    chi: 100_000n,
    omega: 10_000n,
    phi: 0n,
    psi: 1_000n,
    mu: 500_000,
    nu: 200_000,
  });

  async function deployFixture() {
    const [deployer, user, keeper] = await ethers.getSigners();

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
      initialSupply,
      coreParams(),
      priceParams()
    );
    await sari.waitForDeployment();

    await vault.configureSari(await sari.getAddress());

    await sari.grantKeeper(keeper.address);

    return { sari, vault, oracle, lens, deployer, user, keeper };
  }

  async function triggerImpact(
    sari: any,
    from: any,
    to: string,
    amount = ethers.parseEther("1000")
  ): Promise<ContractTransactionResponse> {
    return sari.connect(from).transfer(to, amount);
  }

  it("emits impact, burns balance, and increases F", async () => {
    const { sari, deployer, user, vault } = await deployFixture();
    await sari.connect(deployer).transfer(user.address, ethers.parseEther("100"));

    const preBalance = await sari.balanceOf(user.address);
    const tx = await triggerImpact(sari, user, deployer.address, ethers.parseEther("100"));
    await expect(tx).to.emit(sari, "Impact");

    const postBalance = await sari.balanceOf(user.address);
    expect(postBalance).to.be.lt(preBalance);
    expect(await sari.freq(user.address)).to.equal(1_000_000);
    expect(await sari.F()).to.equal(300_000);

    const vaultBalance = await sari.balanceOf(await vault.getAddress());
    expect(vaultBalance).to.be.gt(0n);
  });

  it("executes tick after epoch and accumulates energy", async () => {
    const { sari, keeper, deployer } = await deployFixture();
    await triggerImpact(sari, deployer, keeper.address);

    const epoch = await sari.epochBlocks();
    await ethers.provider.send("hardhat_mine", [ethers.toQuantity(epoch)]);

    const tx = await sari.connect(keeper).tick();
    await expect(tx).to.emit(sari, "Tick");

    const F = await sari.F();
    const E = await sari.E();
    expect(F).to.be.gt(0);
    expect(E).to.be.gte(F);
  });

  it("updates parameters via setParams", async () => {
    const { sari } = await deployFixture();
    const params = {
      fBase: 900_000,
      fMax: 11_000_000,
      gamma: 40_000,
      alpha: 700_000,
      beta: 90_000,
      delta: 80_000,
      kappa: 400_000,
      burnBps: 200,
      rewardPerImpact: ethers.parseEther("2"),
      epochBlocks: 100,
      maxImpactsPerBlock: 7,
      impactCooldownBlocks: 35,
      Fhigh: 60_000_000,
      surchargeFeeBps: 20,
      surchargeEnabled: false,
    };

    await expect(sari.setParams(params)).to.emit(sari, "ParamsUpdated");
    expect(await sari.burnBps()).to.equal(200);
    expect(await sari.rewardPerImpact()).to.equal(ethers.parseEther("2"));
    expect(await sari.surchargeEnabled()).to.equal(false);
  });

  it("computes a positive reference price and reacts to oracles", async () => {
    const { sari, oracle, lens } = await deployFixture();
    const basePrice = await sari.refPrice();
    expect(basePrice).to.be.gt(0);

    await oracle.setPrice(150_000_000);
    await lens.setMetrics(2_000_000, 500_000, 10_000);
    const newPrice = await sari.refPrice();
    expect(newPrice).to.be.gt(basePrice);
  });
});
