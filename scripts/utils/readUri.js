// import dependencies
const dotenv = require("dotenv");
dotenv.config(); // setup dotenv

//this scripts is for mumbai Chain
const { ethers } = require("hardhat");
let srcAddr = "0x2953399124F0cBB46d2CbACD8A89cF0599974963";
let tokenId = "78555306292208822264975053909961537674478548303611333324072215596677822676993";
async function main() {
  const contractFactory = await ethers.getContractFactory("WAGMIMusicToken1155");
  const contract = await contractFactory.attach(srcAddr);
  let uri = await contract.uri(tokenId);
  console.log(uri);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });