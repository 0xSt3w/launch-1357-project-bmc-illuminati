// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {StakingFixture, BMCStaking, IBMCIlluminatiPass} from "./Base.t.sol";
import {MockPass} from "./mocks/MockPass.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ReenteringNFTOwner is IERC721Receiver {
    BMCStaking private immutable staking;
    MockPass private immutable pass;
    bool public reentered;
    bytes4 public rejection;
    bool public rejectReceipt;

    constructor(BMCStaking staking_, MockPass pass_) {
        staking = staking_;
        pass = pass_;
    }

    function stake(uint256 id) external {
        pass.approve(address(staking), id);
        staking.stakeNFT(id);
    }

    function withdraw(uint256 id) external {
        staking.withdrawNFT(id, address(this));
    }

    function setReject(bool value) external {
        rejectReceipt = value;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        require(!rejectReceipt, "receiver rejects NFT");
        bytes memory data;
        (reentered, data) = address(staking).call(abi.encodeCall(staking.claim, (0)));
        if (data.length >= 4) rejection = bytes4(data);
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract ReentrancyTest is StakingFixture {
    function testTokenCallbackCannotReenterFundingOrActivation() public {
        _configure();
        token.setCallback(address(staking), abi.encodeCall(staking.activate, ()));
        _fund(FUNDING);
        assertFalse(token.callbackSucceeded());
        assertEq(token.callbackError(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        assertFalse(staking.active());
        assertEq(staking.totalFunded(), FUNDING);
    }

    function testTokenCallbacksCannotReenterDepositWithdrawalOrClaim() public {
        _activate();
        token.setCallback(address(staking), abi.encodeCall(staking.stakeBMC, (1, 0)));
        _deposit(alice, 100 ether);
        assertFalse(token.callbackSucceeded());
        assertEq(token.callbackError(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        assertEq(staking.totalPrincipal(), 100 ether);
        _advance(1 days);
        token.setCallback(address(staking), abi.encodeCall(staking.withdrawBMC, (1, 0)));
        vm.prank(alice);
        staking.withdrawBMC(50 ether, 0);
        assertFalse(token.callbackSucceeded());
        assertEq(token.callbackError(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        token.setCallback(address(staking), abi.encodeCall(staking.claim, (0)));
        uint256 pending = _pending(alice);
        assertEq(_claim(alice), pending);
        assertFalse(token.callbackSucceeded());
        assertEq(token.callbackError(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        assertEq(staking.totalRewardsPaid(), pending);
        assertEq(staking.totalPrincipal(), 50 ether);
        _assertConservation();
    }

    function testRecoveryCannotReenterAnotherRecovery() public {
        _activate();
        token.setCallback(address(staking), abi.encodeCall(staking.recoverReserve, (1, 0)));
        vm.prank(address(treasury));
        staking.recoverReserve(100 ether, 0);
        assertFalse(token.callbackSucceeded());
        assertEq(token.callbackError(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        assertEq(staking.totalTreasuryRecovered(), 100 ether);
        _assertConservation();
    }

    function testNFTReceiverCannotReenterRewardClaimAndSafeExitStillSucceeds() public {
        _activate();
        ReenteringNFTOwner owner = new ReenteringNFTOwner(staking, pass);
        pass.mint(address(owner), 41, IBMCIlluminatiPass.Tier.Standard, true);
        owner.stake(41);
        _advance(1 days);
        uint256 accrued = _pending(address(owner));
        owner.withdraw(41);
        assertFalse(owner.reentered());
        assertEq(owner.rejection(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        assertEq(pass.ownerOf(41), address(owner));
        assertEq(_pending(address(owner)), accrued);
        assertEq(_nftWeight(address(owner)), 0);
        _assertConservation();
    }

    function testRejectingNFTReceiverRollsBackAccountingAndCanRetry() public {
        _activate();
        ReenteringNFTOwner owner = new ReenteringNFTOwner(staking, pass);
        pass.mint(address(owner), 41, IBMCIlluminatiPass.Tier.Standard, true);
        owner.stake(41);
        _advance(1 days);
        owner.setReject(true);
        vm.expectRevert("receiver rejects NFT");
        owner.withdraw(41);
        assertEq(pass.ownerOf(41), address(staking));
        assertEq(_nftWeight(address(owner)), 1);
        owner.setReject(false);
        owner.withdraw(41);
        assertEq(pass.ownerOf(41), address(owner));
        _assertConservation();
    }
}
