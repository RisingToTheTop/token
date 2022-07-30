const { expect } = require("chai")
const { config } = require("dotenv")
const { ethers, waffle } = require("hardhat")
const { MerkleTree } = require("merkletreejs");
const keccak256 = require("keccak256");
const chai = require("chai");
chai.use(require('chai-bignumber')(ethers.BigNumber));
const provider = waffle.provider;

describe("main", () => {
  let owner, bob, alice, factory, token, rest, leafNodes, merkleTree, rootHash, hexPloof, i_contract, i_owner, i_alice;
  beforeEach(async() => {
    [owner, bob, alice, fund, ...rest] = await ethers.getSigners();

    factory = await ethers.getContractFactory("WAGMIMusicToken1155");

    token = await factory.deploy();
    await token.deployed();
    tx = await token.initialize(owner.address, "wagmi", "disc", "baseURI");
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
        _presalePrices:[ethers.utils.parseEther("1"), ethers.utils.parseEther("1")],
        _prices:[ethers.utils.parseEther("1"), ethers.utils.parseEther("1")],
        _quantities:[50, 20],
        _presaleQuantities:[10, 5],
        _share:[50, 30, 20],
        _purchaseLimits:[2, 2],
        _royalty:521,
        _merkleRoot:rootHash
      }
      tx = await token.createAlbum(albumData);
      await tx.wait();

      tx = await token.createMusic(
        [owner.address, alice.address, bob.address],
        [ethers.utils.parseEther("1"), ethers.utils.parseEther("1")],
        [20, 30, 50],
        2,
        100,
        20,
        521,
        rootHash,
        1
      );
      await tx.wait();
      // const receipt = await tx.wait();
      // for (const event of receipt.events) {
      //   console.log(`Event ${event.event} with args ${event.args}`);
      //   console.log(`stakeholder\n${event.args[1]}`);
      // }
    })
    describe("presale", async () => {
      beforeEach(async ()=>{
        const tokenarray = await token.getTokenIdsOfAlbum(1);
        tx = await token.startPresale(tokenarray);
        await tx.wait();
        hexPloof = merkleTree.getHexProof(keccak256(alice.address));
      })
      xit("presale", async ()=>{
        tx = await token.connect(alice).omniMint(1,1, 0x0, hexPloof, { value: ethers.utils.parseEther("1")});
        await tx.wait();
        expect(await token.balanceOf(alice.address, 1)).to.be.equal(1)
      })
      xit("presale renda", async ()=>{
        tx = await token.connect(alice).omniMint(1,1, 0x0, hexPloof, { value: ethers.utils.parseEther("1")});
        await tx.wait();
        tx = await token.connect(alice).omniMint(1,1, 0x0, hexPloof, { value: ethers.utils.parseEther("1")});
        await tx.wait();
        await expect(token.connect(alice).omniMint(1,1, 0x0, hexPloof, { value: ethers.utils.parseEther("1")})).to.be.revertedWith('Accumulayion amount of mint exceeds limit');
      })
    })
    describe("publicsale", async () => {
      beforeEach(async ()=>{
        const tokenarray = await token.getTokenIdsOfAlbum(1);
        tx = await token.startPublicSale(tokenarray);
        await tx.wait();
      })
      xit("public Sale", async ()=>{
        tx = await token.connect(bob).omniMint(1,1, 0x0, [], { value: ethers.utils.parseEther("1")});
        await tx.wait();
        expect(await token.balanceOf(bob.address, 1)).to.be.equal(1)
      })
      xit("public sale renda", async ()=>{
        tx = await token.connect(bob).omniMint(1,2, 0x0, [], { value: ethers.utils.parseEther("2")});
        await tx.wait();
        await expect(token.connect(bob).omniMint(1,1, 0x0, [], { value: ethers.utils.parseEther("1")})).to.be.revertedWith('Accumulayion amount of mint exceeds limit');
      })
    })
    describe("check parameter", async ()=>{
      xit("royalty Info", async ()=>{
        const data = await token.royaltyInfo(1,ethers.utils.parseEther("1"));
        console.log("royalty Info",Number(data._royaltyAmount));
        console.log(data._royaltyAmount/ethers.utils.parseEther("1"))
      })
    })
    describe("withdraw revenue", async ()=>{
      beforeEach(async () => {
        const tokenarray = await token.getTokenIdsOfAlbum(1);
        tx = await token.startPublicSale(tokenarray);
        await tx.wait();
        // first funding
        tx = await token.connect(fund).omniMint(1,1, 0x0, [], { value: ethers.utils.parseEther("1")});
        await tx.wait();
        tx = await token.connect(fund).omniMint(3,1, 0x0, [], { value: ethers.utils.parseEther("1")});
        await tx.wait();
        i_contract = await provider.getBalance(token.address);
        i_owner = await provider.getBalance(owner.address);
        i_alice = await provider.getBalance(alice.address);

        // console.log("initial contract balance:",ethers.utils.formatEther(i_contract))
        // console.log("initial owner balance:",ethers.utils.formatEther(i_owner))
        // console.log("initial alice balance:",ethers.utils.formatEther(i_alice))
      })
      it("each share must be keeped even withdrawal become complex", async() => {

        let data = await token.withdrawable();
        // console.log("initial distribution:", ethers.utils.formatEther(data._distribution));
        // console.log("initial withdrawable:", ethers.utils.formatEther(data._withdrawable));

        /* 
        * Share setting 
        *  tokenId:1
        *   owner: 50%
        *   alice: 30%
        *   bob: 20%
        *  tokenId:3
        *   owner: 20%
        *   alice: 30%
        *   bob: 50%
        *  initial revenue
        *   (1,1) ether(+1,+1)
        *  final revenue
        *   (3,1) ether(+2,0)
        *  final desirable amount
        *   contract: 1.1 ether
        *   owner: 1.5+0.2 ether - gas
        *   alice: 0.9+0.3 ether - gas
        *   bob: unaquired
        */

        tx = await token.withdraw(owner.address);
        await tx.wait();
        data = await token.withdrawable();
        // console.log("initial distribution:", ethers.utils.formatEther(data._distribution));
        // console.log("initial withdrawable:", ethers.utils.formatEther(data._withdrawable));

        tx = await token.connect(fund).omniMint(1,1, 0x0, [], { value: ethers.utils.parseEther("2")});
        await tx.wait();
        tx = await token.withdraw(owner.address);
        await tx.wait();
        tx = await token.connect(alice).withdraw(alice.address);
        await tx.wait();

        let f_contract = await provider.getBalance(token.address);
        let f_owner = await provider.getBalance(owner.address);
        let f_alice = await provider.getBalance(alice.address);

        let d_owner = f_owner.sub(i_owner);
        let d_alice = f_alice.sub(i_alice);

        console.log("final condition");
        console.log("contract:", ethers.utils.formatEther(f_contract))
        console.log("owner:", ethers.utils.formatEther(d_owner));
        console.log("alice:", ethers.utils.formatEther(d_alice));
    })
    })
  })
})