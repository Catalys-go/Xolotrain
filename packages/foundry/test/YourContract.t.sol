// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {YourContract} from "../contracts/YourContract.sol";

contract YourContractTest is Test {
    YourContract public yourContract;

    function setUp() public {
        yourContract = new YourContract(vm.addr(1));
    }

    function testMessageOnDeployment() public view {
        require(keccak256(bytes(yourContract.greeting())) == keccak256("Building Unstoppable Apps!!!"));
    }
}
