// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@stable-credit/contracts/interface/IMutualCredit.sol";
import "@stable-credit/contracts/FeeManager.sol";
import "./interface/IImpactCreditIssuer.sol";
import "./interface/IImpactStableCredit.sol";
import "./interface/IImpactFeeManager.sol";

/// @title ImpactFeeManager
/// @notice Extends the FeeManager contract to include custom fee calculation logic
contract ImpactFeeManager is FeeManager, IImpactFeeManager {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IStableCredit;

    /* ========== STATE VARIABLES ========== */
    mapping(address => bool) public _creditFeesDisabled;

    /* ========== INITIALIZER ========== */

    function initialize(address _stableCredit) external initializer {
        __FeeManager_init(_stableCredit);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice Called by a StableCredit instance to collect fees from the credit sender
    /// @dev the sender must approve the feeManager to spend reserve tokens on their behalf before
    /// fees can be collected.
    /// @param sender stable credit sender address
    /// @param recipient stable credit recipient address
    /// @param amount stable credit amount
    function collectFee(address sender, address recipient, uint256 amount) public override {
        if (!shouldChargeTx(sender, recipient)) {
            return;
        }
        uint256 fee = calculateFee(sender, amount);
        // collect reserve token fees from sender
        stableCredit.assurancePool().reserveToken().safeTransferFrom(sender, address(this), fee);
        // calculate base fee
        uint256 baseFee = calculateFee(address(0), amount);
        // deposit portion of baseFee to ambassador
        uint256 ambassadorFee = depositAmbassadorFee(sender, baseFee);
        // update total fees collected
        collectedFees += fee - ambassadorFee;
        emit FeesCollected(sender, fee);
    }

    /// @notice Enables members to specify if fees should be paid in credits if possible
    /// @param member address of member to set payFeesInCredits
    /// @param disabled disable paying fees in credits when available
    function setCreditFeesDisabled(address member, bool disabled) public {
        require(member == _msgSender(), "StableCredit: Only member can set payFeesInCredits");
        _creditFeesDisabled[member] = disabled;
    }

    /* ========== VIEWS ========== */

    /// @notice calculate fee to charge member in reserve token value
    /// @dev extends the base fee calculation to include a member risk fee rate provided by the
    /// ReSource credit issuer. If a null member address is supplied, the base fee is returned.
    /// Calling with inCredits as true requires member balance to be greater than tx amount.
    /// @param amount stable credit amount to base fee off of
    /// @return reserve token amount to charge given member
    function calculateFee(address member, uint256 amount) public view override returns (uint256) {
        // if contract is paused, return 0
        if (paused()) {
            return 0;
        }
        // if member is null, return base fee
        if (member == address(0)) {
            return super.calculateFee(member, amount);
        }
        // add riskFee if member is using credit balance or paying fee in credits
        uint256 balance = stableCredit.balanceOf(member);
        if (balance < amount) {
            // calculate member risk fee rate
            uint256 riskFeeRate = IImpactCreditIssuer(address(stableCredit.creditIssuer()))
                .creditTermsOf(member).feeRate;
            // calculate amount effected by risk fee
            uint256 riskAmount = amount - balance;
            uint256 riskFee = stableCredit.assurancePool().convertStableCreditToReserveToken(
                (riskFeeRate * riskAmount) / 1 ether
            );
            // return base fee + risk fee
            return super.calculateFee(member, amount) + riskFee;
        }
        // if member is using positive balance return base fee calculation
        return super.calculateFee(member, amount);
    }

    /// @notice Returns whether a given member can pay a given amount of fees in credits
    /// @param sender address of Member
    /// @param amount amount of credits to transfer
    /// @return whether member can pay fees in credits
    function canPayFeeInCredits(address sender, uint256 amount) public view returns (bool) {
        uint256 fee = calculateFeeInCredits(sender, amount);
        bool sufficientBalance = stableCredit.balanceOf(sender) >= amount + fee;
        bool sufficientNetworkDebt = stableCredit.networkDebt() >= fee;
        return sufficientBalance && sufficientNetworkDebt;
    }

    function creditFeesDisabled(address member) external view override returns (bool) {
        return _creditFeesDisabled[member];
    }

    /// @notice calculate fee to charge member in stable credits
    /// @dev extends the base fee calculation to include a member risk fee rate provided by the
    /// ReSource credit issuer. If a null member address is supplied, the base fee is returned.
    /// Calling with inCredits as true requires member balance to be greater than tx amount.
    /// @param amount stable credit amount to base fee off of
    /// @return reserve token amount to charge given member
    function calculateFeeInCredits(address member, uint256 amount)
        public
        view
        override
        returns (uint256)
    {
        // if contract is paused or risk oracle is not set, return 0
        if (paused()) {
            return 0;
        }
        // if member is null, return base fee
        uint256 baseFee = baseFeeRate * amount / 1 ether;
        if (member == address(0)) {
            return baseFee;
        }
        // calculate member risk fee rate
        uint256 riskFeeRate =
            IImpactCreditIssuer(address(stableCredit.creditIssuer())).creditTermsOf(member).feeRate;
        uint256 riskFee = riskFeeRate * amount / 1 ether;
        return riskFee + baseFee;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /// @notice deposits member's ambassador fee based off the base fee to be collected
    /// @dev if the ambassador contract is not set, 0 is returned
    /// @param member member address
    /// @param baseFee base fee to be collected in reserve token value
    function depositAmbassadorFee(address member, uint256 baseFee) internal returns (uint256) {
        IImpactStableCredit impactStableCredit = IImpactStableCredit(address(stableCredit));
        if (address(impactStableCredit.ambassador()) != address(0) && baseFee > 0) {
            // approve ambassador to transfer minimum of base fee
            stableCredit.assurancePool().reserveToken().approve(
                address(impactStableCredit.ambassador()), baseFee
            );
            // deposit ambassador fee
            return impactStableCredit.ambassador().compensateAmbassador(member, baseFee);
        }
        return 0;
    }
}
