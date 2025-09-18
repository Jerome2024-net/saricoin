const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SariCoin", function () {
  async function deployFixture() {
    const [admin, treasury, alice] = await ethers.getSigners();
    const initialSupply = ethers.parseUnits("1000000", 18);

    const SariCoin = await ethers.getContractFactory("SariCoin");
    const sari = await SariCoin.deploy(admin.address, treasury.address, initialSupply);
    await sari.waitForDeployment();

    return { sari, admin, treasury, alice, initialSupply };
  }

  it("sets token metadata", async function () {
    const { sari } = await deployFixture();

    expect(await sari.name()).to.equal("Sari USD");
    expect(await sari.symbol()).to.equal("SARI");
    expect(await sari.decimals()).to.equal(18);
  });

  it("assigns admin, minter and pauser roles to the admin", async function () {
    const { sari, admin } = await deployFixture();

    const adminRole = await sari.DEFAULT_ADMIN_ROLE();
    const minterRole = await sari.MINTER_ROLE();
    const pauserRole = await sari.PAUSER_ROLE();

    expect(await sari.hasRole(adminRole, admin.address)).to.be.true;
    expect(await sari.hasRole(minterRole, admin.address)).to.be.true;
    expect(await sari.hasRole(pauserRole, admin.address)).to.be.true;
  });

  it("mints the initial supply to the treasury", async function () {
    const { sari, treasury, initialSupply } = await deployFixture();

    expect(await sari.balanceOf(treasury.address)).to.equal(initialSupply);
  });

  it("allows an authorized minter to mint", async function () {
    const { sari, admin, alice } = await deployFixture();

    const amount = ethers.parseUnits("2500", 18);
    await expect(sari.connect(admin).mint(alice.address, amount))
      .to.emit(sari, "Transfer")
      .withArgs(ethers.ZeroAddress, alice.address, amount);

    expect(await sari.balanceOf(alice.address)).to.equal(amount);
  });

  it("blocks minting while paused", async function () {
    const { sari, admin, alice } = await deployFixture();

    await sari.connect(admin).pause();
    await expect(
      sari.connect(admin).mint(alice.address, ethers.parseUnits("1", 18))
    ).to.be.revertedWithCustomError(sari, "EnforcedPause");
  });

  it("reverts when constructed with zero addresses", async function () {
    const [admin, treasury] = await ethers.getSigners();
    const SariCoin = await ethers.getContractFactory("SariCoin");

    await expect(
      SariCoin.deploy(ethers.ZeroAddress, treasury.address, 0)
    ).to.be.revertedWith("SariCoin: admin is zero address");

    await expect(
      SariCoin.deploy(admin.address, ethers.ZeroAddress, 0)
    ).to.be.revertedWith("SariCoin: treasury is zero address");
  });
});
