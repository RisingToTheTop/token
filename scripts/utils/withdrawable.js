// import dependencies
const dotenv = require("dotenv");
dotenv.config(); // setup dotenv

//this scripts is for mumbai Chain
const { ethers } = require("hardhat");
const srcAddr = process.env.CONTRACT_ADDRESS;

async function main() {
  const contractFactory = await ethers.getContractFactory("WAGMIMusicToken1155");
  const contract = await contractFactory.attach(srcAddr);
  let value = await contract.withdrawable()
  console.log(`✅ [${hre.network.name}] withdrawable()`)
  console.log(`distribution:${ethers.utils.formatEther(value[0])} withdrawable:${ethers.utils.formatEther(value[1])}`)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });