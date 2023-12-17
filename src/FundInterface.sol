// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract FundStorage {
    /**
     * @dev Guard variable for re-entrancy checks
     */
    bool internal _notEntered;

    /**
     * @notice name of this fund
     */
    string public name;

    /**
     * @notice Container for invest balance information
     * @member principal Total balance, after applying the most recent balance-changing action
     * @member roi Global return on investment as of the most recent balance-changing action
     * @member stopLoss Investor stop loss mantissa
     * @member supportIncentive The incentive for supporter which help withdraw fund from stop loss
     */
    struct InvestSnapshot {
        uint principal;
        uint roi;
        uint stopLoss;
        uint supportIncentive;
    }

    // Official record of account investment for each account
    mapping (address => InvestSnapshot) internal accountInvests;

    /**
     * @notice Trader for this fund
     */
    address public trader;

    /**
     * @notice Chip in this fund
     */
    address public chip;

    /**
     * @notice Target in this fund
     */
    address public target;

    /**
     * @notice DEX in this fund
     */
    address public dex;

    /**
     * @notice Last total value mantissa in this fund (scaled by 1e18)
     */
    uint public lastTotalValue;

    /**
     * @notice Return on investment mantissa in this fund (scaled by 1e18)
     */
    uint public roi;
}

abstract contract FundInterface is FundStorage {
    /**
     * @notice Indicator that this is a Fund contract (for inspection)
     */
    bool public constant isFund = true;

    /*** User Functions ***/
    function invest() virtual external returns (uint);
    function divest() virtual external returns (uint);

    /*** Trader Functions ***/
    function swap() virtual external returns (uint);
    function settle() virtual external returns (uint);

    /*** Supporter Functions ***/
    function helpDivest() virtual external returns (uint);
}

abstract contract PriceOracle {
    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    bool public constant isPriceOracle = true;

    /**
      * @notice Get the price of a asset
      * @param asset The asset address to get the price of
      * @return The asset price mantissa (scaled by 1e18).
      *  Zero means the price is unavailable.
      */
    function getPrice(address asset) virtual external view returns (uint);
}

