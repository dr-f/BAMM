const { expect } = require("chai");
//const { ethers } = require("ethers");
const { ethers, web3, assert } = require("hardhat");


const toBN = web3.utils.toBN

describe("BAMM", async () => {
    let knc
    let feePoolAddress
    let bamm
    let oracle
    let treasuryAddress
    let liquidationStrat
    let kncWhale
    let ethWhale
    const ETH = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
    const dummy = "0xEeeeeeeEEEeEEeeEEeeEEeEEEEEeeEEEeeEeEeed"
    const dummy2 = "0xeEEEeeEeEeEeeeeEeeEEeEeEeeeEEEEeeEeEeeef"
    let nonOwner    

    before(async () => {
      //gasPriceInWei = await web3.eth.getGasPrice()      
    })

    beforeEach(async () => {
      const [owner, addr1, addr2] = await ethers.getSigners();

      feePoolAddress = addr1.address;
      ethWhale = kncWhale = owner
      nonOwner = addr2
            
      const KNCToken = await ethers.getContractFactory("KNC");
      const Oracle = await ethers.getContractFactory("LiquidationPriceOracleBase");
      const Bamm = await ethers.getContractFactory("BAMM");
      const LiquidationStrat = await ethers.getContractFactory("LiquidationStrategyBase");

/*
      const BAMM = artifacts.require("BAMM")
      const KNCToken = artifacts.require("KNC")
      const Oracle = artifacts.require("LiquidationPriceOracleBase")
*/
      
      knc = await KNCToken.deploy()
      oracle = await Oracle.deploy()
      liquidationStrat = await LiquidationStrat.deploy()
      treasuryAddress = await liquidationStrat.v();

      bamm = await Bamm.deploy(liquidationStrat.address, treasuryAddress, oracle.address, knc.address, 400, feePoolAddress)
    })

    it("check swap", async () => {
      // send some ether to the treasuryAddress
      await web3.eth.sendTransaction({from: ethWhale.address, to: treasuryAddress, value: web3.utils.toWei("1")})

      const normBalance = await bamm.normalizeAccordingToPrice(ETH, web3.utils.toWei("1"), knc.address)
      expect(normBalance.toString()).to.eql(web3.utils.toWei("600"))

      await bamm.setParams(20, 0, web3.utils.toWei("100000000"))      
      //function normalizeAccordingToPrice(address srcToken, uint srcQty, address destToken) public view returns(uint)
      const retAmount = await bamm.getSwapAmount(knc.address, web3.utils.toWei("1"), ETH)
      expect(retAmount.toString()).to.eql("1666667618248530")

      // give knc allowance
      await knc.approve(bamm.address, web3.utils.toWei("1"))
      await bamm.swap(knc.address, web3.utils.toWei("1"), ETH, 0, dummy)

      const dummyBalance = await web3.eth.getBalance(dummy)
      expect(dummyBalance.toString()).to.eql(retAmount.toString())
    })

    it("check price formula", async () => {
      const xQty = "1234567891"
      const xBalance = "321851652450"
      const yBalance = "219413622039"
      const A = 200
      const ret = toBN((await bamm.getReturn(xQty, xBalance, yBalance, A)).toString());
      const retAfterFee = ret.sub(ret.mul(toBN("4000000")).div(toBN(10**10)))
      assert.equal(retAfterFee.toString(10), '1231543859')
    })

    it("check set params and swap with fees", async () => {
      // send some ether to the treasuryAddress
      await web3.eth.sendTransaction({from: ethWhale.address, to: treasuryAddress, value: web3.utils.toWei("100")})

      const A = 200
      const fee = 100
      const xBalance = web3.utils.toWei("100000000")
      const xQty = web3.utils.toWei("990") // 99% of 1k
      const yBalance = (toBN(xBalance).add(toBN(web3.utils.toWei((200*600).toString())))).toString()

      const expectedRet = toBN((await bamm.getReturn(xQty, xBalance, yBalance, A)).toString());
      const normExpReturn = expectedRet.div(toBN(600)).mul(toBN(100)).div(toBN(99)) // norm to knc and divide by 99%
      await bamm.setParams(A, fee, xBalance)
      const realRet = await bamm.getSwapAmount(knc.address, web3.utils.toWei("1000"), ETH)
      assert.equal(normExpReturn.toString(), realRet.toString())

      const convRate = await bamm.getConversionRate(knc.address, ETH, web3.utils.toWei("1000"), 7)
      assert.equal(convRate.toString(), toBN(realRet.toString()).div(toBN(1000)).toString())

      await knc.approve(bamm.address, web3.utils.toWei("1000"))
      await bamm.trade(knc.address, web3.utils.toWei("1000"), ETH, dummy2, 0, false)
      const dummyBalanceAfter = await web3.eth.getBalance(dummy2)
      expect(dummyBalanceAfter.toString()).to.eql(realRet.toString())

      const feeBalane = await knc.balanceOf(feePoolAddress)
      const startBalance = await knc.balanceOf(liquidationStrat.address)

      assert.equal(feeBalane.toString(), web3.utils.toWei("10"))
      assert.equal(startBalance.toString(), web3.utils.toWei("990"))

      const answer = await bamm.oracleAnswer()
      assert.equal(answer.toString(), startBalance.toString())
    })

    it("check price calc edge cases", async () => {
      // send some ether to the treasuryAddress- be very imbalanced
      await web3.eth.sendTransaction({from: ethWhale.address, to: treasuryAddress, value: web3.utils.toWei("9000")})
      await bamm.setParams(20, 0, web3.utils.toWei("1"))      
      const retAmount = await bamm.getSwapAmount(knc.address, web3.utils.toWei("1"), ETH)
      expect(retAmount.toString()).to.eql("1733333333333332")

      // ask for amount > inventory
      const retAmount2 = await bamm.getSwapAmount(knc.address, web3.utils.toWei("1000000000000000"), ETH)
      expect(retAmount2.toString()).to.eql(web3.utils.toWei("9000"))      
    })

    it("swap below min rate", async () => {
      // send some ether to the treasuryAddress- be very imbalanced
      await web3.eth.sendTransaction({from: ethWhale.address, to: treasuryAddress, value: web3.utils.toWei("9")})
      await bamm.setParams(20, 0, web3.utils.toWei("1"))      
      const retAmount = await bamm.getSwapAmount(knc.address, web3.utils.toWei("1"), ETH)
      const highMinAmount = toBN(retAmount.toString()).add(toBN("1"))

      await knc.approve(bamm.address, web3.utils.toWei("1"))
      await assertRevert(bamm.swap(knc.address, web3.utils.toWei("1"), ETH, highMinAmount.toString(), dummy), "swap: return-too-low")
    })    

    it("set params sad paths", async () => {
      await assertRevert(bamm.setParams(201, 0, web3.utils.toWei("1")), "setParams: A too big")
      await assertRevert(bamm.setParams(19, 0, web3.utils.toWei("1")), "setParams: A too small")
      await assertRevert(bamm.setParams(20, 101, web3.utils.toWei("1")), "setParams: fee is too big")
      await assertRevert(bamm.connect(nonOwner).setParams(20, 100, web3.utils.toWei("1")), "Ownable: caller is not the owner")       
    })
})

async function assertRevert(txPromise, message = undefined) {
  try {
    const tx = await txPromise
    // console.log("tx succeeded")
    assert.isFalse(tx.receipt.status) // when this assert fails, the expected revert didn't occur, i.e. the tx succeeded
  } catch (err) {
    assert.include(err.message, "revert")
    
    if (message) {
       assert.include(err.message, message)
    }
  }
}