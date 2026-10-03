// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {SimpleStablecoin} from "./SimpleStablecoin.sol";

/// @title The collateral vault — the mint/redeem loop
/// @notice Deposit 1 unit of collateral to mint 1 unit of stablecoin; burn 1 unit of
///         stablecoin to take 1 unit of collateral back. This arbitrage loop is the peg's
///         first line of defence: once the coin drifts off peg, arbitrageurs step in and
///         pull it back.
contract Vault {
    using SafeERC20 for IERC20;

    IERC20 public immutable collateral;
    SimpleStablecoin public immutable stable;

    event Deposited(address indexed user, uint256 amount);
    event Redeemed(address indexed user, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientCollateral();

    /// @dev This contract must be granted MINTER_ROLE on `stable`, or deposit/redeem reverts
    constructor(IERC20 collateral_, SimpleStablecoin stable_) {
        if (address(collateral_) == address(0) || address(stable_) == address(0)) {
            revert ZeroAddress();
        }
        collateral = collateral_;
        stable = stable_;
    }

    /// @notice Deposit collateral and mint stablecoin 1:1
    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        collateral.safeTransferFrom(msg.sender, address(this), amount);
        stable.mint(msg.sender, amount);
        emit Deposited(msg.sender, amount);
    }

    /// @notice Burn stablecoin and take back an equal amount of collateral
    /// @dev Burn first, transfer second (checks-effects-interactions), to avoid reentrancy
    function redeem(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (amount > collateral.balanceOf(address(this))) revert InsufficientCollateral();
        IERC20(address(stable)).safeTransferFrom(msg.sender, address(this), amount);
        stable.burn(amount);
        collateral.safeTransfer(msg.sender, amount);
        emit Redeemed(msg.sender, amount);
    }

    function totalCollateral() external view returns (uint256) {
        return collateral.balanceOf(address(this));
    }
}
