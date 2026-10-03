// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title A minimal fiat-collateralized stablecoin
/// @notice "Stability" does not come from this code, it comes from the mint/redeem loop.
///         This contract only decides two things: 1) who may mint (MINTER_ROLE),
///         2) whether everything can be frozen in a crisis (PAUSER_ROLE).
contract SimpleStablecoin is ERC20, AccessControl, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    error ZeroAddress();
    error ZeroAmount();

    /// @param admin initial admin; receives all three roles at once
    constructor(address admin) ERC20("Simple USD", "sUSD") {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        _mint(to, amount);
    }

    /// @notice Burn tokens held by the authorized caller.
/// @dev A minter may no longer choose an arbitrary account to burn from.
///      A vault must first receive tokens through transferFrom, requiring allowance.
    function burn(uint256 amount) external onlyRole(MINTER_ROLE) {
    if (amount == 0) revert ZeroAmount();
    _burn(msg.sender, amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @dev Every balance change routes through here, so pausing freezes transfers,
    ///      minting and redemption all at once.
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20)
        whenNotPaused
    {
        super._update(from, to, value);
    }
}
