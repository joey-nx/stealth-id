// SPDX-License-Identifier: MIT
// Source: https://github.com/erc-8004/erc-8004-contracts
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol" as OZProxy;

contract ERC1967Proxy is OZProxy.ERC1967Proxy {
    constructor(address implementation, bytes memory _data) OZProxy.ERC1967Proxy(implementation, _data) {}
}
