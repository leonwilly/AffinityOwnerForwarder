// @ts-nocheck
import { expect } from "chai";
import hre, { ethers, upgrades } from "hardhat";

async function deploy(this: any, uniswapV2RouterO2Address: string) {
  this.OwnerForwarder = await ethers.getContractFactory("OwnerForwarder");
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
  // const factory = await ethers.getContractAt(
  //   "IUniswapV2Factory",
  //   await router.factory()
  // );
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

  this.ownerForwarder = await this.OwnerForwarder.deploy(
    this.safeAffinity.address,
    uniswapV2RouterO2Address
  );
  const ShillXProgram = await ethers.getContractFactory("ShillXProgram");
  this.program = await ShillXProgram.deploy(
    await this.ownerForwarder.getOwnerForwarderTokenAddress(),
    this.ownerForwarder.address
  );
  this.affinityProxy = this.safeAffinity.attach(this.ownerForwarder.address);
}

describe("OwnerForwarder", function () {
  before(async function () {
    await deploy.call(this, "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3");
  });
  it("it should have the correct token address after construction", async function () {
    expect(await this.ownerForwarder.getOwnerForwarderTokenAddress()).to.eq(
      this.safeAffinity.address
    );
  });
  it("it should have the correct uniswap addresss after contruction", async function () {
    expect(
      await this.ownerForwarder.getOwnerForwarderUniswapV2Router02Address()
    ).to.eq("0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3");
  });
  it("you should be able to transfer ownership from existing manager to new proxy", async function () {
    await this.safeMaster.transferAffinityOwnership(
      this.ownerForwarder.address
    );
    expect(await this.safeAffinity.owner()).to.eq(this.ownerForwarder.address);
  });
  it("you should be able to set permission to another wallet", async function () {
    await this.ownerForwarder.modifyOwnerForwarderPermission(
      this.signers[1].address,
      await this.ownerForwarder.OF_EXTERNAL_PERMISSION(),
      0
    );
    expect(
      await this.ownerForwarder.getOwnerForwarderPermissions(
        this.signers[1].address
      )
    ).to.eq(await this.ownerForwarder.OF_EXTERNAL_PERMISSION());
  });
  it("should prevent unauthorized access", async function () {
    const maliciousOwnerForwarder = this.OwnerForwarder.connect(
      this.signers[2]
    ).attach(this.ownerForwarder.address);
    await expect(
      maliciousOwnerForwarder.modifyOwnerForwarderPermission(
        this.signers[1].address,
        0,
        0
      )
    ).to.revertedWith("OP: unauthorized");
  });
  it("should allow you to remove permissions", async function () {
    await this.ownerForwarder.modifyOwnerForwarderPermission(
      this.signers[1].address,
      0,
      await this.ownerForwarder.OF_EXTERNAL_PERMISSION()
    );
    expect(
      await this.ownerForwarder.getOwnerForwarderPermissions(
        this.signers[1].address
      )
    ).to.eq(0);
  });
  it("program should not be excluded by default", async function () {
    await expect(
      this.program.swap({ value: ethers.utils.parseEther(".1") })
    ).to.be.revertedWith("OP: unauthorized");
  });
  it("should be excluded from taxation when given permission", async function () {
    await this.ownerForwarder.modifyOwnerForwarderPermission(
      this.program.address,
      await this.ownerForwarder.OF_EXTERNAL_PERMISSION(),
      0
    );
    await expect(
      this.program.swap({ value: ethers.utils.parseEther(".1") })
    ).to.not.be.revertedWith("OP: Unauthorized");
  });
  it("after successful swap liquidity pair should be set back to taxed", async function () {
    expect(
      await this.affinityProxy.getIsFeeExempt(await this.safeAffinity.pair())
    ).to.be.false;
  });
});
