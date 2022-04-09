//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "./Auth.sol";
import "./SafeAffinity.sol";

contract SafeMaster is Auth {

    address public affinityAddr;

    SafeAffinity public affinity;

    constructor(address affinityAddress) Auth(msg.sender) {
        affinityAddr = affinityAddress;
        affinity = SafeAffinity(payable(affinityAddress));
    }

    function delegateExemptFee(address _user, bool _exemptFee, bool _exemptTXLimit) external authorized {
        affinity.setIsFeeAndTXLimitExempt(_user, _exemptFee, _exemptTXLimit);
    }

    function transferAffinityOwnership(address _newOwner) external onlyOwner {
        affinity.transferOwnership(_newOwner);
    }

    function setAffinityAddr(address _newAddr) external onlyOwner {
        affinityAddr = _newAddr;
        affinity = SafeAffinity(payable(_newAddr));
    }

}