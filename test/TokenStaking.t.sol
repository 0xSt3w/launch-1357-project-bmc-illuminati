// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StakingFixture, BMCStaking} from "./Base.t.sol";

contract TokenStakingTest is StakingFixture {
    function setUp() public override {
        super.setUp();
        _activate();
    }

    function testDepositClaimAndWithdraw() public {
        uint256 balanceBefore = token.balanceOf(alice);
        assertEq(_deposit(alice, 100 ether), 100 ether);
        assertEq(_principal(alice), 100 ether);
        assertEq(staking.totalPrincipal(), 100 ether);
        assertEq(token.allowance(alice, address(staking)), 0);
        _advance(DURATION / 2);
        uint256 earned = _pending(alice);
        assertApproxEqAbs(earned, FUNDING * 55 / 200, 1);
        assertEq(_claim(alice), earned);
        vm.prank(alice);
        staking.withdrawBMC(100 ether, 100 ether);
        assertEq(token.balanceOf(alice), balanceBefore + earned);
        assertEq(staking.totalPrincipal(), 0);
        _assertConservation();
    }

    function testStaggeredDepositsReceiveOnlyTheirTimeWeightedShare() public {
        _deposit(alice, 100 ether);
        _advance(DURATION / 2);
        _deposit(bob, 300 ether);
        assertEq(_pending(bob), 0);
        _advance(DURATION / 2);
        uint256 budget = FUNDING * 55 / 100;
        assertApproxEqAbs(_claim(alice), budget * 5 / 8, 2);
        assertApproxEqAbs(_claim(bob), budget * 3 / 8, 2);
        _assertConservation();
    }

    function testPartialWithdrawalsCheckpointOldWeight() public {
        _deposit(alice, 300 ether);
        _deposit(bob, 100 ether);
        _advance(DURATION / 2);
        vm.prank(alice);
        staking.withdrawBMC(200 ether, 200 ether);
        _advance(DURATION / 2);
        uint256 budget = FUNDING * 55 / 100;
        assertApproxEqAbs(_claim(alice), budget * 5 / 8, 2);
        assertApproxEqAbs(_claim(bob), budget * 3 / 8, 2);
        assertEq(staking.totalPrincipal(), 200 ether);
        _assertConservation();
    }

    function testLateDepositsDoNotCaptureIdleEmissions() public {
        _advance(DURATION / 2);
        _deposit(alice, 100 ether);
        assertEq(_pending(alice), 0);
        _advance(DURATION / 2);
        assertApproxEqAbs(_claim(alice), FUNDING * 55 / 200, 1);
        assertEq(staking.poolInfo(0).allocated, FUNDING * 55 / 200);
        _assertConservation();
    }

    function testWithdrawnAccountsKeepEarnedRewardsButStopAccruing() public {
        _deposit(alice, 100 ether);
        _advance(DURATION / 3);
        vm.prank(alice);
        staking.withdrawBMC(100 ether, 0);
        uint256 earned = _pending(alice);
        _advance(DURATION);
        assertEq(_pending(alice), earned);
        assertEq(_claim(alice), earned);
        _assertConservation();
    }

    function testSameBlockRoundTripAndClaimRejected() public {
        _deposit(alice, 100 ether);
        vm.startPrank(alice);
        vm.expectRevert(BMCStaking.SameBlock.selector);
        staking.withdrawBMC(1, 0);
        vm.expectRevert(BMCStaking.SameBlock.selector);
        staking.claim(0);
        vm.stopPrank();
        assertEq(_pending(alice), 0);
        vm.roll(block.number + 1);
        vm.prank(alice);
        staking.withdrawBMC(100 ether, 0);
        assertEq(_pending(alice), 0);
        _assertConservation();
    }

    function testNobodyElseCanWithdrawOrClaimAnOwnersBalance() public {
        _deposit(alice, 100 ether);
        _advance(1 days);
        vm.startPrank(bob);
        vm.expectRevert(BMCStaking.InvalidAmount.selector);
        staking.withdrawBMC(100 ether, 0);
        vm.expectRevert(BMCStaking.NothingToClaim.selector);
        staking.claim(0);
        vm.stopPrank();
        assertEq(_principal(alice), 100 ether);
        assertGt(_pending(alice), 0);
    }

    function testZeroOversizedAndInsufficientAllowanceDepositsRevert() public {
        vm.startPrank(alice);
        vm.expectRevert(BMCStaking.InvalidAmount.selector);
        staking.stakeBMC(0, 0);
        vm.expectRevert(BMCStaking.InvalidAmount.selector);
        staking.stakeBMC(type(uint256).max, 0);
        vm.expectRevert();
        staking.stakeBMC(100, 0);
        vm.expectRevert(BMCStaking.InvalidAmount.selector);
        staking.withdrawBMC(0, 0);
        vm.stopPrank();
    }

    function testProgramEndCapsRewardsAndKeepsWithdrawalsAndClaimsOpen() public {
        _deposit(alice, 100 ether);
        _advance(DURATION);
        uint256 earned = _pending(alice);
        _advance(1000 days);
        assertEq(_pending(alice), earned);
        vm.prank(bob);
        vm.expectRevert(BMCStaking.ProgramEnded.selector);
        staking.stakeBMC(100, 0);
        assertApproxEqAbs(_claim(alice), FUNDING * 55 / 100, 1);
        vm.prank(alice);
        vm.expectRevert(BMCStaking.NothingToClaim.selector);
        staking.claim(0);
        vm.prank(alice);
        staking.withdrawBMC(100 ether, 100 ether);
        _assertConservation();
    }

    function testPauseBlocksNewStakesButNotExitsOrRewards() public {
        _deposit(alice, 100 ether);
        _advance(1 days);
        vm.prank(address(treasury));
        staking.setDepositsPaused(true);
        vm.prank(bob);
        vm.expectRevert(BMCStaking.Paused.selector);
        staking.stakeBMC(100, 0);
        vm.prank(bob);
        vm.expectRevert(BMCStaking.Paused.selector);
        staking.stakeNFT(41);
        _claim(alice);
        vm.prank(alice);
        staking.withdrawBMC(100 ether, 0);
        vm.prank(address(treasury));
        staking.setDepositsPaused(false);
        _deposit(bob, 1 ether);
        _assertConservation();
    }

    function testBrokenTreasuryCannotBlockPrincipalWithdrawals() public {
        _deposit(alice, 100 ether);
        _advance(1 days);
        treasury.setThreshold(1);
        vm.prank(alice);
        staking.withdrawBMC(100 ether, 0);
        _claim(alice);
        _assertConservation();
    }

    function testRewardReserveDeficitDoesNotTrapSolventPrincipal() public {
        _deposit(alice, 100 ether);
        _advance(1 days);
        token.burn(address(staking), FUNDING / 2);
        uint256 owed = _pending(alice);
        vm.prank(alice);
        vm.expectRevert(BMCStaking.Insolvent.selector);
        staking.claim(0);
        assertEq(_pending(alice), owed);
        vm.prank(bob);
        vm.expectRevert(BMCStaking.Insolvent.selector);
        staking.stakeBMC(100, 0);
        vm.prank(alice);
        staking.withdrawBMC(100 ether, 100 ether);
        assertEq(staking.totalPrincipal(), 0);
        assertEq(_pending(alice), owed);
    }

    function testFuzzProportionalRewardsAndPrincipalConservation(uint96 first, uint96 second, uint32 elapsed)
        public
    {
        uint256 a = bound(first, 1, 1_000_000 ether);
        uint256 b = bound(second, 1, 1_000_000 ether);
        uint256 time = bound(elapsed, 1, DURATION);
        _deposit(alice, a);
        _deposit(bob, b);
        _advance(time);
        uint256 emission = (FUNDING * 55 / 100) * time / DURATION;
        uint256 aliceReward = _pending(alice);
        uint256 bobReward = _pending(bob);
        assertApproxEqAbs(aliceReward, emission * a / (a + b), 1);
        assertApproxEqAbs(bobReward, emission * b / (a + b), 1);
        if (aliceReward != 0) _claim(alice);
        if (bobReward != 0) _claim(bob);
        vm.prank(alice);
        staking.withdrawBMC(a, a);
        vm.prank(bob);
        staking.withdrawBMC(b, b);
        assertEq(staking.totalPrincipal(), 0);
        _assertConservation();
    }
}
