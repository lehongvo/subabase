// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockIXToken — ERC-20 test token for IX Metaverse Contract System
/// @notice A simple ERC-20 token with public mint for testing purposes.
///         Represents "IX Point" (IXP) with 18 decimals.
/// @dev NOT for production use. Anyone can mint any amount.
contract MockIXToken is ERC20 {
    /// @notice Emitted when tokens are minted
    event TokensMinted(address indexed to, uint256 amount);

    /// @notice Deploy the mock token with name "IX Point" and symbol "IXP"
    constructor() ERC20("IX Point", "IXP") {}

    /// @notice Mint tokens to any address (public, for testing only)
    /// @dev No access control — anyone can mint.
    /// @param to Recipient address
    /// @param amount Amount to mint (18 decimals)
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /// @notice Returns the number of decimals (18)
    /// @return decimals_ Always 18
    function decimals() public pure override returns (uint8 decimals_) {
        return 18;
    }
}
