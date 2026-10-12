// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StakingFixture, BMCStaking, IBMCIlluminatiPass} from "./Base.t.sol";

contract CombinedStakingTest is StakingFixture {
    function setUp() public override {
        super.setUp();
        _activate();
    }

    function testTokenAndNFTAreBothRequiredAndDepositOrderDoesNotMatter() public {
        _deposit(alice, 1000 ether);
        _mintStake(bob, 41, IBMCIlluminatiPass.Tier.Standard);
        assertEq(_bonus(alice), 0);
        assertEq(_bonus(bob), 0);
        _mintStake(alice, 42, IBMCIlluminatiPass.Tier.Standard);
        _deposit(bob, 1000 ether);
        assertEq(_bonus(alice), 100 ether);
        assertEq(_bonus(bob), 100 ether);
        assertEq(staking.poolInfo(2).totalWeight, 200 ether);
        _advance(DURATION);
        uint256[3] memory pending = staking.pendingRewards(alice);
        assertApproxEqAbs(pending[2], FUNDING * 15 / 200, 1);
        _claim(alice);
        _claim(bob);
        _assertConservation();
    }

    function testMinimumIsMeasuredAfterTransferFees() public {
        _mintStake(alice, 41, IBMCIlluminatiPass.Tier.Standard);
        token.setFee(100);
        _deposit(alice, MINIMUM);
        assertEq(_principal(alice), 99 ether);
        assertEq(_bonus(alice), 0);
        _deposit(alice, 2 ether);
        assertEq(_principal(alice), 100.98 ether);
        assertEq(_bonus(alice), 20.196 ether);
        assertLe(_bonus(alice), _principal(alice) / 5);
    }

    function testBonusIsBoundedByBothPrincipalAndNFTLinkedExposure() public {
        _deposit(alice, 1000 ether);
        _mintStake(alice, 41, IBMCIlluminatiPass.Tier.Standard);
        assertEq(_bonus(alice), 100 ether); // min(1000, 1 * 500) / 5
        _mintStake(alice, 42, IBMCIlluminatiPass.Tier.RandomGenesis);
        assertEq(_bonus(alice), 200 ether); // min(1000, 3 * 500) / 5
        _mintStake(alice, 1, IBMCIlluminatiPass.Tier.LegendaryGenesis);
        assertEq(_bonus(alice), 200 ether); // extra NFTs cannot multiply the same principal
        _deposit(alice, 9000 ether);
        assertEq(_bonus(alice), 800 ether); // min(10000, 8 * 500) / 5
        assertLe(_bonus(alice), _principal(alice) / 5);
        _assertConservation();
    }

    function testLosingLastNFTStopsBonusImmediatelyAndRetainsEarnedBonus() public {
        _deposit(alice, 1000 ether);
        _mintStake(alice, 41, IBMCIlluminatiPass.Tier.Standard);
        _advance(DURATION / 2);
        vm.prank(alice);
        staking.withdrawNFT(41, alice);
        uint256[3] memory first = staking.pendingRewards(alice);
        assertEq(_bonus(alice), 0);
        _advance(DURATION / 2);
        uint256[3] memory last = staking.pendingRewards(alice);
        assertEq(last[2], first[2]);
        assertApproxEqAbs(last[2], FUNDING * 15 / 200, 1);
        assertGt(last[0], first[0]);
        _claim(alice);
        _assertConservation();
    }

    function testFallingBelowMinimumStopsBonusAndRestakingHasNoBackpay() public {
        _deposit(alice, 200 ether);
        _mintStake(alice, 41, IBMCIlluminatiPass.Tier.Standard);
        _advance(DURATION / 4);
        vm.prank(alice);
        staking.withdrawBMC(101 ether, 0);
        assertEq(_bonus(alice), 0);
        uint256[3] memory first = staking.pendingRewards(alice);
        _advance(DURATION / 4);
        _deposit(alice, 1 ether);
        assertEq(_bonus(alice), 20 ether);
        uint256[3] memory second = staking.pendingRewards(alice);
        assertEq(second[2], first[2]);
        _advance(DURATION / 2);
        uint256[3] memory last = staking.pendingRewards(alice);
        assertApproxEqAbs(last[2], FUNDING * 15 * 3 / 400, 2);
        _claim(alice);
        _assertConservation();
    }

    function testAllTokenPrincipalWithdrawnStopsBonusButNFTEarnsNormally() public {
        _deposit(alice, 100 ether);
        _mintStake(alice, 1, IBMCIlluminatiPass.Tier.LegendaryGenesis);
        _advance(DURATION / 2);
        vm.prank(alice);
        staking.withdrawBMC(100 ether, 0);
        assertEq(_bonus(alice), 0);
        _advance(DURATION / 2);
        uint256[3] memory pending = staking.pendingRewards(alice);
        assertApproxEqAbs(pending[0], FUNDING * 55 / 200, 1);
        assertApproxEqAbs(pending[1], FUNDING * 25 / 100, 1);
        assertApproxEqAbs(pending[2], FUNDING * 15 / 200, 1);
        _claim(alice);
        _assertConservation();
    }

    function testNFTTransferDoesNotCreateOverlappingBonusOrStealPriorBonus() public {
        _deposit(alice, 1000 ether);
        _deposit(bob, 1000 ether);
        _mintStake(alice, 41, IBMCIlluminatiPass.Tier.Standard);
        _advance(DURATION / 2);
        vm.prank(alice);
        staking.withdrawNFT(41, bob);
        _stakeNFT(bob, 41);
        assertEq(_bonus(alice), 0);
        assertEq(_bonus(bob), 100 ether);
        assertEq(staking.poolInfo(2).totalWeight, 100 ether);
        uint256[3] memory bobInitial = staking.pendingRewards(bob);
        assertEq(bobInitial[2], 0);
        _advance(DURATION / 2);
        uint256[3] memory a = staking.pendingRewards(alice);
        uint256[3] memory b = staking.pendingRewards(bob);
        assertApproxEqAbs(a[2], FUNDING * 15 / 200, 1);
        assertApproxEqAbs(b[2], FUNDING * 15 / 200, 1);
        _claim(alice);
        _claim(bob);
        assertLe(staking.poolInfo(2).paid, FUNDING * 15 / 100);
        _assertConservation();
    }

    function testASecondNFTDepositInSameBlockCannotClaimHistoricalBonus() public {
        _deposit(alice, 1000 ether);
        _advance(DURATION / 2);
        _mintStake(alice, 41, IBMCIlluminatiPass.Tier.Standard);
        uint256[3] memory pending = staking.pendingRewards(alice);
        assertEq(pending[2], 0);
        vm.prank(alice);
        vm.expectRevert(BMCStaking.SameBlock.selector);
        staking.claim(0);
        _advance(DURATION / 2);
        pending = staking.pendingRewards(alice);
        assertApproxEqAbs(pending[2], FUNDING * 15 / 200, 1);
    }

    function testBonusWeightIsNotAnAPYOrAPerAccountPayoutPercentage() public {
        _deposit(alice, 1000 ether);
        _mintStake(alice, 41, IBMCIlluminatiPass.Tier.Standard);
        _advance(DURATION);
        uint256[3] memory pending = staking.pendingRewards(alice);
        assertApproxEqAbs(pending[2], FUNDING * 15 / 100, 1);
        // Each pool has its own denominator: the 20% limit is a weight limit, not a reward ratio.
        assertGt(pending[2], pending[0] / 5);
        assertLe(_bonus(alice), _principal(alice) / 5);
    }

    function testPartialNFTExitReducesBonusExposureBeforeNextInterval() public {
        _deposit(alice, 1000 ether);
        _deposit(bob, 1000 ether);
        _mintStake(alice, 41, IBMCIlluminatiPass.Tier.Standard);
        _mintStake(alice, 42, IBMCIlluminatiPass.Tier.Standard);
        _mintStake(bob, 43, IBMCIlluminatiPass.Tier.Standard);
        _advance(DURATION / 2);
        vm.prank(alice);
        staking.withdrawNFT(42, alice);
        assertEq(_bonus(alice), 100 ether);
        assertEq(staking.poolInfo(2).totalWeight, 200 ether);
        _advance(DURATION / 2);
        uint256[3] memory a = staking.pendingRewards(alice);
        uint256[3] memory b = staking.pendingRewards(bob);
        uint256 budget = FUNDING * 15 / 100;
        assertApproxEqAbs(a[2], budget * 7 / 12, 2);
        assertApproxEqAbs(b[2], budget * 5 / 12, 2);
        _claim(alice);
        _claim(bob);
        _assertConservation();
    }
}
