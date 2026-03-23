// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @title IXProxy - Thin wrapper around OZ TransparentUpgradeableProxy
/// @notice Exists solely to generate a Hardhat artifact for deployment scripts.
contract IXProxy is TransparentUpgradeableProxy {
    constructor(
        address logic,
        address initialOwner,
        bytes memory data
    ) TransparentUpgradeableProxy(logic, initialOwner, data) {}
}
