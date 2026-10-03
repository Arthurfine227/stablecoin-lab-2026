// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {MockUSDC} from "../src/MockUSDC.sol";
import {SimpleStablecoin} from "../src/SimpleStablecoin.sol";
import {Vault} from "../src/Vault.sol";

contract StablecoinTest is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;

    address internal admin = address(this);
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant AMOUNT = 1_000e6;

    function setUp() public {
        usdc = new MockUSDC();
        stable = new SimpleStablecoin(admin);
        vault = new Vault(usdc, stable);
        stable.grantRole(stable.MINTER_ROLE(), address(vault));
    }

    // ---------- happy path ----------

    function test_Deposit_MintsOneToOne() public {
        usdc.faucet(alice, AMOUNT);

        vm.startPrank(alice);
        usdc.approve(address(vault), AMOUNT);
        vault.deposit(AMOUNT);
        vm.stopPrank();

        assertEq(stable.balanceOf(alice), AMOUNT, "should mint 1:1");
        assertEq(usdc.balanceOf(address(vault)), AMOUNT, "collateral should be escrowed in the vault");
        assertEq(vault.totalCollateral(), stable.totalSupply(), "collateral should fully back the supply");
    }

    function test_Redeem_BurnsAndReturnsCollateral() public {
        usdc.faucet(alice, AMOUNT);

        vm.startPrank(alice);
        usdc.approve(address(vault), AMOUNT);
        vault.deposit(AMOUNT);
        stable.approve(address(vault), AMOUNT);
        vault.redeem(AMOUNT);
        vm.stopPrank();

        assertEq(stable.balanceOf(alice), 0, "stablecoin should be burned");
        assertEq(stable.totalSupply(), 0, "total supply should be back to zero");
        assertEq(usdc.balanceOf(alice), AMOUNT, "collateral should come back in full");
        assertEq(usdc.balanceOf(address(vault)), 0, "vault should be empty");
    }

    // ---------- the in-class attack demo ----------

    /// @dev The step run live in class: minting by a non-MINTER must revert
    function test_Mint_RevertsForNonMinter() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                stable.MINTER_ROLE()
            )
        );
        vm.prank(attacker);
        stable.mint(attacker, AMOUNT);
    }

    function test_Pause_BlocksTransfers() public {
        usdc.faucet(alice, AMOUNT);
        vm.startPrank(alice);
        usdc.approve(address(vault), AMOUNT);
        vault.deposit(AMOUNT);
        vm.stopPrank();

        stable.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(alice);
        stable.transfer(attacker, 1e6);
    }

    // ---------- invariant ----------

    /// @dev At any legitimate deposit size, collateral must stay >= the stablecoin supply
    function testFuzz_Invariant_CollateralBacksSupply(uint96 raw) public {
        uint256 amount = uint256(raw) % 1_000_000e6;
        vm.assume(amount > 0);

        usdc.faucet(alice, amount);

        vm.startPrank(alice);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();

        assertGe(vault.totalCollateral(), stable.totalSupply(), "collateral does not cover the supply");
    }

    // ---------- edge cases ----------

    function test_Redeem_RevertsOnZeroAmount() public {
        vm.expectRevert(Vault.ZeroAmount.selector);
        vm.prank(alice);
        vault.redeem(0);
    }

    function test_Redeem_RevertsOnEmptyVault() public {
        // The vault holds no collateral, so redeeming must revert rather than pay out of
        // thin air
        vm.expectRevert(Vault.InsufficientCollateral.selector);
        vm.prank(attacker);
        vault.redeem(1e6);
    }
}
