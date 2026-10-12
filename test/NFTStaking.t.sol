// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StakingFixture, BMCStaking, IBMCIlluminatiPass} from "./Base.t.sol";
import {MockPass} from "./mocks/MockPass.sol";

contract NFTStakingTest is StakingFixture {
    function setUp() public override {
        super.setUp();
        _activate();
    }

    function testFourVerifiedTiersReceiveOneTwoThreeFiveWeights() public {
        _mintStake(alice, 500, IBMCIlluminatiPass.Tier.Standard);
        _mintStake(bob, 173, IBMCIlluminatiPass.Tier.Genesis);
        _mintStake(carol, 40, IBMCIlluminatiPass.Tier.Genesis);
        _mintStake(alice, 1, IBMCIlluminatiPass.Tier.LegendaryGenesis);
        assertEq(_nftWeight(alice), 6);
        assertEq(_nftWeight(bob), 2);
        assertEq(_nftWeight(carol), 3);
        assertEq(staking.poolInfo(1).totalWeight, 11);
        _advance(DURATION);
        uint256 budget = FUNDING / 4;
        assertApproxEqAbs(_claim(alice), budget * 6 / 11, 1);
        assertApproxEqAbs(_claim(bob), budget * 2 / 11, 1);
        assertApproxEqAbs(_claim(carol), budget * 3 / 11, 1);
        _assertConservation();
    }

    function testPendingNFTCannotStakeThenFinalGenesisCanStakeWithoutBackpay() public {
        pass.mint(alice, 499, IBMCIlluminatiPass.Tier.Pending, false);
        vm.startPrank(alice);
        pass.approve(address(staking), 499);
        vm.expectRevert(BMCStaking.PendingReveal.selector);
        staking.stakeNFT(499);
        vm.stopPrank();
        assertEq(pass.ownerOf(499), alice);
        assertEq(_nftWeight(alice), 0);
        _advance(DURATION / 2);
        pass.reveal(499, IBMCIlluminatiPass.Tier.Genesis);
        vm.prank(alice);
        staking.stakeNFT(499);
        assertEq(_nftWeight(alice), 2);
        assertEq(_pending(alice), 0);
        _advance(DURATION / 2);
        assertEq(_claim(alice), FUNDING / 8);
        _assertConservation();
    }

    function testTierAndArtworkAssignmentBothRequired() public {
        pass.mint(alice, 70, IBMCIlluminatiPass.Tier.Genesis, false);
        pass.mint(alice, 71, IBMCIlluminatiPass.Tier.Pending, true);
        vm.startPrank(alice);
        pass.approve(address(staking), 70);
        vm.expectRevert(BMCStaking.PendingReveal.selector);
        staking.stakeNFT(70);
        pass.approve(address(staking), 71);
        vm.expectRevert(BMCStaking.PendingReveal.selector);
        staking.stakeNFT(71);
        vm.stopPrank();
    }

    function testMysteryRarityIsNotInferredFromID() public {
        pass.mint(alice, 41, IBMCIlluminatiPass.Tier.Standard, true);
        pass.mint(alice, 500, IBMCIlluminatiPass.Tier.Genesis, true);
        assertEq(staking.nftWeight(41), 1);
        assertEq(staking.nftWeight(500), 2);
    }

    
function testInconsistentKnownTiersAndOutOfRangeIDsRejected()
    public
{
    // Legendary token incorrectly classified as Standard.
    pass.mint(alice, 1, IBMCIlluminatiPass.Tier.Standard, true);

    // Early Genesis incorrectly classified as Standard.
    pass.mint(alice, 2, IBMCIlluminatiPass.Tier.Standard, true);

    // Mystery token incorrectly classified as Legendary.
    pass.mint(
        alice,
        41,
        IBMCIlluminatiPass.Tier.LegendaryGenesis,
        true
    );

    // Mystery token with invalid early-Genesis artwork.
    pass.mint(alice, 42, IBMCIlluminatiPass.Tier.Genesis, true);

    uint256[3] memory invalidIds = [
        uint256(1),
        uint256(2),
        uint256(41)
    ];

    for (uint256 i = 0; i < invalidIds.length; i++) {
        vm.expectRevert(BMCStaking.InvalidNFT.selector);
        staking.nftWeight(invalidIds[i]);
    }

    vm.expectRevert(BMCStaking.InvalidNFT.selector);
    staking.nftWeight(0);

    vm.expectRevert(BMCStaking.InvalidNFT.selector);
    staking.nftWeight(501);
}


    function testOnlyCurrentNFTOwnerCanStakeEvenIfCallerIsApprovedOperator() public {
        pass.mint(alice, 41, IBMCIlluminatiPass.Tier.Standard, true);
        vm.prank(alice);
        pass.setApprovalForAll(bob, true);
        vm.prank(bob);
        vm.expectRevert(BMCStaking.NotStakeOwner.selector);
        staking.stakeNFT(41);
        vm.prank(bob);
        pass.transferFrom(alice, carol, 41);
        vm.prank(alice);
        vm.expectRevert(BMCStaking.NotStakeOwner.selector);
        staking.stakeNFT(41);
        _stakeNFT(carol, 41);
        _advance(1 days);
        assertGt(_pending(carol), 0);
        assertEq(_pending(alice), 0);
        assertEq(_pending(bob), 0);
    }

    function testCustodyPreventsOwnershipChangesAndDoubleStaking() public {
        _mintStake(alice, 41, IBMCIlluminatiPass.Tier.Standard);
        assertEq(pass.ownerOf(41), address(staking));
        vm.prank(alice);
        vm.expectRevert(BMCStaking.AlreadyStaked.selector);
        staking.stakeNFT(41);
        vm.prank(bob);
        vm.expectRevert(BMCStaking.AlreadyStaked.selector);
        staking.stakeNFT(41);
        vm.prank(alice);
        vm.expectRevert();
        pass.transferFrom(address(staking), bob, 41);
        _advance(1 days);
        vm.prank(bob);
        vm.expectRevert(BMCStaking.NotStakeOwner.selector);
        staking.withdrawNFT(41, bob);
        vm.prank(bob);
        vm.expectRevert(BMCStaking.NothingToClaim.selector);
        staking.claim(0);
    }

    function testExitChangesOwnerButOldEarnedRewardsRemainWithDepositor() public {
        _mintStake(alice, 41, IBMCIlluminatiPass.Tier.Standard);
        _advance(DURATION / 2);
        uint256 aliceEarned = _pending(alice);
        vm.prank(alice);
        staking.withdrawNFT(41, bob);
        assertEq(pass.ownerOf(41), bob);
        assertEq(_nftWeight(alice), 0);
        _stakeNFT(bob, 41);
        assertEq(_pending(bob), 0);
        _advance(DURATION / 2);
        assertEq(_claim(alice), aliceEarned);
        assertEq(_claim(bob), FUNDING / 8);
        _assertConservation();
    }

    function testSameBlockNFTWithdrawalFailsAndRewardIsZero() public {
        _mintStake(alice, 41, IBMCIlluminatiPass.Tier.Standard);
        vm.prank(alice);
        vm.expectRevert(BMCStaking.SameBlock.selector);
        staking.withdrawNFT(41, alice);
        assertEq(_pending(alice), 0);
        vm.roll(block.number + 1);
        vm.prank(alice);
        staking.withdrawNFT(41, alice);
        assertEq(_pending(alice), 0);
    }

    function testWithdrawalsWorkWhenPausedAndMetadataBreaks() public {
        _mintStake(alice, 41, IBMCIlluminatiPass.Tier.Standard);
        _advance(1 days);
        vm.prank(address(treasury));
        staking.setDepositsPaused(true);
        pass.setBrokenMetadata(true);
        vm.prank(alice);
        staking.withdrawNFT(41, alice);
        assertEq(pass.ownerOf(41), alice);
        assertEq(_nftWeight(alice), 0);
        assertGt(_claim(alice), 0);
        _assertConservation();
    }

    function testInvalidRecipientsDoNotDestroyNFTPosition() public {
        _mintStake(alice, 41, IBMCIlluminatiPass.Tier.Standard);
        _advance(1 days);
        vm.startPrank(alice);
        vm.expectRevert(BMCStaking.InvalidConfiguration.selector);
        staking.withdrawNFT(41, address(0));
        vm.expectRevert(BMCStaking.InvalidConfiguration.selector);
        staking.withdrawNFT(41, address(staking));
        vm.expectRevert();
        staking.withdrawNFT(41, address(token));
        vm.stopPrank();
        (address owner, uint256 weight,) = staking.nftPositions(41);
        assertEq(owner, alice);
        assertEq(weight, 1);
        assertEq(pass.ownerOf(41), address(staking));
    }

    function testUnsolicitedSafeTransfersAndForgedCallbacksRejected() public {
        pass.mint(alice, 41, IBMCIlluminatiPass.Tier.Standard, true);
        vm.prank(alice);
        vm.expectRevert(BMCStaking.InvalidNFT.selector);
        pass.safeTransferFrom(alice, address(staking), 41);
        assertEq(pass.ownerOf(41), alice);
        vm.expectRevert(BMCStaking.InvalidNFT.selector);
        staking.onERC721Received(address(staking), alice, 41, "");
        MockPass other = new MockPass();
        other.mint(alice, 41, IBMCIlluminatiPass.Tier.Standard, true);
        vm.prank(alice);
        vm.expectRevert(BMCStaking.InvalidNFT.selector);
        other.safeTransferFrom(alice, address(staking), 41);
    }

    function testNFTWithdrawAndClaimAfterProgramEnd() public {
        _mintStake(alice, 1, IBMCIlluminatiPass.Tier.LegendaryGenesis);
        _advance(DURATION * 2);
        vm.prank(alice);
        staking.withdrawNFT(1, alice);
        assertApproxEqAbs(_claim(alice), FUNDING / 4, 1);
        vm.prank(alice);
        vm.expectRevert(BMCStaking.ProgramEnded.selector);
        staking.stakeNFT(1);
        _assertConservation();
    }
}
