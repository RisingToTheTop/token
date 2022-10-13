// import dependencies
const dotenv = require("dotenv");
dotenv.config(); // setup dotenv

//this scripts is for mumbai Chain
const { ethers } = require("hardhat");
const srcAddr = "0xddeDDff43B8a48C3726fF744096aC2c083473850";
// const tokenAddr = "0x192D1024424EB9f4F4090a7c05316AA8281ECaa5";

async function main() {

  const contractFactory = await ethers.getContractFactory("ExchangeAgent");
  const contract = await contractFactory.attach(srcAddr);
  let tx = await contract.setMigration(1,7);
  await tx.wait();
  tx = await contract.exchange(1,1,"0xAd84F848Efb88C7D2aC9e0e8181861a995041D71");
  await tx.wait();
  console.log(`✅ [${hre.network.name}] exchange()`)
  console.log(` tx: ${tx.transactionHash}`)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });