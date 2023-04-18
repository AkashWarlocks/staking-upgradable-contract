const { ethers, upgrades } = require("hardhat");
const hre = require("hardhat");

async function main() {
    const fsV1Address = "0x7a2088a1bFc9d81c55368AE168C2C02570cB814F"

    const FSV2 = await ethers.getContractFactory("FranchiseStakingV2");

    const upgrade = await upgrades.upgradeProxy(fsV1Address, FSV2);

    const tokenAddress = await upgrade.getTokenAddress()

    console.log(`token address: ${tokenAddress}`)


}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});