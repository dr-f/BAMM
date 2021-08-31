pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract KNC is ERC20PresetFixedSupply {
    constructor() ERC20PresetFixedSupply("KNC","KNC",200000000e18,msg.sender) {}
}

contract LiquidationPriceOracleBase {
    uint price = 600e18; // 1 eth = 600 knc

    function getExpectedReturn(
        address liquidator,
        address[] calldata tokenIns,
        uint256[] calldata amountIns,
        address tokenOut,
        bytes calldata hint
    ) external view returns (uint256 minAmountOut) {
        minAmountOut = amountIns[0] * price / 1e18;
    }

    function setPrice(uint _price) external {
        price = _price;
    }
}

contract Vault {
    function transferEth(address payable dest, uint amount) external {
        dest.transfer(amount);
    }

    receive() external payable {}    
}

contract LiquidationStrategyBase {
    Vault public v;
    constructor() {
        v = new Vault();
    }
    function liquidate(
        address oracle,
        address[] calldata sources,
        uint256[] calldata amounts,
        address payable recipient,
        address dest,
        bytes calldata oracleHint,
        bytes calldata txData
    ) external returns (uint256 destAmount) {
        v.transferEth(recipient, amounts[0]);
    }
}
