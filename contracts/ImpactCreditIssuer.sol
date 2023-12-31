// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@stable-credit/contracts/CreditIssuer.sol";
import "./interface/IImpactCreditIssuer.sol";

/// @title ImpactCreditIssuer
/// @notice This contract enables authorized network participants to autonomously underwrite new
/// and existing members in order to issue credit lines and their associated credit terms.
/// @dev This contract inherits from the base CreditIssuer contract and implements the foundational
/// logic for credit periods and period expiration.
contract ImpactCreditIssuer is CreditIssuer, IImpactCreditIssuer {
    /* ========== STATE VARIABLES ========== */
    // member => credit terms
    mapping(address => CreditTerm) public creditTerms;

    /* ========== INITIALIZER ========== */

    function initialize(address _stableCredit) public initializer {
        __CreditIssuer_init(_stableCredit);
    }

    /* ========== VIEWS ========== */

    /// @notice returns whether a given member is in compliance with credit terms.
    /// @dev intended to be overwritten in parent implementation to include custom compliance logic.
    /// @param member address of member.
    /// @return whether member is in compliance with credit terms.
    function inCompliance(address member) public view override returns (bool) {
        return !periodInitialized(member) || (hasRebalanced(member) || hasValidITD(member));
    }

    /// @notice fetches whether a given member has rebalanced within the current credit period.
    /// @param member address of member to fetch rebalanced status for.
    /// @return whether the given member has rebalanced within the current credit period.
    function hasRebalanced(address member) public view returns (bool) {
        return creditTerms[member].rebalanced;
    }

    /// @notice fetches whether a given member has a valid Income to Debt ratio within the current
    /// credit period.
    /// @param member address of member to fetch ITD status for.
    /// @return whether the given member has a valid Income to Debt ratio within the current credit.
    /// period
    function hasValidITD(address member) public view returns (bool) {
        if (itdOf(member) == -1) return true;
        return itdOf(member) >= int256(creditTerms[member].minITD);
    }

    /// @notice fetches a given member's Income to Debt ratio within the current credit period.
    /// @param member address of member to fetch ITD for.
    /// @return ITD ratio within the current credit period, where 1 ether == 100%.
    function itdOf(address member) public view override returns (int256) {
        // if no income, return 0
        if (creditTerms[member].periodIncome == 0) return 0;
        // if no debt, return indeterminate
        if (stableCredit.creditBalanceOf(member) == 0) return -1;
        // income / credit balance (in Parts Per Million)
        return int256(creditTerms[member].periodIncome * 1 ether)
            / int256(stableCredit.creditBalanceOf(member));
    }

    /// @notice fetches a given member's needed income to comply with the given network's minimum
    /// Income to Debt ratio within the current credit period.
    /// @param member address of member to fetch needed income for.
    /// @return income required to be in good standing for current credit period.
    function neededIncomeOf(address member) external view returns (uint256) {
        // if ITD is valid, no income is needed
        if (hasValidITD(member)) return 0;
        return (
            (creditTerms[member].minITD * stableCredit.creditBalanceOf(member) / 1 ether)
                - creditTerms[member].periodIncome
        ) * 1 ether / ((creditTerms[member].minITD + 1 ether)) + 1;
    }

    /// @notice fetches a given member's credit terms state.
    /// @param member address of member to fetch needed income for.
    /// @return CreditTerm data including paused, rebalanced, periodIncome, and feeRate.
    function creditTermsOf(address member) public view override returns (CreditTerm memory) {
        return creditTerms[member];
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice facilitates authorized callers to autonomously underwrite and issue credit
    /// to members.
    /// @dev Caller must be authorized by network to underwrite members.
    /// @param member address of member to underwrite.
    function underwriteMember(address member)
        public
        override
        notNull(member)
        canIssueCreditTo(member)
    {
        super.underwriteMember(member);
        // TODO: use SBT data to calculate limit, fee rate, and min ITD
        // if member does not have SBT minted, return
        // grantMember(member);
        // initializeCreditLine(network, member, feeRate, creditLimit);
        emit MemberUnderwritten(member);
    }

    /// @notice called by network authorized to issue credit.
    /// @dev intended to be overwritten in parent implementation to include custom underwriting logic.
    /// @param member address of member.
    function grantMember(address member) public notNull(member) canIssueCreditTo(member) {
        // TODO: use SBT to determine identity of caller
    }

    /// @notice facilitates network operators to bypass the underwriting process and manually
    /// assign new members with credit terms and issue credit.
    /// @dev caller must have network operator role access.
    /// @param member address of member to initialize credit line for.
    /// @param periodLength length of credit period in seconds.
    /// @param graceLength length of grace period in seconds.
    /// @param creditLimit credit limit for member.
    /// @param feeRate fee rate for member.
    /// @param minITD minimum Income to Debt ratio for member.
    /// @param balance initial balance for member (debt is assigned to network debt account)
    function initializeCreditLine(
        address member,
        uint256 periodLength,
        uint256 graceLength,
        uint256 creditLimit,
        uint256 feeRate,
        uint256 minITD,
        uint256 balance
    ) public onlyIssuer notNull(member) notInActivePeriod(member) {
        // set member fee rate
        creditTerms[member].feeRate = feeRate;
        // set member minimum Income to Debt ratio
        creditTerms[member].minITD = minITD;
        // initialize credit line
        stableCredit.createCreditLine(member, creditLimit, balance);
        // initialize credit period
        initializeCreditPeriod(member, block.timestamp + periodLength, graceLength);
        emit CreditTermsCreated(member, feeRate, minITD);
    }

    /// @notice enables network operators to update a given member's minimum ITD.
    /// @dev caller must have network operator role access.
    /// @param member address of member to update minimum ITD for.
    function updateMinItd(address member, uint256 minItd) external onlyIssuer {
        creditTerms[member].minITD = minItd;
        emit MinITDUpdated(member, minItd);
    }

    /// @notice enables network operators to update a given member's rebalanced status.
    /// @dev caller must have network operator role access.
    /// @param member address of member to update rebalanced status for.
    /// @param feeRate new fee rate for member.
    function updateFeeRate(address member, uint256 feeRate) external onlyIssuer {
        creditTerms[member].feeRate = feeRate;
        emit FeeRateUpdated(member, feeRate);
    }

    /// @notice responsible for initializing the given member's credit period.
    /// @param member address of member to initialize credit period for.
    /// @param periodExpiration timestamp of when the credit period expires.
    /// @param graceLength timestamp of when the grace period expires.
    function _initializeCreditPeriod(address member, uint256 periodExpiration, uint256 graceLength)
        internal
        override
    {
        // initialize credit terms
        creditTerms[member].rebalanced = false;
        creditTerms[member].periodIncome = 0;
        super._initializeCreditPeriod(member, periodExpiration, graceLength);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /// @notice called with each stable credit transaction to validate the transaction and update
    /// credit term state.
    /// @dev Hook that is called before any transfer of credits and credit line state sync.
    /// @param from address of transaction sender.
    /// @param to address of transaction recipient.
    /// @param amount credits being transferred.
    /// @return whether the transaction is valid.
    function _validateTransaction(address from, address to, uint256 amount)
        internal
        override
        returns (bool)
    {
        // update recipients terms if credit period is initialized.
        if (periodInitialized(to)) {
            updateMemberTerms(to, amount);
        }
        // if period is paused for member, validate member
        if (creditPeriods[from].paused) return true;
        // validate credit period
        return super._validateTransaction(from, to, amount);
    }

    /// @notice called when a member's credit period has expired
    /// @dev deletes credit terms and emits a default event if caller is in default.
    /// @param member address of member to expire.
    /// @return true if member is not in default, false if member is in default.
    function expireCreditPeriod(address member) internal override returns (bool) {
        // require member is not in active period (either in grace or expired)
        require(!inActivePeriod(member), "Credit: period not expired");
        // if member is in compliance, re-underwrite, reset terms, and initialize new period
        if (inCompliance(member)) {
            // TODO: re-underwrite
            // reset terms
            creditTerms[member].rebalanced = false;
            creditTerms[member].periodIncome = 0;
            CreditPeriod memory period = creditPeriods[member];
            uint256 newExpiration = block.timestamp + (period.expiration - period.issuedAt);
            // start new credit period
            _initializeCreditPeriod(member, newExpiration, period.graceLength);
            return true;
        }
        return super.expireCreditPeriod(member);
    }

    /// @notice updates a given member's credit terms states: income and rebalanced.
    /// @param member address of member to update terms for.
    /// @param income amount of income to add to period income.
    function updateMemberTerms(address member, uint256 income) private {
        // record new period income
        creditTerms[member].periodIncome += income;
        // update rebalanced status if possible
        if (income >= stableCredit.creditBalanceOf(member)) {
            creditTerms[member].rebalanced = true;
        }

        emit CreditTermsUpdated(member, income, creditTerms[member].rebalanced);
    }
}
