// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./PriceFormula.sol";
import "./ILiquidationPriceOracleBase.sol";
import "./ILiquidationStrategyBase.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BAMM is ILiquidationPriceOracleBase, PriceFormula, Ownable {
    using SafeMath for uint256;

    ILiquidationPriceOracleBase public immutable priceAggregator;
    address public immutable KNC;
    address public immutable treasury;
    address payable public immutable liquidationStrategyBase;

    address payable public immutable feePool;
    uint public constant MAX_FEE = 100; // 1%
    uint public fee = 0; // fee in bps
    uint public A = 20;
    uint public kncXBalance = 1000e18;
    uint public constant MIN_A = 20;
    uint public constant MAX_A = 200;    

    uint public immutable maxDiscount; // max discount in bips
    uint constant public PRECISION = 1e18;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint public oracleAnswer = 0;

    event ParamsSet(uint A, uint fee, uint kncXBalance);
    event CompletedSwap(address src, uint srcQty, address dest, uint destAmount, address reciever);

    constructor(
        address payable _liquidationStrategyBase,
        address _treasury,
        address _priceAggregator,
        address _KNC,
        uint _maxDiscount,
        address payable _feePool)
    {
        liquidationStrategyBase = _liquidationStrategyBase;
        treasury = _treasury;
        priceAggregator = ILiquidationPriceOracleBase(_priceAggregator);
        KNC = _KNC;

        feePool = _feePool;
        maxDiscount = _maxDiscount;
    }

    function setParams(uint _A, uint _fee, uint _kncXBalance) external onlyOwner {
        require(_fee <= MAX_FEE, "setParams: fee is too big");
        require(_A >= MIN_A, "setParams: A too small");
        require(_A <= MAX_A, "setParams: A too big");

        fee = _fee;
        A = _A;
        kncXBalance = _kncXBalance;

        emit ParamsSet(_A, _fee, _kncXBalance);
    }

    function normalizeAccordingToPrice(address srcToken, uint srcQty, address destToken) public view returns(uint) {
        address[] memory tokenIns = new address[](1);
        uint[] memory amountIns = new uint[](1);
        uint[] memory types = new uint[](1);

        tokenIns[0] = srcToken;
        amountIns[0] = srcQty;
        types[0] = 0;

        bytes memory hint = abi.encode(types);

        return priceAggregator.getExpectedReturn(address(this), tokenIns, amountIns, destToken, hint);
    }

    function addBps(uint n, int bps) internal pure returns(uint) {
        require(bps <= 10000, "reduceBps: bps exceeds max");
        require(bps >= -10000, "reduceBps: bps exceeds min");

        return n.mul(uint(10000 + bps)) / 10000;
    }

    function getTokenToKNCSwapAmount(IERC20 token, uint kncQty, address knc) public view returns(uint amount) {
        uint tokenBalance = 0;
        if(address(token) == ETH) tokenBalance = treasury.balance;
        else tokenBalance = token.balanceOf(treasury);

        uint tokenBalanceInKNC = normalizeAccordingToPrice(address(token), tokenBalance, knc);

        uint maxReturn = addBps(kncQty.mul(tokenBalance) / tokenBalanceInKNC, int(maxDiscount));

        uint xQty = kncQty;
        uint xBalance = knc == KNC ? kncXBalance : 0;
        uint yBalance = xBalance.add(tokenBalanceInKNC.mul(2));

        if(xBalance == 0) return 0;

        uint kncReturn = getReturn(xQty, xBalance, yBalance, A);
        uint basicReturn = kncReturn.mul(tokenBalance) / tokenBalanceInKNC;

        if(maxReturn < basicReturn) basicReturn = maxReturn;

        basicReturn =  basicReturn * 10000 / (10000 - fee);

        if(basicReturn > tokenBalance) basicReturn = tokenBalance;

        amount = basicReturn;
    }

    function getExpectedReturn(
        address /* liquidator */,
        address[] calldata /* tokenIns */,
        uint256[] calldata /* amountIns */,
        address /* tokenOut */,
        bytes calldata /* hint */
    ) external override view returns (uint256 minAmountOut)
    {
        return oracleAnswer;
    }

    function getSwapAmount(address src, uint srcQty, address dest) public view returns(uint) {
        uint amountAfterFee = addBps(srcQty, -int(fee));

        return getTokenToKNCSwapAmount(IERC20(dest), amountAfterFee, address(src));        
    }

    function swap(IERC20 src, uint srcQty, IERC20 dest, uint minReturn, address payable destAddress) public returns(uint) {
        uint amountAfterFee = addBps(srcQty, -int(fee));
        uint feeAmount = srcQty.sub(amountAfterFee);

        address[] memory sources = new address[](1);
        uint[] memory amounts = new uint[](1);

        sources[0] = address(dest);
        amounts[0] = getSwapAmount(address(src), srcQty, address(dest));
        require(amounts[0] >= minReturn, "swap: return-too-low");

        oracleAnswer = amountAfterFee;

        if(address(src) == ETH) {
            liquidationStrategyBase.transfer(amountAfterFee);
            if(feeAmount > 0) feePool.transfer(feeAmount);
        }
        else {
            src.transferFrom(msg.sender, address(liquidationStrategyBase), amountAfterFee);
            if(feeAmount > 0) src.transferFrom(msg.sender, feePool, feeAmount);
        }

        ILiquidationStrategyBase(liquidationStrategyBase).liquidate(address(this), sources, amounts, payable(address(this)), address(src), "", "");

        if(address(dest) == ETH) destAddress.transfer(amounts[0]);
        else dest.transfer(destAddress, amounts[0]);

        emit CompletedSwap(address(src), srcQty, address(dest), amounts[0], destAddress);

        return amounts[0];
    }

    function liquidationCallback(
        address caller,
        address[] calldata sources,
        uint256[] calldata amounts,
        address payable recipient,
        address dest,
        uint256 minReturn,
        bytes calldata txData
    ) external
    {
        // Do nothing
    }

    // kyber network reserve compatible function
    function trade(
        IERC20 srcToken,
        uint256 srcAmount,
        IERC20 destToken,
        address payable destAddress,
        uint256 /* conversionRate */,
        bool /* validate */
    ) external payable returns (bool) {
        return swap(srcToken, srcAmount, destToken, 0, destAddress) > 0;
    }

    function getConversionRate(
        IERC20 src,
        IERC20 dest,
        uint256 srcQty,
        uint256 /* blockNumber */
    ) external view returns (uint) {
        require(address(src) == KNC && address(dest) == ETH, "unsupported tokens");
        uint destQty = getSwapAmount(address(src), srcQty, address(dest));

        return destQty.mul(PRECISION) / srcQty; // this will break if tokens don't have 18 decimals
    }

    receive() external payable {}
}
