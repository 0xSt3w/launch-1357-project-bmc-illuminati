// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StakingFixture, BMCStaking} from "./Base.t.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract PlainNFT is ERC721 {
    constructor() ERC721("No rarity integration", "NONE") {}
}

contract FundingTest is StakingFixture {
    function testDefaultsAndFixedToken() public view {
        assertEq(address(staking.BMC()), BMC_ADDRESS);
        assertEq(staking.treasury(), address(treasury));
        assertEq(staking.duration(), 365 days);
        assertEq(staking.totalFunded(), 0);
        assertEq(staking.start(), 0);
        assertEq(address(staking.collection()), address(0));
        assertEq(_pending(alice), 0);
        assertFalse(staking.active());
    }

    function testExactAllocationOfActualFunding() public {
        _activate();
        assertEq(staking.poolInfo(0).budget, FUNDING * 55 / 100);
        assertEq(staking.poolInfo(1).budget, FUNDING * 25 / 100);
        assertEq(staking.poolInfo(2).budget, FUNDING * 15 / 100);
        assertEq(staking.uncommittedReserve(), FUNDING * 5 / 100);
        assertEq(staking.end() - staking.start(), DURATION);
        _assertConservation();
    }

    function testSplitRoundingGoesToReserveAndFundingAccumulates() public {
        _configure();
        _fund(47);
        _fund(54);
        vm.prank(address(treasury));
        staking.activate();
        assertEq(staking.poolInfo(0).budget, 55);
        assertEq(staking.poolInfo(1).budget, 25);
        assertEq(staking.poolInfo(2).budget, 15);
        assertEq(staking.uncommittedReserve(), 6);
        _assertConservation();
    }

    function testCannotStakeBeforeActivation() public {
        vm.expectRevert(BMCStaking.NotActive.selector);
        staking.stakeBMC(100, 0);
        vm.expectRevert(BMCStaking.NotActive.selector);
        staking.stakeNFT(1);
    }

    function testUnconfiguredStateBlocksActivationFundingAndNFTReads() public {
        vm.expectRevert(BMCStaking.NotConfigured.selector);
        staking.nftWeight(1);
        vm.startPrank(address(treasury));
        vm.expectRevert(BMCStaking.NotConfigured.selector);
        staking.activate();
        vm.expectRevert(BMCStaking.NotConfigured.selector);
        staking.fundRewards(10, 0);
        staking.configureProgram(DURATION, MINIMUM, LINK_CAP);
        vm.expectRevert(BMCStaking.NotConfigured.selector);
        staking.activate();
        vm.stopPrank();
    }

    function testUnfundedAndNegligiblyFundedProgramsCannotStart() public {
        _configure();
        vm.prank(address(treasury));
        vm.expectRevert(BMCStaking.InvalidAmount.selector);
        staking.activate();
        _fund(1);
        vm.prank(address(treasury));
        vm.expectRevert(BMCStaking.InvalidAmount.selector);
        staking.activate();
    }

    function testOnlyTreasuryControlsFundingConfigurationAndRecovery() public {
        _activate();
        vm.startPrank(alice);
        vm.expectRevert(BMCStaking.Unauthorized.selector);
        staking.configureProgram(DURATION, 10, 10);
        vm.expectRevert(BMCStaking.Unauthorized.selector);
        staking.configureCollection(address(pass), keccak256("wrong caller"));
        vm.expectRevert(BMCStaking.Unauthorized.selector);
        staking.fundRewards(10, 0);
        vm.expectRevert(BMCStaking.Unauthorized.selector);
        staking.activate();
        vm.expectRevert(BMCStaking.Unauthorized.selector);
        staking.setDepositsPaused(true);
        vm.expectRevert(BMCStaking.Unauthorized.selector);
        staking.recoverReserve(1, 0);
        vm.expectRevert(BMCStaking.Unauthorized.selector);
        staking.recoverUnallocated(0);
        vm.expectRevert(BMCStaking.Unauthorized.selector);
        staking.recoverRemainder(0);
        vm.stopPrank();
    }

    function testNoFundingOrConfigurationChangesAfterActivation() public {
        _activate();
        vm.startPrank(address(treasury));
        vm.expectRevert(BMCStaking.AlreadyActive.selector);
        staking.configureProgram(DURATION * 2, MINIMUM, LINK_CAP);
        vm.expectRevert(BMCStaking.AlreadyActive.selector);
        staking.configureCollection(address(pass), keccak256("second"));
        vm.expectRevert(BMCStaking.AlreadyActive.selector);
        staking.fundRewards(FUNDING, 0);
        vm.expectRevert(BMCStaking.AlreadyActive.selector);
        staking.activate();
        vm.stopPrank();
    }

    function testRejectsZeroTreasuryConstructor() public {
        vm.expectRevert(BMCStaking.InvalidTreasury.selector);
        new BMCStaking(address(0));
    }

    function testRejectsInvalidTreasuries() public {
        BMCStaking eoaControlled = new BMCStaking(alice);
        vm.prank(alice);
        vm.expectRevert(BMCStaking.InvalidTreasury.selector);
        eoaControlled.configureProgram(DURATION, MINIMUM, LINK_CAP);

        treasury.setThreshold(1);
        vm.prank(address(treasury));
        vm.expectRevert(BMCStaking.InvalidTreasury.selector);
        staking.configureProgram(DURATION, MINIMUM, LINK_CAP);
        treasury.setThreshold(4);
        vm.prank(address(treasury));
        vm.expectRevert(BMCStaking.InvalidTreasury.selector);
        staking.configureProgram(DURATION, MINIMUM, LINK_CAP);
        treasury.setThreshold(2);
        address[] memory owners = treasury.getOwners();
        treasury.setOwner(1, owners[0]);
        vm.prank(address(treasury));
        vm.expectRevert(BMCStaking.InvalidTreasury.selector);
        staking.configureProgram(DURATION, MINIMUM, LINK_CAP);
        treasury.setOwner(1, address(0));
        vm.prank(address(treasury));
        vm.expectRevert(BMCStaking.InvalidTreasury.selector);
        staking.configureProgram(DURATION, MINIMUM, LINK_CAP);
    }

    function testInvalidConfigurationAndWrongCollectionABI() public {
        PlainNFT plain = new PlainNFT();
        vm.startPrank(address(treasury));
        vm.expectRevert(BMCStaking.InvalidConfiguration.selector);
        staking.configureProgram(1, MINIMUM, LINK_CAP);
        vm.expectRevert(BMCStaking.InvalidConfiguration.selector);
        staking.configureProgram(731 days, MINIMUM, LINK_CAP);
        vm.expectRevert(BMCStaking.InvalidConfiguration.selector);
        staking.configureProgram(DURATION, 0, LINK_CAP);
        vm.expectRevert(BMCStaking.InvalidConfiguration.selector);
        staking.configureProgram(DURATION, MINIMUM, 0);
        vm.expectRevert(BMCStaking.InvalidConfiguration.selector);
        staking.configureProgram(DURATION, type(uint256).max, LINK_CAP);
        vm.expectRevert(BMCStaking.InvalidConfiguration.selector);
        staking.configureCollection(alice, keccak256("no code"));
        vm.expectRevert(BMCStaking.InvalidConfiguration.selector);
        staking.configureCollection(address(pass), bytes32(0));
        vm.expectRevert(BMCStaking.InvalidConfiguration.selector);
        staking.configureCollection(address(plain), keccak256("wrong ABI"));
        staking.configureCollection(address(pass), keccak256("correct test fixture"));
        vm.expectRevert(BMCStaking.InvalidConfiguration.selector);
        staking.configureCollection(address(pass), keccak256("second attempt"));
        vm.stopPrank();
    }

    function testProgramParametersCanChangeBeforeActivation() public {
        _configure();
        vm.prank(address(treasury));
        staking.configureProgram(366 days, 7, 9);
        assertEq(staking.duration(), 366 days);
        assertEq(staking.minimumBMC(), 7);
        assertEq(staking.linkedBMCPerWeight(), 9);
    }

    function testWrongChainCannotFundOrActivate() public {
        _configure();
        vm.chainId(31337);
        vm.startPrank(address(treasury));
        vm.expectRevert(BMCStaking.WrongChain.selector);
        staking.fundRewards(100, 0);
        vm.expectRevert(BMCStaking.WrongChain.selector);
        staking.activate();
        vm.stopPrank();
    }

    function testDirectDonationsCannotIncreaseBudgetsOrWeights() public {
        _activate();
        vm.prank(alice);
        token.transfer(address(staking), 100 ether);
        assertEq(staking.totalFunded(), FUNDING);
        assertEq(staking.totalPrincipal(), 0);
        assertEq(staking.rewardReserve(), FUNDING);
        _assertConservation();
    }

    function testNoPrincipalOrArbitrarySweepAdministrativeFunction() public {
        _activate();
        _deposit(alice, 100 ether);
        vm.prank(address(treasury));
        (bool success,) = address(staking)
            .call(abi.encodeWithSignature("withdraw(address,uint256)", address(token), 100 ether));
        assertFalse(success);
        vm.prank(address(treasury));
        vm.expectRevert(BMCStaking.InvalidAmount.selector);
        staking.withdrawBMC(100 ether, 0);
        assertEq(_principal(alice), 100 ether);
    }

    function testReserveIsBoundedAndDoesNotChangeEarnedRewards() public {
        _activate();
        _deposit(alice, 100 ether);
        _advance(DURATION / 2);
        uint256 pending = _pending(alice);
        uint256 reserve = staking.uncommittedReserve();
        vm.startPrank(address(treasury));
        vm.expectRevert(BMCStaking.InvalidAmount.selector);
        staking.recoverReserve(reserve + 1, 0);
        staking.recoverReserve(reserve, reserve);
        vm.expectRevert(BMCStaking.InvalidAmount.selector);
        staking.recoverReserve(1, 0);
        vm.stopPrank();
        assertEq(_pending(alice), pending);
        assertEq(staking.totalPrincipal(), 100 ether);
        _assertConservation();
    }
}
