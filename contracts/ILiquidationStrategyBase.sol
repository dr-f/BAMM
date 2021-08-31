// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
* Use different logics to compute price oracle
* If token is not supported, it should return 0 as conversion rate
*/
interface ILiquidationStrategyBase {
  function liquidate(
    address oracle,
    address[] calldata sources,
    uint256[] calldata amounts,
    address payable recipient,
    address dest,
    bytes calldata oracleHint,
    bytes calldata txData
  ) external returns (uint256 destAmount);
}