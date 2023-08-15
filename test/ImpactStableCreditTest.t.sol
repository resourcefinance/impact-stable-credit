// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "@stable-credit/contracts/AccessManager.sol";
import "@stable-credit/contracts/Assurance/AssurancePool.sol";
import "@stable-credit/contracts/Assurance/AssuranceOracle.sol";
import "@uniswap/v3-periphery/contracts/lens/Quoter.sol";
import "../contracts/ImpactCreditIssuer.sol";
import "../contracts/ImpactFeeManager.sol";
import "../contracts/ImpactStableCredit.sol";
import "../contracts/Pools/CreditPool.sol";
import "./MockERC20.sol";

contract ImpactStableCreditTest is Test {
    address alice;
    address bob;
    address carol;
    address deployer;

    MockERC20 public reserveToken;
    AssurancePool public assurancePool;
    AssuranceOracle public assuranceOracle;
    ImpactStableCredit public stableCredit;
    AccessManager public accessManager;
    ImpactFeeManager public feeManager;
    ImpactCreditIssuer public creditIssuer;
    CreditPool public creditPool;

    // STATIC VARIABLES
    address uSDCAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address uSDCWhale = 0x78605Df79524164911C144801f41e9811B7DB73D;
    address wETHAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address uniSwapRouterAddress = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    Quoter quoter = Quoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

    function setUpReSourceTest() public {
        alice = address(2);
        bob = address(3);
        carol = address(4);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        deployer = address(1);
        vm.startPrank(deployer);

        // deploy reserve token
        reserveToken = new MockERC20(1000000e18, "Reserve Token", "REZ");
        // deploy AssuranceOracle
        assuranceOracle = new AssuranceOracle();
        // deploy accessManager
        accessManager = new AccessManager();
        accessManager.initialize(deployer);
        // deploy mock StableCredit network
        stableCredit = new ImpactStableCredit();
        stableCredit.initialize("mock", "MOCK", address(accessManager));
        // deploy assurancePool
        assurancePool = new AssurancePool();
        assurancePool.initialize(
            address(stableCredit),
            address(reserveToken),
            address(reserveToken),
            address(assuranceOracle),
            uniSwapRouterAddress,
            deployer
        );
        //deploy feeManager
        feeManager = new ImpactFeeManager();
        feeManager.initialize(address(stableCredit));
        // deploy creditIssuer
        creditIssuer = new ImpactCreditIssuer();
        creditIssuer.initialize(address(stableCredit));
        // initialize contract variables
        accessManager.grantOperator(address(stableCredit)); // grant stableCredit operator access
        accessManager.grantOperator(address(creditIssuer)); // grant creditIssuer operator access
        accessManager.grantOperator(address(feeManager)); // grant feeManager operator access
        stableCredit.setAccessManager(address(accessManager)); // set accessManager
        stableCredit.setFeeManager(address(feeManager)); // set feeManager
        stableCredit.setCreditIssuer(address(creditIssuer)); // set creditIssuer
        stableCredit.setAssurancePool(address(assurancePool)); // set assurancePool
        assurancePool.setTargetRTD(20e16); // set targetRTD to 20%
        feeManager.setBaseFeeRate(5e16); // set base fee rate to 5%
        // send alice 1000 reserve tokens
        assurancePool.reserveToken().transfer(alice, 1000 ether);
        reserveToken.transfer(bob, 100 ether);
        reserveToken.transfer(carol, 100 ether);
        accessManager.grantMember(bob);
        // initialize alice credit line
        creditIssuer.initializeCreditLine(alice, 90 days, 30 days, 1000e6, 5e16, 10e16, 0);
        // deploy credit pool
        creditPool = new CreditPool();
        creditPool.initialize(address(stableCredit));
        // set credit pool limit to max
        stableCredit.createCreditLine(address(creditPool), type(uint128).max - 1, 0);
        accessManager.grantOperator(address(creditPool)); // grant creditPool operator access
    }

    function test() public {}
}
