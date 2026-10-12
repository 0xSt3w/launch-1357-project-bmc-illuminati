
 // SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BMCStaking} from "../src/BMCStaking.sol";
import {MockBMC} from "./mocks/MockBMC.sol";
import {MockTreasury} from "./mocks/MockTreasury.sol";
import {BMCIlluminatiPass} from "../integration/contracts/BMCIlluminatiPass.sol";

contract RealBMCPassIntegrationTest is Test {
    address constant BMC_ADDRESS =
        0x38224239f2BDae357D47cb864BC533d7f72dF961;

    address alice = makeAddr("alice");

    MockBMC bmc;
    BMCIlluminatiPass pass;
    BMCStaking staking;
    MockTreasury treasury;

    function setUp() public {
        vm.chainId(1);
        vm.warp(100000);
        vm.roll(100);

        MockBMC implementation = new MockBMC();
        vm.etch(BMC_ADDRESS, address(implementation).code);

        bmc = MockBMC(BMC_ADDRESS);
        bmc.setDecimals(18);

        treasury = new MockTreasury(
            makeAddr("signer1"),
            makeAddr("signer2"),
            makeAddr("signer3")
        );

        pass = new BMCIlluminatiPass(
            address(this),
            BMC_ADDRESS,
            address(0x1234)
        );

        pass.setGenesisImagesCID("bafytestcid");

        staking = new BMCStaking(address(treasury));

        vm.startPrank(address(treasury));
        staking.configureProgram(
            365 days,
            100 ether,
            500 ether
        );
        staking.configureCollection(
            address(pass),
            keccak256("integration review only")
        );
        vm.stopPrank();

        bmc.mint(address(treasury), 1000000 ether);

        vm.startPrank(address(treasury));
        bmc.approve(address(staking), 1000000 ether);
        staking.fundRewards(
            1000000 ether,
            1000000 ether
        );
        staking.activate();
        vm.stopPrank();

        bmc.mint(alice, 2100000 ether);
    }

    function testRealPassGenesisMintStakeWithdrawAndWeights()
        public
    {
        vm.startPrank(alice);

        bmc.approve(address(pass), 2000000 ether);

        uint256 id1 = pass.mintGenesis();
        uint256 id2 = pass.mintGenesis();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(pass.totalSupply(), 2);

        assertEq(pass.artworkIdOf(1), 1);
        assertEq(pass.artworkIdOf(2), 2);

        assertEq(staking.nftWeight(1), 5);
        assertEq(staking.nftWeight(2), 3);

        pass.approve(address(staking), 1);
        pass.approve(address(staking), 2);

        staking.stakeNFT(1);
        staking.stakeNFT(2);

        assertEq(pass.ownerOf(1), address(staking));
        assertEq(pass.ownerOf(2), address(staking));

        vm.expectRevert(
            BMCStaking.AlreadyStaked.selector
        );
        staking.stakeNFT(1);

        vm.stopPrank();

        (, uint256 nftWeight,,,) =
            staking.accounts(alice);

        assertEq(nftWeight, 8);

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);

        uint256[3] memory pending =
            staking.pendingRewards(alice);

        assertGt(pending[1], 0);

        vm.startPrank(alice);
        staking.withdrawNFT(1, alice);
        staking.withdrawNFT(2, alice);
        vm.stopPrank();

        assertEq(pass.ownerOf(1), alice);
        assertEq(pass.ownerOf(2), alice);

        (, nftWeight,,,) = staking.accounts(alice);

        assertEq(nftWeight, 0);
    }
}
