// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import hre, { ethers } from "hardhat";
import SafeManagerABI from "../test/SafeManagerABI.json";
import AffinityABI from "../test/AffinityABI.json";

async function deploy(
  this: any,
  safeManagerAddress: string,
  uniswapV2RouterO2Address: string,
  deployerWalletAddress?: string
) {
  this.OwnerProxy = await ethers.getContractFactory("OwnerProxy");
  this.signer = await ethers.getSigner();
  this.signers = [...(await ethers.getSigners())];
  this.ownerProxy = await this.OwnerProxy.deploy(
    "0xbb3ce748b884948625b07ee475c5e227e35e4e66",
    uniswapV2RouterO2Address
  );
  let deployerSigner = this.signers[0];
  if (deployerWalletAddress) {
    // impersonate the wallet so we can sign for the owner on testnet
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [deployerWalletAddress],
    });
    deployerSigner = await ethers.getSigner(deployerWalletAddress);
  }
  this.safeManager = new ethers.Contract(
    safeManagerAddress,
    SafeManagerABI,
    deployerSigner
  );
  this.affinity = new ethers.Contract(
    this.ownerProxy.address,
    AffinityABI,
    this.signer
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
  console.log(`OwnerProxy deployed at ${ctx.ownerProxy}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
