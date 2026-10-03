// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {SimpleStablecoin} from "./SimpleStablecoin.sol";

/// @title Peg Stability Module
/// @notice Provides a fee-free 1:1 swap between USDC and sUSD.
contract PegStabilityModule {
    using SafeERC20 for IERC20;

    IERC20 public immutable reserve;
    SimpleStablecoin public immutable stable;

    event SwappedUSDCForSUSD(address indexed user, uint256 amount);
    event SwappedSUSDForUSDC(address indexed user, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientReserves();

    constructor(IERC20 reserve_, SimpleStablecoin stable_) {
        if (address(reserve_) == address(0) || address(stable_) == address(0)) {
            revert ZeroAddress();
        }

        reserve = reserve_;
        stable = stable_;
    }

    /// @notice Deposit USDC and receive the same amount of sUSD.
    function swapUSDCForSUSD(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        reserve.safeTransferFrom(msg.sender, address(this), amount);
        stable.mint(msg.sender, amount);

        emit SwappedUSDCForSUSD(msg.sender, amount);
    }

    /// @notice Burn sUSD and receive the same amount of USDC.
    function swapSUSDForUSDC(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (amount > reserve.balanceOf(address(this))) revert InsufficientReserves();

        stable.burn(msg.sender, amount);
        reserve.safeTransfer(msg.sender, amount);

        emit SwappedSUSDForUSDC(msg.sender, amount);
    }

    function totalReserves() external view returns (uint256) {
        return reserve.balanceOf(address(this));
    }
}