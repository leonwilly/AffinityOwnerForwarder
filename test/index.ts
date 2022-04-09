// @ts-nocheck
import { expect } from "chai";
import hre, { ethers, upgrades } from "hardhat";

async function deploy(this: any, uniswapV2RouterO2Address: string) {
  this.OwnerProxy = await ethers.getContractFactory("OwnerProxy");
  this.signer = await ethers.getSigner();
  this.signers = [...(await ethers.getSigners())];
  this.SafeAffinity = await ethers.getContractFactory("SafeAffinity");
  this.safeAffinity = await this.SafeAffinity.deploy(
    this.signer.address,
    uniswapV2RouterO2Address
  );
  this.SafeMaster = await ethers.getContractFactory("SafeMaster");
  this.safeMaster = await this.SafeMaster.deploy(this.safeAffinity.address);
  const router = await ethers.getContractAt(
    "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol:IUniswapV2Router02",
    uniswapV2RouterO2Address
  );
  const factory = await ethers.getContractAt(
    "IUniswapV2Factory",
    await router.factory()
  );
  await factory.createPair(this.signer.address, await router.WETH());
  // transfer the balance to the generated wallet loaded with ETH
  await this.safeAffinity.approve(
    router.address,
    await this.safeAffinity.balanceOf(this.signer.address)
  );
  await router.addLiquidityETH(
    this.safeAffinity.address,
    await this.safeAffinity.balanceOf(this.signer.address),
    0,
    0,
    this.signer.address,
    ethers.constants.MaxInt256,
    { value: ethers.utils.parseEther("100") }
  );
  await this.safeAffinity.transferOwnership(this.safeMaster.address);

  this.ownerProxy = await this.OwnerProxy.deploy(
    this.safeAffinity.address,
    uniswapV2RouterO2Address
  );
  const ShillXProgram = await ethers.getContractFactory("ShillXProgram");
  this.program = await ShillXProgram.deploy(
    await this.ownerProxy.getOwnerProxyTokenAddress(),
    this.ownerProxy.address
  );
}

describe("OwnerProxy", function () {
  before(async function () {
    await deploy.call(this, "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3");
  });
  it("it should have the correct token address after construction", async function () {
    expect(await this.ownerProxy.getOwnerProxyTokenAddress()).to.eq(
      this.safeAffinity.address
    );
  });
  it("it should have the correct uniswap addresss after contruction", async function () {
    expect(await this.ownerProxy.getOwnerProxyUniswapV2Router02Address()).to.eq(
      "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3"
    );
  });
  it("you should be able to transfer ownership from existing manager to new proxy", async function () {
    await this.safeMaster.transferAffinityOwnership(this.ownerProxy.address);
    expect(await this.safeAffinity.owner()).to.eq(this.ownerProxy.address);
  });
  it("you should be able to set permission to another wallet", async function () {
    await this.ownerProxy.modifyOwnerProxyPermission(
      this.signers[1].address,
      await this.ownerProxy.OP_EXTERNAL_PERMISSION(),
      0
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
      maliciousOwnerProxy.modifyOwnerProxyPermission(
        this.signers[1].address,
        0,
        0
      )
    ).to.revertedWith("OP: unauthorized");
  });
  it("should allow you to remove permissions", async function () {
    await this.ownerProxy.modifyOwnerProxyPermission(
      this.signers[1].address,
      0,
      await this.ownerProxy.OP_EXTERNAL_PERMISSION()
    );
    expect(
      await this.ownerProxy.getOwnerProxyPermissions(this.signers[1].address)
    ).to.eq(0);
  });
  it("program should not be excluded by default", async function () {
    await expect(
      this.program.swap({ value: ethers.utils.parseEther(".1") })
    ).to.be.revertedWith("OP: unauthorized");
  });
  it("should be excluded from taxation when given permission", async function () {
    await this.ownerProxy.modifyOwnerProxyPermission(
      this.program.address,
      await this.ownerProxy.OP_EXTERNAL_PERMISSION(),
      0
    );
    await expect(
      this.program.swap({ value: ethers.utils.parseEther(".1") })
    ).to.not.be.revertedWith("OP: Unauthorized");
  });
});
