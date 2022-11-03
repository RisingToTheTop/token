const { expect } = require("chai")
const { config } = require("dotenv")
const { ethers, waffle, upgrades } = require("hardhat")
const { MerkleTree } = require("merkletreejs");
const keccak256 = require("keccak256");
const chai = require("chai");
chai.use(require('chai-bignumber')(ethers.BigNumber));
const provider = waffle.provider;

describe("main", () => {
  let owner, bob, alice, aggregator, factory, token, rest, leafNodes, merkleTree, rootHash, hexPloof, i_contract, i_owner, i_alice, i_aggregator, exFactory, exContract;
  beforeEach(async() => {
    [owner, bob, alice, fund, aggregator, ...rest] = await ethers.getSigners();

    const Lib = await ethers.getContractFactory("MusicLib");
    const lib = await Lib.deploy();
    await lib.deployed();

    factory = await ethers.getContractFactory("Record1155v2",{
      libraries: {
        MusicLib: lib.address,
      }
    });

    token = await factory.deploy();
    await token.deployed();
    tx = await token.initialize(owner.address, "WagmiToken", "disc","baseURI");
    await tx.wait();

    whitelistAddresses = [owner.address, alice.address, bob.address];
    leafNodes = whitelistAddresses.map(addr => keccak256(addr));
    merkleTree = new MerkleTree(leafNodes, keccak256, { sortPairs: true});
    rootHash = merkleTree.getRoot();
  })

  describe("normal method for erc1155", () => {
    beforeEach(async ()=>{
      const albumData = {
        _stakeHolders:[owner.address, alice.address, bob.address],
        _aggregator: aggregator.address,
        _presalePrices:[ethers.utils.parseEther("1"), ethers.utils.parseEther("1")],
        _prices:[ethers.utils.parseEther("1"), ethers.utils.parseEther("1")],
        _recoupLines:[10000, 10000],
        _quantities:[50, 20],
        _presaleQuantities:[10, 5],
        _share:[50, 30, 20],
        _purchaseLimits:[2, 2],
        _presalePurchaseLimits:[2, 2],
        _royalty:521,
        _merkleRoot:rootHash
      }
      // const albumData = {
      //   _stakeHolders:[owner.address, alice.address, bob.address],
      //   _aggregator: aggregator.address,
      //   _presalePrices:[ethers.utils.parseEther("0.5"), ethers.utils.parseEther("0.5"), ethers.utils.parseEther("0.5"), ethers.utils.parseEther("0.5")],
      //   _prices:[ethers.utils.parseEther("0.5"), ethers.utils.parseEther("0.5"), ethers.utils.parseEther("0.5"), ethers.utils.parseEther("0.5")],
      //   _recoupLines:[100,100,100,100],
      //   _presaleQuantities:[10, 10, 10, 10],
      //   _quantities:[10, 10, 10, 10],
      //   _share:[80,20],
      //   _presalePurchaseLimits:[10,10,10,10],
      //   _purchaseLimits:[10,10,10,10],
      //   _royalty:500,
      //   _merkleRoot:rootHash
      // }
      const musicData = {
        stakeHolders: [owner.address, alice.address, bob.address],
        aggregator: aggregator.address,
        prices: [ethers.utils.parseEther("1"), ethers.utils.parseEther("1")],
        recoupLine: 150000,
        share: [20, 30, 50],
        purchaseLimits: [2,2],
        numSold: 0,
        quantity: 100,
        presaleQuantity: 20,
        royalty: 521,
        album: 1,
        merkleRoot: rootHash
      }
      tx = await token.createAlbum(albumData);
      await tx.wait();
      tx = await token.createMusic(musicData);
      await tx.wait();
      // const receipt = await tx.wait();
      // for (const event of receipt.events) {
      //   console.log(`Event ${event.event} with args ${event.args}`);
      //   console.log(`stakeholder\n${event.args[1]}`);
      // }
    })
    describe("presale", () => {
      beforeEach(async ()=>{
        const tokenarray = await token.getTokenIdsOfAlbum(1);
        tx = await token.handleSaleState(tokenarray, 1);
        await tx.wait();
        hexPloof = merkleTree.getHexProof(keccak256(alice.address));
      })
      it("presale", async ()=>{
        tx = await token.connect(alice).omniMint(1,1, 0x0, hexPloof, { value: ethers.utils.parseEther("1")});
        await tx.wait();
        expect(await token.balanceOf(alice.address, 1)).to.be.equal(1)
      })
      it("presale renda", async ()=>{
        tx = await token.connect(alice).omniMint(1,1, 0x0, hexPloof, { value: ethers.utils.parseEther("1")});
        await tx.wait();
        tx = await token.connect(alice).omniMint(1,1, 0x0, hexPloof, { value: ethers.utils.parseEther("1")});
        await tx.wait();
        await expect(token.connect(alice).omniMint(1,1, 0x0, hexPloof, { value: ethers.utils.parseEther("1")})).to.be.revertedWith('exceeds limit');
      })
    })
    describe("publicsale", () => {
      beforeEach(async ()=>{
        const tokenarray = await token.getTokenIdsOfAlbum(1);
        tx = await token.handleSaleState(tokenarray, 2);
        await tx.wait();
      })
      it("public Sale", async ()=>{
        tx = await token.connect(bob).omniMint(1,1, 0x0, [], { value: ethers.utils.parseEther("1")});
        await tx.wait();
        expect(await token.balanceOf(bob.address, 1)).to.be.equal(1)
      })
      it("public sale renda", async ()=>{
        tx = await token.connect(bob).omniMint(1,2, 0x0, [], { value: ethers.utils.parseEther("2")});
        await tx.wait();
        await expect(token.connect(bob).omniMint(1,1, 0x0, [], { value: ethers.utils.parseEther("1")})).to.be.revertedWith('exceeds limit');
      })
    })
    describe("check parameter", ()=>{
      it("royalty Info", async ()=>{
        const data = await token.royaltyInfo(1,ethers.utils.parseEther("1"));
        // console.log("royalty Info",Number(data._royaltyAmount));
        // console.log("royalty Info:", data._royaltyAmount/ethers.utils.parseEther("1"))
      })
    })
    describe("withdraw revenue", ()=>{
      beforeEach(async () => {
        const tokenarray = await token.getTokenIdsOfAlbum(1);
        tx = await token.handleSaleState(tokenarray, 2);
        await tx.wait();
        // first funding
        tx = await token.connect(fund).omniMint(1,1, 0x0, [], { value: ethers.utils.parseEther("1")});
        await tx.wait();
        tx = await token.connect(fund).omniMint(3,1, 0x0, [], { value: ethers.utils.parseEther("1")});
        await tx.wait();
        i_contract = await provider.getBalance(token.address);
        i_owner = await provider.getBalance(owner.address);
        i_alice = await provider.getBalance(alice.address);
        i_aggregator = await provider.getBalance(aggregator.address);

        // console.log("initial contract balance:",ethers.utils.formatEther(i_contract))
        // console.log("initial owner balance:",ethers.utils.formatEther(i_owner))
        // console.log("initial alice balance:",ethers.utils.formatEther(i_alice))
      })
      it("each share must be keeped even withdrawal become complex", async() => {

        let data = await token.withdrawable(owner.address);
        // console.log("initial distribution:", ethers.utils.formatEther(data.distribution));
        // console.log("initial withdrawable:", ethers.utils.formatEther(data.value));
        // console.log("initial locked:", ethers.utils.formatEther(data.locked));

        /* 
        * Share setting 
        *  tokenId:1
        *   recoup line(円): 10000
        *   owner: 50%
        *   alice: 30%
        *   bob: 20%
        *  tokenId:3
        *   recoup line(円): 150000
        *   owner: 20%
        *   alice: 30%
        *   bob: 50%
        *  initial revenue
        *   (1,1) ether(+1,+1)
        *  final revenue
        *   (3,1) ether(+2,+1)
        *  final desirable amount
        *   contract: 1.08 ether
        *   owner: 1.65 ether - gas
        *   alice: 1.17 ether - gas
        *   aggregator: 1.1 ether - gas
        *   bob: unaquired
        */
        tx = await token.connect(aggregator).recoup(1);
        await tx.wait();
        tx = await token.connect(aggregator).recoup(3);
        await tx.wait();

        data = await token.withdrawable(owner.address);
        tx = await token.withdraw(owner.address, data.value);
        await tx.wait();

        tx = await token.connect(fund).omniMint(1,1, 0x0, [], { value: ethers.utils.parseEther("2")});
        await tx.wait();
        tx = await token.connect(fund).omniMint(3,1, 0x0, [], { value: ethers.utils.parseEther("1")});
        await tx.wait();

        tx = await token.withdraw(owner.address, 1000);
        await tx.wait();
        data = await token.withdrawable(owner.address);
        tx = await token.withdraw(owner.address, data.value);
        await tx.wait();

        await expect(token.connect(aggregator).recoup(1)).revertedWith("cost have been recouped");

        data = await token.withdrawable(alice.address);
        tx = await token.connect(alice).withdraw(alice.address, data.value);
        await tx.wait();

        let f_contract = await provider.getBalance(token.address);
        let f_owner = await provider.getBalance(owner.address);
        let f_alice = await provider.getBalance(alice.address);
        let f_aggregator = await provider.getBalance(aggregator.address);

        let d_owner = f_owner.sub(i_owner);
        let d_alice = f_alice.sub(i_alice);
        let d_aggregator = f_aggregator.sub(i_aggregator);

        console.log("====================================================")
        console.log("desirable");
        console.log(" contract: 1.08 ether")
        console.log(" owner: 1.65 ether - gas");
        console.log(" alice: 1.17 ether - gas");
        console.log(" aggregator: 1.1 ether - gas");
        console.log("====================================================")
        console.log("====================================================")
        console.log("final condition");
        console.log(" contract:", ethers.utils.formatEther(f_contract), "ether")
        console.log(" owner:", ethers.utils.formatEther(d_owner), "ether");
        console.log(" alice:", ethers.utils.formatEther(d_alice), "ether");
        console.log(" aggregator:", ethers.utils.formatEther(d_aggregator), "ether");
        console.log("====================================================")
    })
    })

    // describe("extension", ()=>{
    //   beforeEach(async ()=>{
    //   exFactory = await ethers.getContractFactory("ExchangeAgent");
    //   exContract = await exFactory.deploy(token.address,token.address);
    //   await exContract.deployed();
    //   tx = await token.license(exContract.address, true);
    //   await tx.wait();
    //   })
    //   it("ganbare", async()=>{
    //     const albumData = {
    //       _stakeHolders:[owner.address, alice.address, bob.address],
    //       _presalePrices:[ethers.utils.parseEther("1"), ethers.utils.parseEther("1")],
    //       _prices:[ethers.utils.parseEther("1"), ethers.utils.parseEther("1")],
    //       _quantities:[50, 20],
    //       _presaleQuantities:[10, 5],
    //       _share:[50, 30, 20],
    //       _purchaseLimits:[2, 2],
    //       _presalePurchaseLimits:[2, 2],
    //       _royalty:521,
    //       _merkleRoot:rootHash
    //     }
    //     tx = await token.createAlbum(albumData);
    //     await tx.wait();
    //     tx = await exContract.setMigration(1,1);
    //     await tx.wait();
    //     const tokenarray = await token.getTokenIdsOfAlbum(1);
    //     tx = await token.startPublicSale(tokenarray);
    //     await tx.wait();
    //     tx = await token.connect(bob).omniMint(1,1, 0x0, [], { value: ethers.utils.parseEther("1")});
    //     await tx.wait();
    //     expect(await token.balanceOf(bob.address, 1)).to.be.equal(1);
    //     expect(await token.balanceOf(alice.address, 1)).to.be.equal(0);
    //     // main deals !
    //     tx = await exContract.connect(bob).exchange(1,0, alice.address);
    //     await tx.wait();
    //     console.log("alice balance",Number(await token.balanceOf(alice.address, 1)));
    //   })
    // })
    // describe("upgradeable", ()=>{
    //   beforeEach(async ()=>{
    //     upgradeFactory = await ethers.getContractFactory("WAGMIMusicToken1155V2");
    //     upgradeContract = await upgrades.upgradeProxy(token.address, upgradeFactory);
    //     await upgradeContract.deployed();
    //   })
    //   it("ganbare", async()=>{
    //     tx = await upgradeContract.initializeV2(owner.address, "wagmi", "disc", "baseURI");
    //     await tx.wait();
    //   })
    // })
  })
})