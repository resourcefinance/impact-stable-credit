// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@stable-credit/contracts/StableCredit/StableCredit.sol";
import "./interface/IImpactStableCredit.sol";
import "./interface/IImpactFeeManager.sol";
import "./interface/IImpactCreditIssuer.sol";

/// @title ImpactStableCredit
/// @notice Extends the StableCredit contract to include network burning functionality
/// via fees paid in credits, an ambassador program, and the credit pool.
/// @dev Restricted functions are only callable by network operators.

contract ImpactStableCredit is StableCredit, IImpactStableCredit {
    /* ========== STATE VARIABLES ========== */

    IAmbassador public ambassador;

    /* ========== INITIALIZER ========== */

    function initialize(string memory name_, string memory symbol_, address access_)
        public
        virtual
        initializer
    {
        __StableCredit_init(name_, symbol_, access_);
        // assign "network debt account" credit line
        setCreditLimit(address(this), type(uint128).max - 1);
        access = IAccessManager(access_);
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    /// @notice Reduces network debt in exchange for reserve reimbursement.
    /// @dev Must have sufficient network debt or pool debt to service.
    function burnNetworkDebt(address member, uint256 amount)
        public
        override
        onlyOperator
        returns (uint256)
    {
        return super.burnNetworkDebt(member, amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice transfer a given member's debt to the network
    /// @param member address of member to write off
    function writeOffCreditLine(address member) public virtual override onlyCreditIssuer {
        if (address(ambassador) != address(0)) {
            ambassador.assumeDebt(member, creditBalanceOf(member));
        }
        super.writeOffCreditLine(member);
    }

    /// @notice enables network admin to set the ambassador address
    /// @param _ambassador address of ambassador contract
    function setAmbassador(address _ambassador) external onlyAdmin {
        ambassador = IAmbassador(_ambassador);
        emit AmbassadorUpdated(_ambassador);
    }

    /// @notice Enables members to transfer credits to other network participants
    /// @dev members are only able to pay tx fees in stable credits if there is network debt to service
    /// and they are only using a positive balance (including tx fee)
    /// @param _from address of sender
    /// @param _to address of recipient
    /// @param _amount amount of credits to transfer
    function _transferWithCreditFees(address _from, address _to, uint256 _amount)
        internal
        returns (bool)
    {
        IImpactFeeManager impactFeeManager = IImpactFeeManager(address(feeManager));
        require(
            impactFeeManager.canPayFeeInCredits(_from, _amount),
            "StableCredit: Cannot pay fees in credits"
        );
        uint256 fee = IImpactFeeManager(address(feeManager)).calculateFeeInCredits(_from, _amount);
        super.burnNetworkDebt(_from, fee);
        // validate transaction
        if (!creditIssuer.validateTransaction(_from, _to, _amount)) return false;
        IImpactCreditIssuer impactCreditIssuer = IImpactCreditIssuer(address(creditIssuer));
        emit CreditLineStateUpdated(
            _from,
            _to,
            impactCreditIssuer.itdOf(_from),
            impactCreditIssuer.itdOf(_to),
            creditIssuer.inCompliance(_from),
            creditIssuer.inCompliance(_to)
            );
        MutualCredit._transfer(_from, _to, _amount);
        return true;
    }

    /// @notice Caller must approve feeManager to spend reserve tokens for transfer of credits.
    /// @dev Validates the caller's credit line and synchronizes demurrage balance.
    function _transfer(address _from, address _to, uint256 _amount)
        internal
        virtual
        override
        senderIsMember(_from)
    {
        IImpactFeeManager impactFeeManager = IImpactFeeManager(address(feeManager));
        // allow transfer with credit fees if credit fees are enabled and the sender is not an operator
        if (
            feeManager.shouldChargeTx(_from, _to) && !impactFeeManager.creditFeesDisabled(_from)
                && impactFeeManager.canPayFeeInCredits(_from, _amount)
        ) {
            _transferWithCreditFees(_from, _to, _amount);
        } else {
            super._transfer(_from, _to, _amount);
        }
        IImpactCreditIssuer impactCreditIssuer = IImpactCreditIssuer(address(creditIssuer));
        emit CreditLineStateUpdated(
            _from,
            _to,
            impactCreditIssuer.itdOf(_from),
            impactCreditIssuer.itdOf(_to),
            creditIssuer.inCompliance(_from),
            creditIssuer.inCompliance(_to)
            );
    }
}
