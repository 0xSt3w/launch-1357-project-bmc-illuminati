// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StakingFixture, BMCStaking} from "./Base.t.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TransferFeesTest is StakingFixture {
    function testFundingBudgetsUseNetReceipt() public {
        _configure();
        token.setFee(700);
        uint256 received = _fund(FUNDING);
        assertEq(received, FUNDING * 93 / 100);
        vm.prank(address(treasury));
        staking.activate();
        assertEq(staking.totalFunded(), received);
        assertEq(staking.poolInfo(0).budget, received * 55 / 100);
        assertEq(staking.poolInfo(1).budget, received * 25 / 100);
        assertEq(staking.poolInfo(2).budget, received * 15 / 100);
        _assertConservation();
    }

    function testDepositWithdrawalAndClaimFeesNeverSpendAnotherOwnersPrincipal() public {
        _activate();
        token.setFee(1000);
        uint256 credited = _deposit(alice, 1000 ether);
        assertEq(credited, 900 ether);
        assertEq(_principal(alice), 900 ether);
        _deposit(bob, 1000 ether);
        _advance(DURATION);
        uint256 reward = _pending(alice);
        uint256 balanceBefore = token.balanceOf(alice);
        vm.prank(alice);
        (uint256 gross, uint256 net) = staking.claim(reward * 9 / 10);
        assertEq(gross, reward);
        assertEq(net, reward - reward / 10);
        assertEq(token.balanceOf(alice) - balanceBefore, net);
        vm.prank(alice);
        uint256 withdrawn = staking.withdrawBMC(900 ether, 810 ether);
        assertEq(withdrawn, 810 ether);
        assertEq(_principal(bob), 900 ether);
        assertEq(staking.totalRewardsPaid(), gross);
        _assertConservation();
    }

    function testMinReceiptProtectsDepositAndFailureIsAtomic() public {
        _activate();
        token.setFee(100);
        uint256 balanceBefore = token.balanceOf(alice);
        vm.startPrank(alice);
        token.approve(address(staking), 100 ether);
        vm.expectRevert(BMCStaking.InsufficientReceived.selector);
        staking.stakeBMC(100 ether, 100 ether);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), balanceBefore);
        assertEq(_principal(alice), 0);
        _assertConservation();
    }

    function testMinReceiptProtectsFundingAndFailureIsAtomic() public {
        _configure();
        token.setFee(100);
        vm.startPrank(address(treasury));
        token.approve(address(staking), FUNDING);
        vm.expectRevert(BMCStaking.InsufficientReceived.selector);
        staking.fundRewards(FUNDING, FUNDING);
        vm.stopPrank();
        assertEq(staking.totalFunded(), 0);
        assertEq(staking.rewardReserve(), 0);
        assertEq(token.balanceOf(address(staking)), 0);
    }

    function testMinReceiptProtectsClaimsAndWithdrawalsAfterFeeIncrease() public {
        _activate();
        _deposit(alice, 100 ether);
        _advance(30 days);
        uint256 reward = _pending(alice);
        token.setFee(5000);
        vm.startPrank(alice);
        vm.expectRevert(BMCStaking.InsufficientReceived.selector);
        staking.claim(reward);
        vm.expectRevert(BMCStaking.InsufficientReceived.selector);
        staking.withdrawBMC(100 ether, 100 ether);
        vm.stopPrank();
        assertEq(_pending(alice), reward);
        assertEq(_principal(alice), 100 ether);
        assertEq(staking.totalRewardsPaid(), 0);
        _assertConservation();
    }

    function testNoReturnERC20TransfersSupportedAndFalseReturnsRevert() public {
        token.setReturnMode(2);
        _activate();
        _deposit(alice, 100 ether);
        _advance(1 days);
        _claim(alice);
        vm.prank(alice);
        staking.withdrawBMC(50 ether, 50 ether);
        token.setReturnMode(1);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        staking.withdrawBMC(50 ether, 0);
        token.approve(address(staking), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        staking.stakeBMC(1 ether, 0);
        vm.stopPrank();
        assertEq(_principal(alice), 50 ether);
        _assertConservation();
    }

    function testSurchargeCannotBePaidFromRewardReservesOrOtherPrincipal() public {
        _activate();
        _deposit(alice, 100 ether);
        _deposit(bob, 100 ether);
        _advance(1 days);
        token.setSurcharge(1000);
        vm.prank(alice);
        vm.expectRevert(BMCStaking.UnsupportedTokenBehavior.selector);
        staking.withdrawBMC(100 ether, 0);
        vm.prank(alice);
        vm.expectRevert(BMCStaking.UnsupportedTokenBehavior.selector);
        staking.claim(0);
        assertEq(_principal(alice), 100 ether);
        assertEq(staking.totalRewardsPaid(), 0);
        _assertConservation();
    }

    function testUnsupportedReflectionAndZeroReceiptRevert() public {
        _activate();
        token.setReflection(1000);
        vm.startPrank(alice);
        token.approve(address(staking), 100 ether);
        vm.expectRevert(BMCStaking.UnsupportedTokenBehavior.selector);
        staking.stakeBMC(100 ether, 0);
        vm.stopPrank();
        token.setReflection(0);
        token.setFee(10_000);
        vm.prank(alice);
        vm.expectRevert(BMCStaking.UnsupportedTokenBehavior.selector);
        staking.stakeBMC(100 ether, 0);
        assertEq(_principal(alice), 0);
        _assertConservation();
    }

    function testTreasuryRecoveryFeesAreDebitedOnlyFromItsAllocation() public {
        _activate();
        token.setFee(900);
        uint256 reserve = staking.uncommittedReserve();
        uint256 balanceBefore = token.balanceOf(address(treasury));
        vm.prank(address(treasury));
        staking.recoverReserve(reserve, reserve * 91 / 100);
        assertEq(token.balanceOf(address(treasury)) - balanceBefore, reserve * 91 / 100);
        assertEq(staking.totalTreasuryRecovered(), reserve);
        _assertConservation();
    }

    function testRawUnitAccountingWorksWithoutAssumingEighteenDecimals() public {
        token.setDecimals(6);
        _configure();
        vm.prank(address(treasury));
        staking.configureProgram(DURATION, 100e6, 500e6);
        _fund(1000e6);
        vm.prank(address(treasury));
        staking.activate();
        _deposit(alice, 100e6);
        _advance(DURATION);
        assertApproxEqAbs(_claim(alice), 550e6, 1);
        vm.prank(alice);
        staking.withdrawBMC(100e6, 100e6);
        _assertConservation();
    }

    function testFuzzFeeOnTransferConservesGrossBudgets(uint16 fee, uint96 principal) public {
        _activate();
        uint256 feeBps = bound(fee, 0, 9999);
        uint256 requested = bound(principal, 10_000, 1_000_000 ether);
        token.setFee(feeBps);
        uint256 credited = _deposit(alice, requested);
        assertEq(credited, requested - requested * feeBps / 10_000);
        _advance(DURATION);
        _claim(alice);
        vm.prank(alice);
        uint256 returned = staking.withdrawBMC(credited, 0);
        assertEq(returned, credited - credited * feeBps / 10_000);
        assertEq(staking.totalPrincipal(), 0);
        _assertConservation();
    }
}
