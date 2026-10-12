// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BMCStaking} from "../src/BMCStaking.sol";
import {IBMCIlluminatiPass} from "../src/interfaces/IBMCIlluminatiPass.sol";
import {MockBMC} from "./mocks/MockBMC.sol";
import {MockPass} from "./mocks/MockPass.sol";
import {MockTreasury} from "./mocks/MockTreasury.sol";

abstract contract StakingFixture is Test {
    address internal constant BMC_ADDRESS = 0x38224239f2BDae357D47cb864BC533d7f72dF961;
    uint256 internal constant FUNDING = 1_000_000 ether;
    uint256 internal constant MINIMUM = 100 ether;
    uint256 internal constant LINK_CAP = 500 ether;
    uint256 internal constant DURATION = 365 days;
    BMCStaking internal staking;
    MockBMC internal token;
    MockPass internal pass;
    MockTreasury internal treasury;
    address internal alice;
    address internal bob;
    address internal carol;

    function setUp() public virtual {
        vm.chainId(1);
        vm.warp(100_000);
        vm.roll(100);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        MockBMC implementation = new MockBMC();
        vm.etch(BMC_ADDRESS, address(implementation).code);
        token = MockBMC(BMC_ADDRESS);
        token.setDecimals(18);
        pass = new MockPass();
        treasury = new MockTreasury(makeAddr("signer-one"), makeAddr("signer-two"), makeAddr("signer-three"));
        staking = new BMCStaking(address(treasury));
        token.mint(address(treasury), FUNDING * 10);
        token.mint(alice, FUNDING * 10);
        token.mint(bob, FUNDING * 10);
        token.mint(carol, FUNDING * 10);
    }

    function _configure() internal {
        vm.startPrank(address(treasury));
        staking.configureProgram(DURATION, MINIMUM, LINK_CAP);
        staking.configureCollection(address(pass), keccak256("test-only interface review"));
        vm.stopPrank();
    }

    function _fund(uint256 amount) internal returns (uint256 received) {
        vm.startPrank(address(treasury));
        token.approve(address(staking), amount);
        received = staking.fundRewards(amount, 0);
        vm.stopPrank();
    }

    function _activate() internal {
        _configure();
        _fund(FUNDING);
        vm.prank(address(treasury));
        staking.activate();
    }

    function _deposit(address who, uint256 amount) internal returns (uint256 received) {
        vm.startPrank(who);
        token.approve(address(staking), amount);
        received = staking.stakeBMC(amount, 0);
        vm.stopPrank();
    }

    function _mintStake(address who, uint256 tokenId, IBMCIlluminatiPass.Tier tier) internal {
        pass.mint(who, tokenId, tier, true);
        _stakeNFT(who, tokenId);
    }

    function _stakeNFT(address who, uint256 tokenId) internal {
        vm.startPrank(who);
        pass.approve(address(staking), tokenId);
        staking.stakeNFT(tokenId);
        vm.stopPrank();
    }

    function _advance(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
        vm.roll(block.number + 1);
    }

    function _principal(address who) internal view returns (uint256 value) {
        (value,,,,) = staking.accounts(who);
    }

    function _bonus(address who) internal view returns (uint256 value) {
        (,, value,,) = staking.accounts(who);
    }

    function _nftWeight(address who) internal view returns (uint256 value) {
        (, value,,,) = staking.accounts(who);
    }

    function _pending(address who) internal view returns (uint256 value) {
        uint256[3] memory parts = staking.pendingRewards(who);
        return parts[0] + parts[1] + parts[2];
    }

    function _claim(address who) internal returns (uint256 gross) {
        vm.prank(who);
        (gross,) = staking.claim(0);
    }

    function _assertConservation() internal view {
        assertGe(token.balanceOf(address(staking)), staking.totalPrincipal() + staking.rewardReserve());
        assertEq(
            staking.totalFunded(),
            staking.rewardReserve() + staking.totalRewardsPaid() + staking.totalTreasuryRecovered()
        );
        uint256 remaining = staking.uncommittedReserve();
        uint256 paid;
        for (uint256 i; i < 3; ++i) {
            BMCStaking.Pool memory p = staking.poolInfo(i);
            assertLe(p.allocated, p.emitted);
            assertLe(p.emitted, p.budget);
            assertLe(p.paid + p.accrued, p.allocated);
            assertLe(p.paid + p.accrued + p.recovered, p.budget);
            remaining += p.budget - p.paid - p.recovered;
            paid += p.paid;
        }
        assertEq(paid, staking.totalRewardsPaid());
        assertEq(remaining, staking.rewardReserve());
    }
}
