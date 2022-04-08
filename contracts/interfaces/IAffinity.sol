pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // required for calling af ERC20 functions

// @title IAffinity an interface for calling external / public affinity methods
interface IAffinity is IERC20 {
    function setIsFeeAndTXLimitExempt(address holder, bool feeExempt, bool txLimitExempt) external;
}
