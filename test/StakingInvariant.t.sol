// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StakingFixture, BMCStaking, IBMCIlluminatiPass} from "./Base.t.sol";
import {MockBMC} from "./mocks/MockBMC.sol";
import {MockPass} from "./mocks/MockPass.sol";

/// @dev Stateful driver with independent principal, custody, donation and payout ledgers.
contract StakingHandler is Test {
    BMCStaking public immutable staking;
    MockBMC public immutable token;
    MockPass public immutable pass;
    address[3] public actors;
    uint256[6] public ids = [uint256(1), 2, 40, 41, 173, 500];
    uint256[3] public principal;
    uint256[3] public nftWeight;
    mapping(uint256 => address) public nftStaker;
    uint256 public rewardsPaid;
    uint256 public donations;

    constructor(BMCStaking staking_, MockBMC token_, MockPass pass_, address[3] memory actors_) {
        staking = staking_;
        token = token_;
        pass = pass_;
        actors = actors_;
    }

    function deposit(uint256 who, uint96 amount) external {
        if (block.timestamp >= staking.end() || staking.depositsPaused()) return;
        uint256 index = who % 3;
        address actor = actors[index];
        uint256 requested = bound(amount, 1, 100_000 ether);
        if (token.balanceOf(actor) < requested) return;
        uint256 beforeBalance = token.balanceOf(address(staking));
        vm.startPrank(actor);
        token.approve(address(staking), requested);
        staking.stakeBMC(requested, 0);
        vm.stopPrank();
        principal[index] += token.balanceOf(address(staking)) - beforeBalance;
    }

    function withdraw(uint256 who, uint96 amount) external {
        uint256 index = who % 3;
        address actor = actors[index];
        (,,, uint256 deposited,) = staking.accounts(actor);
        if (principal[index] == 0 || block.number <= deposited) return;
        uint256 requested = bound(amount, 1, principal[index]);
        vm.prank(actor);
        staking.withdrawBMC(requested, 0);
        principal[index] -= requested;
    }

    function stakeNFT(uint256 which) external {
        if (block.timestamp >= staking.end() || staking.depositsPaused()) return;
        uint256 id = ids[which % ids.length];
        if (nftStaker[id] != address(0)) return;
        address actor = pass.ownerOf(id);
        vm.startPrank(actor);
        pass.approve(address(staking), id);
        staking.stakeNFT(id);
        vm.stopPrank();
        nftStaker[id] = actor;
        nftWeight[_actorIndex(actor)] += _weight(id);
    }

    function withdrawNFT(uint256 which, uint256 recipient) external {
        uint256 id = ids[which % ids.length];
        address actor = nftStaker[id];
        (,, uint256 deposited) = staking.nftPositions(id);
        if (actor == address(0) || block.number <= deposited) return;
        vm.prank(actor);
        staking.withdrawNFT(id, actors[recipient % 3]);
        nftStaker[id] = address(0);
        nftWeight[_actorIndex(actor)] -= _weight(id);
    }

    function transferUnstakedNFT(uint256 which, uint256 recipient) external {
        uint256 id = ids[which % ids.length];
        if (nftStaker[id] != address(0)) return;
        address actor = pass.ownerOf(id);
        vm.prank(actor);
        pass.transferFrom(actor, actors[recipient % 3], id);
    }

    function claim(uint256 who) external {
        _claim(actors[who % 3]);
    }

    function advance(uint32 elapsed, uint8 blocks_) external {
        vm.warp(block.timestamp + bound(elapsed, 0, staking.duration() / 6));
        vm.roll(block.number + bound(blocks_, 1, 20));
    }

    function pause(bool value) external {
        vm.prank(staking.treasury());
        staking.setDepositsPaused(value);
    }

    function changeFee(uint16 fee) external {
        token.setFee(bound(fee, 0, 2000));
    }

    function donate(uint256 who, uint96 amount) external {
        address actor = actors[who % 3];
        uint256 requested = bound(amount, 1, 100 ether);
        if (token.balanceOf(actor) < requested) return;
        uint256 beforeBalance = token.balanceOf(address(staking));
        vm.prank(actor);
        token.transfer(address(staking), requested);
        donations += token.balanceOf(address(staking)) - beforeBalance;
    }

    function recoverReserve(uint96 amount) external {
        uint256 reserve = staking.uncommittedReserve();
        if (reserve == 0) return;
        vm.prank(staking.treasury());
        staking.recoverReserve(bound(amount, 1, reserve), 0);
    }

    function recoverIdle() external {
        if (block.timestamp < staking.end()) return;
        uint256 idle;
        for (uint256 i; i < 3; ++i) {
            BMCStaking.Pool memory p = staking.poolInfo(i);
            idle += p.emitted - p.allocated - p.idleRecovered;
            if (p.totalWeight == 0) idle += p.budget - p.emitted;
        }
        if (idle == 0) return;
        vm.prank(staking.treasury());
        staking.recoverUnallocated(0);
    }

    function recoverDust() external {
        _recoverDust();
    }

    /// @dev Called only by afterInvariant, never selected for random fuzz actions.
    function closeAll() external {
        if (block.timestamp < staking.end()) vm.warp(staking.end());
        vm.roll(block.number + 1);
        for (uint256 i; i < 3; ++i) {
            if (principal[i] != 0) {
                vm.prank(actors[i]);
                staking.withdrawBMC(principal[i], 0);
                principal[i] = 0;
            }
        }
        for (uint256 i; i < ids.length; ++i) {
            uint256 id = ids[i];
            address actor = nftStaker[id];
            if (actor != address(0)) {
                vm.prank(actor);
                staking.withdrawNFT(id, actor);
                nftStaker[id] = address(0);
                nftWeight[_actorIndex(actor)] -= _weight(id);
            }
        }
        for (uint256 i; i < 3; ++i) {
            _claim(actors[i]);
        }
        _recoverDust();
        uint256 reserve = staking.uncommittedReserve();
        if (reserve != 0) {
            vm.prank(staking.treasury());
            staking.recoverReserve(reserve, 0);
        }
    }

    function _recoverDust() internal {
        if (
            block.timestamp < staking.end() || staking.totalPrincipal() != 0
                || staking.poolInfo(1).totalWeight != 0
        ) return;
        uint256 available;
        for (uint256 i; i < 3; ++i) {
            BMCStaking.Pool memory p = staking.poolInfo(i);
            available += p.budget - p.paid - p.accrued - p.recovered;
        }
        if (available == 0) return;
        vm.prank(staking.treasury());
        staking.recoverRemainder(0);
    }

    function _claim(address actor) internal {
        (,,,, uint256 deposited) = staking.accounts(actor);
        uint256[3] memory pending = staking.pendingRewards(actor);
        if (pending[0] + pending[1] + pending[2] == 0 || block.number <= deposited) return;
        uint256 beforeBalance = token.balanceOf(address(staking));
        uint256 beforeRecipient = token.balanceOf(actor);
        vm.prank(actor);
        (uint256 gross, uint256 net) = staking.claim(0);
        assertEq(gross, beforeBalance - token.balanceOf(address(staking)));
        assertEq(net, token.balanceOf(actor) - beforeRecipient);
        rewardsPaid += gross;
    }

    function _actorIndex(address actor) internal view returns (uint256) {
        for (uint256 i; i < 3; ++i) {
            if (actors[i] == actor) return i;
        }
        revert("unknown fixture actor");
    }

    function _weight(uint256 id) internal pure returns (uint256) {
        if (id == 1) return 5;
        if (id == 2 || id == 40) return 3;
        if (id == 173) return 2;
        return 1;
    }
}

contract StakingInvariantTest is StakingFixture {
    StakingHandler internal handler;

    function setUp() public override {
        super.setUp();
        _activate();
        pass.mint(alice, 1, IBMCIlluminatiPass.Tier.LegendaryGenesis, true);

pass.mint(bob, 2, IBMCIlluminatiPass.Tier.Genesis, true);

pass.mint(carol, 40, IBMCIlluminatiPass.Tier.Genesis, true);
        pass.mint(alice, 41, IBMCIlluminatiPass.Tier.Standard, true);
        pass.mint(bob, 173, IBMCIlluminatiPass.Tier.RandomGenesis, true);
        pass.mint(carol, 500, IBMCIlluminatiPass.Tier.Standard, true);
        handler = new StakingHandler(staking, token, pass, [alice, bob, carol]);
        bytes4[] memory selectors = new bytes4[](13);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.withdraw.selector;
        selectors[2] = handler.stakeNFT.selector;
        selectors[3] = handler.withdrawNFT.selector;
        selectors[4] = handler.transferUnstakedNFT.selector;
        selectors[5] = handler.claim.selector;
        selectors[6] = handler.advance.selector;
        selectors[7] = handler.pause.selector;
        selectors[8] = handler.changeFee.selector;
        selectors[9] = handler.donate.selector;
        selectors[10] = handler.recoverReserve.selector;
        selectors[11] = handler.recoverIdle.selector;
        selectors[12] = handler.recoverDust.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariantPrincipalSolventAndFundingConserved() public view {
        _assertConservation();
        assertEq(
            token.balanceOf(address(staking)),
            staking.totalPrincipal() + staking.rewardReserve() + handler.donations()
        );
        assertEq(staking.totalRewardsPaid(), handler.rewardsPaid());
    }

    function invariantEveryOwnerRetainsTheirMeasuredPrincipal() public view {
        uint256 total;
        for (uint256 i; i < 3; ++i) {
            address actor = handler.actors(i);
            uint256 expected = handler.principal(i);
            assertEq(_principal(actor), expected);
            total += expected;
        }
        assertEq(staking.totalPrincipal(), total);
        assertEq(staking.poolInfo(0).totalWeight, total);
    }

    function invariantNFTCustodyAndWeightsAreUnique() public view {
        uint256 total;
        for (uint256 i; i < 3; ++i) {
            address actor = handler.actors(i);
            uint256 expected = handler.nftWeight(i);
            assertEq(_nftWeight(actor), expected);
            total += expected;
        }
        assertEq(staking.poolInfo(1).totalWeight, total);
        for (uint256 i; i < 6; ++i) {
            uint256 id = handler.ids(i);
            address expected = handler.nftStaker(id);
            (address recorded,,) = staking.nftPositions(id);
            assertEq(recorded, expected);
            if (expected != address(0)) assertEq(pass.ownerOf(id), address(staking));
            else assertNotEq(pass.ownerOf(id), address(staking));
        }
    }

    function invariantCombinedExposureNeverExceedsTwentyPercent() public view {
        uint256 total;
        for (uint256 i; i < 3; ++i) {
            address actor = handler.actors(i);
            uint256 principal = handler.principal(i);
            uint256 nftWeight = handler.nftWeight(i);
            uint256 expected;
            if (principal >= MINIMUM && nftWeight != 0) {
                uint256 linkedCap = nftWeight * LINK_CAP;
                expected = (principal < linkedCap ? principal : linkedCap) / 5;
            }
            assertEq(_bonus(actor), expected);
            assertLe(expected, principal / 5);
            total += expected;
        }
        assertEq(staking.poolInfo(2).totalWeight, total);
    }

    function invariantAllClaimableRewardsFitTheirOwnFundedBudgets() public view {
        uint256[3] memory totals;
        for (uint256 i; i < 3; ++i) {
            uint256[3] memory pending = staking.pendingRewards(handler.actors(i));
            for (uint256 j; j < 3; ++j) {
                totals[j] += pending[j];
            }
        }
        for (uint256 i; i < 3; ++i) {
            BMCStaking.Pool memory p = staking.poolInfo(i);
            assertLe(totals[i] + p.paid + p.recovered, p.budget);
        }
        assertLe(totals[0] + totals[1] + totals[2], staking.rewardReserve());
    }

    function afterInvariant() public {
        handler.closeAll();
        assertEq(staking.totalPrincipal(), 0);
        assertEq(staking.poolInfo(1).totalWeight, 0);
        assertEq(staking.poolInfo(2).totalWeight, 0);
        assertEq(staking.rewardReserve(), 0);
        assertEq(staking.totalFunded(), staking.totalRewardsPaid() + staking.totalTreasuryRecovered());
        assertEq(token.balanceOf(address(staking)), handler.donations());
        _assertConservation();
    }
}
