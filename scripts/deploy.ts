// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import hre, { ethers } from "hardhat";

async function deploy(
  this: any,
  safeMasterAaddress: string,
  uniswapV2RouterO2Address: string
) {
  this.OwnerProxy = await ethers.getContractFactory("OwnerProxy");
  this.SafeMaster = await ethers.getContractFactory("");
  this.safeMaster = await ethers.getContractAt(
    "SafeMaster",
    safeMasterAaddress
  );
  this.ownerProxy = await this.OwnerProxy.deploy(
    await this.safeMaster.getAffinityTokenAddress(),
    uniswapV2RouterO2Address
  );
}

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const ctx: any = {};
  await deploy.call(
    ctx,
    "0x670272316237229b82E40B42B9f3Faf43e967B39",
    "0x10ED43C718714eb63d5aA57B78B54704E256024E"
  );
  await ctx.safeMaster.transferAffinityOwnership(ctx.ownerProxy.address);
  console.log(`OwnerProxy deployed at ${ctx.ownerProxy}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
