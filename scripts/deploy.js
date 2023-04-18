// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { upgrades } = require("hardhat");
const hre = require("hardhat");

async function main() {
  const currentTimestampInSeconds = Math.round(Date.now() / 1000);
  const unlockTime = currentTimestampInSeconds + 60;

  const lockedAmount = hre.ethers.utils.parseEther("0.001");

  const Lock = await hre.ethers.getContractFactory("Lock");
  const ERC20 = await hre.ethers.getContractFactory("DrifeERCToken")
  const ERC721 = await hre.ethers.getContractFactory("GameItem")
  const FS = await hre.ethers.getContractFactory("FranchiseStaking")
  
  

  const lock = await Lock.deploy(unlockTime, { value: lockedAmount });

  await lock.deployed();

  //ERC20
  const drf = await ERC20.deploy();

  await drf.deployed()
  console.log(`ERC20: ${drf.address}`,)

  //ERC721

  const nft = await ERC721.deploy();
  await nft.deployed()

  console.log(`NFT: ${nft.address}`)

  //STaking

  const fs = await upgrades.deployProxy(FS,[drf.address, nft.address, 1, 1, 1,1,1,1,1,1])

  // drf.address, nft.address, 1, 1, 1,1,1,1,1,1
  await fs.deployed()
  console.log(`FS: ${fs.address}`)

  // await fs.initialize(drf.address, nft.address, 1, 1, 1,1,1,1,1,1)


  // console.log(
  //   `Lock with ${ethers.utils.formatEther(
  //     lockedAmount
  //   )}ETH and unlock timestamp ${unlockTime} deployed to ${lock.address}`
  // );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
