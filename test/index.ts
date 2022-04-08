// @ts-nocheck
import { expect } from "chai";
import hre, { ethers, upgrades } from "hardhat";
import SafeManagerABI from "./SafeManagerABI.json";
import AffinityABI from "./AffinityABI.json";

const SAFE_MANAGER_ADDRESS = "0xDa47a6923f3f9a9d57242a05051B03bC2d28d2A0"; // needed to replace
// SafeAffinity: 0xbb3ce748b884948625b07ee475c5e227e35e4e66
// 0x1fd455fdfd26962fce5c694bd8028d64a5ed6026
//deployerWalletAddress

async function deploy(
  this: any,
  safeManagerAddress: string,
  uniswapV2RouterO2Address: string,
  deployerWalletAddress: string | undefined
) {
  this.OwnerProxy = await ethers.getContractFactory("OwnerProxy");
  this.signer = await ethers.getSigner();
  this.signers = [...(await ethers.getSigners())];

  this.deployerSigner = this.signers[0];
  if (deployerWalletAddress) {
    // impersonate the wallet so we can sign for the owner on testnet
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [deployerWalletAddress],
    });
    this.deployerSigner = await ethers.getSigner(deployerWalletAddress);
  }
  this.safeManager = new ethers.Contract(
    safeManagerAddress,
    SafeManagerABI,
    this.deployerSigner
  );
}

describe("OwnerProxy", function () {
  before(async function () {
    await deploy.call(
      this,
      "0xDa47a6923f3f9a9d57242a05051B03bC2d28d2A0",
      "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3",
      "0x1fd455fdfd26962fce5c694bd8028d64a5ed6026"
    );
  });

  it("create a liquidity pair and then add liquidity to test the swap", async function () {
    await this.safeManager.transferAffinityOwnership(this.signer.address);
    const affinity = new ethers.Contract(
      await this.safeManager.affinityAddr(),
      AffinityABI,
      this.deployerSigner
    );
    expect(await affinity.owner()).to.eq(this.signer.address);
  });
  it("it should deploy owner proxy", async function () {
    this.ownerProxy = await this.OwnerProxy.deploy(
      "0xbb3ce748b884948625b07ee475c5e227e35e4e66",
      "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3"
    );
    const ShillXProgram = await ethers.getContractFactory("ShillXProgram");
    this.program = await ShillXProgram.deploy(
      await this.ownerProxy.getOwnerProxyTokenAddress(),
      this.ownerProxy.address
    );
    this.affinity = new ethers.Contract(
      this.ownerProxy.address,
      AffinityABI,
      this.signer
    );
  });
  it("it should have the correct token address after construction", async function () {
    expect(
      (await this.ownerProxy.getOwnerProxyTokenAddress()).toUpperCase()
    ).to.eq("0xbb3ce748b884948625b07ee475c5e227e35e4e66".toUpperCase());
  });
  it("it should have the correct uniswap addresss after contruction", async function () {
    expect(await this.ownerProxy.getOwnerProxyUniswapV2Router02Address()).to.eq(
      "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3"
    );
  });
  it("you should be able to transfer ownership from existing manager to new proxy", async function () {
    const affinity = new ethers.Contract(
      await this.ownerProxy.getOwnerProxyTokenAddress(),
      AffinityABI,
      this.signer
    );
    await affinity.transferOwnership(this.ownerProxy.address);
    expect(await this.affinity.owner()).to.eq(this.ownerProxy.address);
  });
  it("you should be able to set permission to another wallet", async function () {
    await this.ownerProxy.setOwnerProxyPermission(
      this.signers[1].address,
      await this.ownerProxy.OP_EXTERNAL_PERMISSION()
    );
    expect(
      await this.ownerProxy.getOwnerProxyPermissions(this.signers[1].address)
    ).to.eq(await this.ownerProxy.OP_EXTERNAL_PERMISSION());
  });
  it("should prevent unauthorized access", async function () {
    const maliciousOwnerProxy = this.OwnerProxy.connect(this.signers[2]).attach(
      this.ownerProxy.address
    );
    await expect(
      maliciousOwnerProxy.setOwnerProxyPermission(this.signers[1].address, 0)
    ).to.revertedWith("OP: unauthorized");
  });
  it("should allow you to remove permissions", async function () {
    await this.ownerProxy.setOwnerProxyPermission(this.signers[1].address, 0);
    expect(
      await this.ownerProxy.getOwnerProxyPermissions(this.signers[1].address)
    ).to.eq(0);
  });
  /**
   * The following test fail because there isn't a pair or liquidity pool on testnet.
   * Please create a liquidity pool so I can complete the last two tests.
   */
  it("program should not be excluded by default", async function () {
    expect(await this.program.swap({ value: ethers.utils.parseEther("1.0") }))
      .to.be.false;
  });
  it("should be excluded from taxation when given permission", async function () {
    await this.ownerProxy.setOwnerProxyPermission(
      this.program.address,
      await this.ownerProxy.OP_EXTERNAL_PERMISSION()
    );
    expect(await this.program.swap({ value: ethers.utils.parseEther("1.0") }))
      .to.be.true;
  });
});
