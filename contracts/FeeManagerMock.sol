// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@stable-credit/contracts/FeeManager.sol";

contract FeeManagerMock is FeeManager {
    function initialize(address _stableCredit) public initializer {
        __FeeManager_init(_stableCredit);
    }
}
