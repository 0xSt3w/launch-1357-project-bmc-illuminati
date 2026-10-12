// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StakingFixture, BMCStaking, IBMCIlluminatiPass} from "./Base.t.sol";

contract SettlementTest is StakingFixture {
    function setUp() public override {
        super.setUp();
        _activate();
    }

    function testUnusedProgramReturnsOnlyRewardsToTreasuryAfterExpiry() public {
        _advance(DURATION);
        vm.startPrank(address(treasury));
        staking.recoverUnallocated(0);
        staking.recoverReserve(FUNDING / 20, 0);
        vm.expectRevert(BMCStaking.InvalidAmount.selector);
        staking.recoverUnallocated(0);
        vm.expectRevert(BMCStaking.InvalidAmount.selector);
        staking.recoverRemainder(0);
        vm.stopPrank();
        assertEq(staking.rewardReserve(), 0);
        assertEq(staking.totalTreasuryRecovered(), FUNDING);
        _assertConservation();
    }

    function testCannotRecoverIdleEmissionsOrDustEarly() public {
        vm.startPrank(address(treasury));
        vm.expectRevert(BMCStaking.ProgramNotEnded.selector);
        staking.recoverUnallocated(0);
        vm.expectRevert(BMCStaking.ProgramNotEnded.selector);
        staking.recoverRemainder(0);
        vm.stopPrank();
    }

    function testIdleRecoveryLeavesPrincipalAndUnclaimedRewardsUntouched() public {
        _advance(DURATION / 2);
        _deposit(alice, 100 ether);
        _mintStake(alice, 1, IBMCIlluminatiPass.Tier.LegendaryGenesis);
        _advance(DURATION / 2);
        uint256 pending = _pending(alice);
        vm.prank(address(treasury));
        staking.recoverUnallocated(0);
        assertEq(_pending(alice), pending);
        assertEq(staking.totalTreasuryRecovered(), FUNDING * 95 / 200);
        assertEq(staking.totalPrincipal(), 100 ether);
        _claim(alice);
        _assertConservation();
    }

    function testFinalRemainderRequiresAllPositionsExited() public {
        _deposit(alice, 100 ether);
        _mintStake(alice, 1, IBMCIlluminatiPass.Tier.LegendaryGenesis);
        _advance(DURATION);
        vm.prank(address(treasury));
        vm.expectRevert(BMCStaking.PositionsRemain.selector);
        staking.recoverRemainder(0);
        vm.prank(alice);
        staking.withdrawBMC(100 ether, 0);
        vm.prank(address(treasury));
        vm.expectRevert(BMCStaking.PositionsRemain.selector);
        staking.recoverRemainder(0);
    }

    function testDustRecoveryPreservesEveryAccruedWholeUnitIndefinitely() public {
        _deposit(alice, 101 ether);
        _deposit(bob, 207 ether);
        _mintStake(alice, 1, IBMCIlluminatiPass.Tier.LegendaryGenesis);
       
_mintStake(bob, 173, IBMCIlluminatiPass.Tier.Genesis);

        _advance(DURATION);
        vm.startPrank(alice);
        staking.withdrawBMC(101 ether, 0);
        staking.withdrawNFT(1, alice);
        vm.stopPrank();
        vm.startPrank(bob);
        staking.withdrawBMC(207 ether, 0);
        staking.withdrawNFT(173, bob);
        vm.stopPrank();
        uint256 aliceEarned = _pending(alice);
        uint256 bobEarned = _pending(bob);
        vm.startPrank(address(treasury));
        staking.recoverRemainder(0);
        staking.recoverReserve(FUNDING / 20, 0);
        vm.expectRevert(BMCStaking.InvalidAmount.selector);
        staking.recoverRemainder(0);
        vm.expectRevert(BMCStaking.InvalidAmount.selector);
        staking.recoverUnallocated(0);
        vm.stopPrank();
        assertEq(staking.rewardReserve(), aliceEarned + bobEarned);
        _advance(5000 days);
        assertEq(_claim(alice), aliceEarned);
        assertEq(_claim(bob), bobEarned);
        assertEq(token.balanceOf(address(staking)), 0);
        _assertConservation();
    }

    function testFinalRecoveryAfterPartialIdleRecoveryCannotRecoverTwice() public {
        _advance(DURATION / 2);
        _deposit(alice, 103 ether);
        _advance(DURATION / 2);
        vm.prank(address(treasury));
        staking.recoverUnallocated(0);
        vm.prank(alice);
        staking.withdrawBMC(103 ether, 0);
        uint256 earned = _pending(alice);
        vm.startPrank(address(treasury));
        staking.recoverRemainder(0);
        staking.recoverReserve(FUNDING / 20, 0);
        vm.stopPrank();
        assertEq(staking.rewardReserve(), earned);
        _claim(alice);
        assertEq(token.balanceOf(address(staking)), 0);
        _assertConservation();
    }

    function testRepeatedClaimsCannotExceedBudgetsAndDoNotEraseAccountFractions() public {
        _deposit(alice, 103 ether);
        _deposit(bob, 107 ether);
        uint256 paid;
        for (uint256 i; i < 100; ++i) {
            _advance(DURATION / 100);
            paid += _claim(alice);
        }
        uint256 budget = FUNDING * 55 / 100;
        assertApproxEqAbs(paid, budget * 103 / 210, 2);
        assertApproxEqAbs(_claim(bob), budget * 107 / 210, 2);
        assertLe(staking.totalRewardsPaid(), budget);
        _assertConservation();
    }

    function testTinyRewardsPreservePerAccountFractionAcrossZeroValueCheckpoints() public {
        // Use a separate small raw-unit program to stress floor arithmetic.
        staking = new BMCStaking(address(treasury));
        _configure();
        _fund(20);
        vm.prank(address(treasury));
        staking.activate();
        _deposit(alice, 3);
        _deposit(bob, 7);
        for (uint256 i; i < 9; ++i) {
            _advance(DURATION / 10);
            // Adding one unit checkpoints old rewards before changing weight.
            _deposit(alice, 1);
        }
        _advance(DURATION / 10);
        uint256 aliceReward = _pending(alice);
        uint256 bobReward = _pending(bob);
        assertGt(aliceReward, 0);
        assertGt(bobReward, 0);
        assertLe(aliceReward + bobReward, 11);
        _claim(alice);
        _claim(bob);
        _assertConservation();
    }
}
