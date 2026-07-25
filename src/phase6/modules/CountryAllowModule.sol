// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AbstractModule} from "./AbstractModule.sol";
import {IIdentityRegistry} from "../../phase5/interfaces/IIdentityRegistry.sol";

/// @title CountryAllowModule — "the receiver must reside in an allowed country".
/// @notice Rule #2 from the plan ("Must be an EU resident"). It reads the
///         receiver's country from the Phase 5 Identity Registry, so it depends
///         on the investor being registered with a country code.
///
/// Stateless: no hooks needed, just a per-country allow-list + a registry read.
contract CountryAllowModule is AbstractModule {
    IIdentityRegistry public identityRegistry;
    mapping(uint16 country => bool allowed) private _allowed;

    event CountryAllowed(uint16 indexed country);
    event CountryDisallowed(uint16 indexed country);

    constructor(IIdentityRegistry identityRegistry_) {
        identityRegistry = identityRegistry_;
    }

    function allowCountry(uint16 country) external onlyOwner {
        _allowed[country] = true;
        emit CountryAllowed(country);
    }

    function disallowCountry(uint16 country) external onlyOwner {
        _allowed[country] = false;
        emit CountryDisallowed(country);
    }

    function isCountryAllowed(uint16 country) external view returns (bool) {
        return _allowed[country];
    }

    function moduleCheck(address, address to, uint256) external view override returns (bool) {
        return _allowed[identityRegistry.investorCountry(to)];
    }

    function name() external pure override returns (string memory) {
        return "CountryAllowModule";
    }
}
