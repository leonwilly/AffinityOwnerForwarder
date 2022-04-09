//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAffinityDistributor {
    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution, uint256 _bnbToSafemoonThreshold) external;
    function setShare(address shareholder, uint256 amount) external;
    function deposit() external;
    function process(uint256 gas) external;
    function processManually() external returns(bool);
    function claimEarnDividend(address sender) external;
    function claimVAULTDividend(address sender) external;
    function updatePancakeRouterAddress(address pcs) external;
    function setSafeEarnAddress(address nSeth) external;
    function setSafeVaultAddress(address nSeth) external;
}