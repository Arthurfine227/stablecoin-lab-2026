// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockUSDC} from "../src/MockUSDC.sol";
import {SimpleStablecoin} from "../src/SimpleStablecoin.sol";
import {PegStabilityModule} from "../src/PegStabilityModule.sol";

contract PegStabilityModuleTest is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    PegStabilityModule internal psm;

    address internal alice = makeAddr("alice");

    function setUp() public {
        usdc = new MockUSDC();
        stable = new SimpleStablecoin(address(this));
        psm = new PegStabilityModule(usdc, stable);

        stable.grantRole(stable.MINTER_ROLE(), address(psm));
        usdc.faucet(alice, 1_000_000e6);
    }

    function test_SwapUSDCForSUSD_IsOneToOne() public {
        uint256 amount = 1_000e6;

        vm.startPrank(alice);
        usdc.approve(address(psm), amount);
        psm.swapUSDCForSUSD(amount);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(psm)), amount);
        assertEq(stable.balanceOf(alice), amount);
        assertEq(stable.totalSupply(), amount);
        assertEq(psm.totalReserves(), stable.totalSupply());
    }

    function test_RoundTrip_ReturnsUSDCAndBurnsSUSD() public {
        uint256 amount = 1_000e6;

        vm.startPrank(alice);
        usdc.approve(address(psm), amount);
        psm.swapUSDCForSUSD(amount);
        psm.swapSUSDForUSDC(amount);
        vm.stopPrank();

        assertEq(usdc.balanceOf(alice), 1_000_000e6);
        assertEq(usdc.balanceOf(address(psm)), 0);
        assertEq(stable.balanceOf(alice), 0);
        assertEq(stable.totalSupply(), 0);
    }

    function test_SwapsRevertOnZeroAmount() public {
        vm.startPrank(alice);

        vm.expectRevert(PegStabilityModule.ZeroAmount.selector);
        psm.swapUSDCForSUSD(0);

        vm.expectRevert(PegStabilityModule.ZeroAmount.selector);
        psm.swapSUSDForUSDC(0);

        vm.stopPrank();
    }

    function test_SwapSUSDForUSDC_RevertsWithoutReserves() public {
        uint256 amount = 1e6;
        stable.mint(alice, amount);

        vm.expectRevert(PegStabilityModule.InsufficientReserves.selector);
        vm.prank(alice);
        psm.swapSUSDForUSDC(amount);
    }

    function testFuzz_RoundTripPreservesBacking(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000e6);

        vm.startPrank(alice);
        usdc.approve(address(psm), amount);
        psm.swapUSDCForSUSD(amount);

        assertEq(psm.totalReserves(), stable.totalSupply());

        psm.swapSUSDForUSDC(amount);
        vm.stopPrank();

        assertEq(psm.totalReserves(), 0);
        assertEq(stable.totalSupply(), 0);
    }
}