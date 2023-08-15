// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interface/IAmbassador.sol";
import "../interface/ICreditPool.sol";

interface IImpactStableCredit {
    /// @dev the ambassador contract which manages the network's ambassador program
    function ambassador() external view returns (IAmbassador);

    /* ========== EVENTS ========== */
    event AmbassadorUpdated(address ambassador);
    event CreditPoolUpdated(address creditPool);
    event CreditLineStateUpdated(
        address sender,
        address recipient,
        int256 senderITD,
        int256 recipientITD,
        bool senderCompliance,
        bool recipientCompliance
    );
}
