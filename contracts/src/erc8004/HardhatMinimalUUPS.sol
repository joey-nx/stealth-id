// SPDX-License-Identifier: MIT
// Source: https://github.com/erc-8004/erc-8004-contracts
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title HardhatMinimalUUPS
 * @dev Minimal UUPS placeholder for proxy deployment.
 *      Used as initial implementation before upgrading to real registries.
 */
contract HardhatMinimalUUPS is OwnableUpgradeable, UUPSUpgradeable {
    address private _identityRegistry;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address identityRegistry_) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        _identityRegistry = identityRegistry_;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getVersion() external pure returns (string memory) {
        return "0.0.1";
    }
}
