// import dependencies
const dotenv = require("dotenv");
dotenv.config(); // setup dotenv

/*
  comment in omniMint !!!
  comment in omniMint !!!
  comment in omniMint !!!
  comment out fix ETH/JPY rate !!!
  comment out fix ETH/JPY rate !!!
  comment out fix ETH/JPY rate !!!
*/

async function main() {
  const Lib = await ethers.getContractFactory("MusicLib");
  const lib = await Lib.deploy();
  await lib.deployed();

  const factory = await hre.ethers.getContractFactory("Record1155v2",{
    libraries: {
      MusicLib: lib.address,
    }
  });
  const option = {
    gasPrice: 0 * 10**9
  }
  const contract = await factory.deploy();
  // const contract = await factory.deploy();
  await contract.deployed();
  console.log("NFT deployed to:", contract.address);
  const gasPrice = contract.deployTransaction.gasPrice;
  const gasLimit = contract.deployTransaction.gasLimit;

  console.log("GasPrice(gwei):", gasPrice / 10**9);
  console.log("GasLimit:", gasLimit);
  console.log("GasFee:", ethers.utils.formatEther(gasPrice) * gasLimit)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });