// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StakingFixture, BMCStaking, IBMCIlluminatiPass} from "./Base.t.sol";

contract AccountingBoundsTest is StakingFixture {
    function testMaximumSupportedFundingAndPrincipalDoNotOverflow() public {
        _configure();
        uint256 maximum = type(uint128).max;
        token.mint(address(treasury), maximum);
        token.mint(alice, maximum);
        _fund(maximum);
        vm.startPrank(address(treasury));
        token.approve(address(staking), 1);
        vm.expectRevert(BMCStaking.InvalidAmount.selector);
        staking.fundRewards(1, 0);
        staking.activate();
        vm.stopPrank();
        _deposit(alice, maximum);
        vm.startPrank(bob);
        token.approve(address(staking), 1);
        vm.expectRevert(BMCStaking.InvalidAmount.selector);
        staking.stakeBMC(1, 0);
        vm.stopPrank();
        _mintStake(alice, 1, IBMCIlluminatiPass.Tier.LegendaryGenesis);
        _advance(DURATION);
        uint256 reward = _pending(alice);
        assertLe(reward, maximum);
        _claim(alice);
        vm.prank(alice);
        staking.withdrawBMC(maximum, maximum);
        assertEq(staking.totalPrincipal(), 0);
        _assertConservation();
    }

    function testSingleRawUnitPrincipalWithMaximumRewardsDoesNotOverflowIndex() public {
        _configure();
        uint256 maximum = type(uint128).max;
        token.mint(address(treasury), maximum);
        _fund(maximum);
        vm.prank(address(treasury));
        staking.activate();
        _deposit(alice, 1);
        _advance(DURATION);
        assertEq(_claim(alice), staking.poolInfo(0).budget);
        vm.prank(alice);
        staking.withdrawBMC(1, 1);
        _assertConservation();
    }

    function testMaximumLinkedCapCannotOverflowOrDuplicatePrincipalWeight() public {
        _configure();
        vm.prank(address(treasury));
        staking.configureProgram(DURATION, 1, type(uint128).max);
        _fund(FUNDING);
        vm.prank(address(treasury));
        staking.activate();
        _deposit(alice, 999 ether);
        _mintStake(alice, 1, IBMCIlluminatiPass.Tier.LegendaryGenesis);
        assertEq(_bonus(alice), 999 ether / 5);
        _advance(DURATION);
        _claim(alice);
        _assertConservation();
    }
}
