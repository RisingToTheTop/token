// import dependencies
const dotenv = require("dotenv");
dotenv.config(); // setup dotenv

//this scripts is for mumbai Chain
const { ethers } = require("hardhat");
const srcAddr = process.env.CONTRACT_ADDRESS;

async function main() {
  const contractFactory = await ethers.getContractFactory("WAGMIMusicToken1155");
  const contract = await contractFactory.attach(srcAddr);
  let tx = await contract.license("0xAd84F848Efb88C7D2aC9e0e8181861a995041D71", true);
  await tx.wait();
  console.log(`✅ [${hre.network.name}] createAlbum(Struct)`)
  console.log(` tx: ${tx.transactionHash}`)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });