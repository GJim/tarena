// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPriceOracle {
    function getPrice(address asset) external view returns (uint);
    function setPrice(address asset, uint priceMantissa) external;
}

contract SimplePriceOracle is IPriceOracle {
    mapping(address => uint) prices;
    event PricePosted(address asset, uint previousPriceMantissa, uint requestedPriceMantissa, uint newPriceMantissa);

    function getPrice(address asset) public view returns (uint) {
        return prices[asset];
    }

    function setPrice(address asset, uint priceMantissa) public {
        emit PricePosted(asset, prices[asset], priceMantissa, priceMantissa);
        prices[asset] = priceMantissa;
    }
}
