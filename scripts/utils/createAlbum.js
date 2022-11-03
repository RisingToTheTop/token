// import dependencies
const dotenv = require("dotenv");
dotenv.config(); // setup dotenv

const srcAddr = process.env.CONTRACT_ADDRESS;
const rootHash = "0x4a7c2a80d3ac8aaec63c2764b79ad0ae6974df0348dfe6e4d7d637aea205bc66"

const albumData = {
  _stakeHolders:["0xAd84F848Efb88C7D2aC9e0e8181861a995041D71","0x16ea840cfA174FdAC738905C4E5dB59Fd86912a1"],
  _aggregator:"0xAd84F848Efb88C7D2aC9e0e8181861a995041D71",
  _presalePrices:[ethers.utils.parseEther("0.5"), ethers.utils.parseEther("0.5"), ethers.utils.parseEther("0.5"), ethers.utils.parseEther("0.5")],
  _prices:[ethers.utils.parseEther("0.5"), ethers.utils.parseEther("0.5"), ethers.utils.parseEther("0.5"), ethers.utils.parseEther("0.5")],
  _recoupLines:[100000, 100000, 100000, 100000],
  _presaleQuantities:[10, 10, 10, 10],
  _quantities:[10, 10, 10, 10],
  _share:[50,50],
  _presalePurchaseLimits:[10,10,10,10],
  _purchaseLimits:[10,10,10,10],
  _royalty:500,
  _merkleRoot:rootHash
}

const musicData = {
  stakeHolders:["0xAd84F848Efb88C7D2aC9e0e8181861a995041D71","0x16ea840cfA174FdAC738905C4E5dB59Fd86912a1"],
  aggregator:"0xAd84F848Efb88C7D2aC9e0e8181861a995041D71",
  prices:[ethers.utils.parseEther("0.01"),ethers.utils.parseEther("0.01")],
  recoupLine:10000,
  share:[80,20],
  purchaseLimits:[2,10],
  numSold:0,
  quantity:10,
  presaleQuantity:10,
  royalty:500,
  album:0,
  merkleRoot:rootHash
}

// const option = {
//   gasPrice: 100 * 10**9
// }

async function main () {
  const Lib = await ethers.getContractFactory("MusicLib");
  const lib = await Lib.attach("0xD956F8e8d89e88bF30AB26a0AB25DfC0A7A87901");
  const contractFactory = await ethers.getContractFactory("Record1155v2",{
    libraries: {
      MusicLib: lib.address,
    }
  });
  const contract = await contractFactory.attach(srcAddr);
  // let estimateGas = await contract.estimateGas.createAlbum(albumData)
  // console.log(Number(estimateGas))

  let tx = await (await contract.createMusic(musicData)).wait()
  console.log(`✅ [${hre.network.name}] createAlbum(Struct)`)
  console.log(` tx: ${tx.transactionHash}`)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });