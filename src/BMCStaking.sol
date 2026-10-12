// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IBMCIlluminatiPass} from "./interfaces/IBMCIlluminatiPass.sol";
import {IMultisigTreasury} from "./interfaces/IMultisigTreasury.sol";

/// @title BMC Illuminati fixed-budget staking
/// @notice One immutable program; only BMC rewards. Requires independent review before deployment.
/// @dev All amounts are raw BMC units. Supported transfer fees are deducted from the transfer amount;
/// sender surcharges, rebases and reflection are unsupported. No proxy, mint, approvals or arbitrary sweep.
contract BMCStaking is ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    IERC20 public constant BMC = IERC20(0x38224239f2BDae357D47cb864BC533d7f72dF961);
    uint256 public constant SCALE = 1 << 128;
    uint256 public constant MAX_AMOUNT = type(uint128).max;
    uint256 public constant MIN_DURATION = 1 days;
    uint256 public constant MAX_DURATION = 730 days;
    uint256 public constant BONUS_BPS = 2000;
    uint256 public constant TOKEN_POOL = 0;
    uint256 public constant NFT_POOL = 1;
    uint256 public constant BONUS_POOL = 2;

    struct Pool {
        uint256 budget;
        uint256 emitted;
        uint256 allocated;
        uint256 totalWeight;
        uint256 rewardPerWeight;
        uint256 accrued;
        uint256 paid;
        uint256 recovered;
        uint256 idleRecovered;
    }

    struct Account {
        uint256 principal;
        uint256 nftWeight;
        uint256 bonusWeight;
        uint256 lastTokenDepositBlock;
        uint256 lastStakeBlock;
    }

    struct Reward {
        uint256 index;
        uint256 accrued;
        uint256 remainder;
    }

    struct NFTPosition {
        address staker;
        uint256 weight;
        uint256 depositBlock;
    }

    address public immutable treasury;
    IBMCIlluminatiPass public collection;
    bytes32 public collectionReviewHash;
    uint256 public duration = 365 days;
    uint256 public minimumBMC;
    uint256 public linkedBMCPerWeight;
    uint256 public start;
    uint256 public end;
    bool public active;
    bool public depositsPaused;
    uint256 public totalFunded;
    uint256 public totalPrincipal;
    uint256 public rewardReserve;
    uint256 public uncommittedReserve;
    uint256 public totalRewardsPaid;
    uint256 public totalTreasuryRecovered;

    Pool[3] public pools;
    mapping(address => Account) public accounts;
    mapping(address => mapping(uint256 => Reward)) public rewards;
    mapping(uint256 => NFTPosition) public nftPositions;

    // Accept ERC721 callbacks only during the exact transfer requested by stakeNFT.
    address private expectedNFTOwner;
    uint256 private expectedNFTId;

    error Unauthorized();
    error InvalidTreasury();
    error InvalidConfiguration();
    error AlreadyActive();
    error NotConfigured();
    error NotActive();
    error ProgramEnded();
    error ProgramNotEnded();
    error Paused();
    error InvalidAmount();
    error InsufficientReceived();
    error UnsupportedTokenBehavior();
    error Insolvent();
    error InvalidNFT();
    error PendingReveal();
    error AlreadyStaked();
    error NotStakeOwner();
    error SameBlock();
    error NothingToClaim();
    error PositionsRemain();
    error WrongChain();

    event ProgramConfigured(uint256 duration, uint256 minimumBMC, uint256 linkedBMCPerWeight);
    event CollectionConfigured(address indexed collection, bytes32 indexed reviewHash);
    event RewardsFunded(address indexed treasury, uint256 requested, uint256 received, uint256 totalFunded);
    event Activated(
        uint256 start,
        uint256 end,
        uint256 tokenBudget,
        uint256 nftBudget,
        uint256 bonusBudget,
        uint256 reserve
    );
    event DepositsPaused(bool paused);
    event TokenDeposited(address indexed owner, uint256 requested, uint256 credited);
    event TokenWithdrawn(address indexed owner, uint256 debited, uint256 received);
    event NFTStaked(address indexed owner, uint256 indexed tokenId, uint256 weight);
    event NFTWithdrawn(address indexed owner, address indexed recipient, uint256 indexed tokenId);
    event BonusWeightChanged(address indexed owner, uint256 weight);
    event RewardClaimed(
        address indexed owner, uint256 tokenReward, uint256 nftReward, uint256 bonusReward, uint256 received
    );
    /// @param kind 0 = uncommitted reserve, 1 = idle emissions, 2 = final rounding remainder.
    event TreasuryRecovered(uint8 indexed kind, uint256 debited, uint256 received);

    /// @param treasury_ Actual reviewed multisig address, supplied by the requester before deployment.
    /// @dev No external calls in the constructor. There is deliberately no default treasury address.
    constructor(address treasury_) {
        if (treasury_ == address(0) || treasury_ == address(this)) revert InvalidTreasury();
        treasury = treasury_;
    }

    modifier onlyTreasury() {
        if (msg.sender != treasury) revert Unauthorized();
        _requireMultisig();
        _;
    }

    modifier beforeActivation() {
        if (active) revert AlreadyActive();
        _;
    }

    /// @notice Configure raw-unit minimum and per-NFT-weight linked principal cap before activation.
    /// @dev Pass 365 days for the initial 12-month (365-day) program.
    function configureProgram(uint256 duration_, uint256 minimumBMC_, uint256 linkedBMCPerWeight_)
        external
        nonReentrant
        onlyTreasury
        beforeActivation
    {
        if (
            duration_ < MIN_DURATION || duration_ > MAX_DURATION || minimumBMC_ == 0
                || minimumBMC_ > MAX_AMOUNT || linkedBMCPerWeight_ == 0 || linkedBMCPerWeight_ > MAX_AMOUNT
        ) {
            revert InvalidConfiguration();
        }
        duration = duration_;
        minimumBMC = minimumBMC_;
        linkedBMCPerWeight = linkedBMCPerWeight_;
        emit ProgramConfigured(duration_, minimumBMC_, linkedBMCPerWeight_);
    }

    /// @notice Bind the independently reviewed collection exactly once. Never use an invented address.
    /// @dev reviewHash is the hash of the external review/integration artifact, not an onchain audit proof.
    function configureCollection(address collection_, bytes32 reviewHash)
        external
        nonReentrant
        onlyTreasury
        beforeActivation
    {
        if (address(collection) != address(0) || collection_.code.length == 0 || reviewHash == bytes32(0)) {
            revert InvalidConfiguration();
        }
        if (
            !IERC165(collection_).supportsInterface(type(IERC721).interfaceId)
                || !IERC165(collection_).supportsInterface(type(IBMCIlluminatiPass).interfaceId)
        ) {
            revert InvalidConfiguration();
        }
        collection = IBMCIlluminatiPass(collection_);
        collectionReviewHash = reviewHash;
        emit CollectionConfigured(collection_, reviewHash);
    }

    /// @notice Exact-allowance funding from the designated treasury only; measured net of incoming fees.
    /// @dev Funding is irrevocably reserved for this program. Direct token transfers are not funding.
    function fundRewards(uint256 amount, uint256 minReceived)
        external
        nonReentrant
        onlyTreasury
        beforeActivation
        returns (uint256 received)
    {
        if (block.chainid != 1) revert WrongChain();
        _requireConfigured();
        _assertSolvent();
        received = _receiveBMC(amount, minReceived);
        if (received > MAX_AMOUNT - totalFunded) revert InvalidAmount();
        totalFunded += received;
        rewardReserve += received;
        emit RewardsFunded(msg.sender, amount, received, totalFunded);
    }

    /// @notice Start once, only after review, explicit launch authorization and complete prefunding.
    function activate() external nonReentrant onlyTreasury beforeActivation {
        if (block.chainid != 1) revert WrongChain();
        _requireConfigured();
        _assertSolvent();
        uint256 tokenBudget = Math.mulDiv(totalFunded, 55, 100);
        uint256 nftBudget = Math.mulDiv(totalFunded, 25, 100);
        uint256 bonusBudget = Math.mulDiv(totalFunded, 15, 100);
        if (tokenBudget == 0 || nftBudget == 0 || bonusBudget == 0) revert InvalidAmount();
        pools[TOKEN_POOL].budget = tokenBudget;
        pools[NFT_POOL].budget = nftBudget;
        pools[BONUS_POOL].budget = bonusBudget;
        uncommittedReserve = totalFunded - tokenBudget - nftBudget - bonusBudget;
        start = block.timestamp;
        end = start + duration;
        active = true;
        emit Activated(start, end, tokenBudget, nftBudget, bonusBudget, uncommittedReserve);
    }

    /// @notice Stops only new stakes. Time, earned rewards, claims and safe withdrawals continue.
    function setDepositsPaused(bool paused) external nonReentrant onlyTreasury {
        depositsPaused = paused;
        emit DepositsPaused(paused);
    }

    function stakeBMC(uint256 amount, uint256 minReceived) external nonReentrant returns (uint256 received) {
        _requireDepositsOpen();
        _assertSolvent();
        _checkpoint(msg.sender);
        received = _receiveBMC(amount, minReceived);
        if (received > MAX_AMOUNT - totalPrincipal) revert InvalidAmount();
        Account storage a = accounts[msg.sender];
        a.principal += received;
        totalPrincipal += received;
        pools[TOKEN_POOL].totalWeight += received;
        a.lastTokenDepositBlock = block.number;
        a.lastStakeBlock = block.number;
        _refreshBonus(msg.sender);
        emit TokenDeposited(msg.sender, amount, received);
    }

    /// @notice Withdraw a gross principal amount to its owner; recipient transfer fees are borne by owner.
    /// @dev Never depends on treasury, pause, NFT metadata or reward-reserve solvency.
    function withdrawBMC(uint256 amount, uint256 minReceived)
        external
        nonReentrant
        returns (uint256 received)
    {
        Account storage a = accounts[msg.sender];
        if (amount == 0 || amount > a.principal) revert InvalidAmount();
        if (block.number <= a.lastTokenDepositBlock) revert SameBlock();
        _checkpoint(msg.sender);
        a.principal -= amount;
        totalPrincipal -= amount;
        pools[TOKEN_POOL].totalWeight -= amount;
        _refreshBonus(msg.sender);
        received = _sendBMC(msg.sender, amount, minReceived);
        emit TokenWithdrawn(msg.sender, amount, received);
    }

    function stakeNFT(uint256 tokenId) external nonReentrant {
        _requireDepositsOpen();
        _assertSolvent();
        if (nftPositions[tokenId].staker != address(0)) revert AlreadyStaked();
        if (collection.ownerOf(tokenId) != msg.sender) revert NotStakeOwner();
        uint256 weight = nftWeight(tokenId);
        _checkpoint(msg.sender);
        nftPositions[tokenId] = NFTPosition(msg.sender, weight, block.number);
        accounts[msg.sender].nftWeight += weight;
        accounts[msg.sender].lastStakeBlock = block.number;
        pools[NFT_POOL].totalWeight += weight;
        _refreshBonus(msg.sender);
        expectedNFTOwner = msg.sender;
        expectedNFTId = tokenId;
        collection.safeTransferFrom(msg.sender, address(this), tokenId);
        expectedNFTOwner = address(0);
        expectedNFTId = 0;
        if (collection.ownerOf(tokenId) != address(this)) revert InvalidNFT();
        emit NFTStaked(msg.sender, tokenId, weight);
    }

    /// @notice Only the original depositor can choose where their NFT is returned.
    function withdrawNFT(uint256 tokenId, address recipient) external nonReentrant {
        NFTPosition memory position = nftPositions[tokenId];
        if (position.staker != msg.sender) revert NotStakeOwner();
        if (recipient == address(0) || recipient == address(this)) revert InvalidConfiguration();
        if (block.number <= position.depositBlock) revert SameBlock();
        _checkpoint(msg.sender);
        delete nftPositions[tokenId];
        accounts[msg.sender].nftWeight -= position.weight;
        pools[NFT_POOL].totalWeight -= position.weight;
        _refreshBonus(msg.sender);
        collection.safeTransferFrom(address(this), recipient, tokenId);
        emit NFTWithdrawn(msg.sender, recipient, tokenId);
    }

    /// @notice Claim all three modes to the stake owner. Past earned rewards survive every withdrawal.
    function claim(uint256 minReceived) external nonReentrant returns (uint256 gross, uint256 received) {
        if (block.number <= accounts[msg.sender].lastStakeBlock) revert SameBlock();
        _checkpoint(msg.sender);
        uint256[3] memory amounts;
        for (uint256 i; i < 3; ++i) {
            Reward storage r = rewards[msg.sender][i];
            Pool storage p = pools[i];
            amounts[i] = r.accrued;
            gross += r.accrued;
            p.accrued -= r.accrued;
            p.paid += r.accrued;
            // Local hard caps are independent of the actual token balance or any principal deposits.
            if (p.paid > p.allocated || p.paid + p.recovered > p.budget) revert Insolvent();
            r.accrued = 0;
        }
        if (gross == 0) revert NothingToClaim();
        _assertSolvent();
        rewardReserve -= gross;
        totalRewardsPaid += gross;
        received = _sendBMC(msg.sender, gross, minReceived);
        _assertSolvent();
        emit RewardClaimed(msg.sender, amounts[0], amounts[1], amounts[2], received);
    }

    /// @notice Return only the explicitly uncommitted 5% plus allocation-rounding residue.
    function recoverReserve(uint256 amount, uint256 minReceived) external nonReentrant onlyTreasury {
        if (!active) revert NotActive();
        if (amount == 0 || amount > uncommittedReserve) revert InvalidAmount();
        uncommittedReserve -= amount;
        _recover(0, amount, minReceived);
    }

    /// @notice After expiry, return emissions for periods with no eligible weight; never earned rewards.
    function recoverUnallocated(uint256 minReceived) external nonReentrant onlyTreasury {
        _requireEnded();
        _updatePools();
        uint256 amount = 0;
        for (uint256 i; i < 3; ++i) {
            Pool storage p = pools[i];
            uint256 idle = p.emitted - p.allocated;
            uint256 available = idle - p.idleRecovered;
            p.idleRecovered = idle;
            p.recovered += available;
            amount += available;
        }
        if (amount == 0) revert InvalidAmount();
        _recover(1, amount, minReceived);
    }

    /// @notice Reclaim final dust only after expiry and ALL principal/NFT positions have exited.
    /// @dev Every position is checkpointed on exit. All accrued whole units remain claimable forever.
    function recoverRemainder(uint256 minReceived) external nonReentrant onlyTreasury {
        _requireEnded();
        if (totalPrincipal != 0 || pools[NFT_POOL].totalWeight != 0) revert PositionsRemain();
        _updatePools();
        uint256 amount = 0;
        for (uint256 i; i < 3; ++i) {
            Pool storage p = pools[i];
            uint256 available = p.budget - p.paid - p.accrued - p.recovered;
            p.recovered += available;
            p.idleRecovered = p.emitted - p.allocated;
            amount += available;
        }
        if (amount == 0) revert InvalidAmount();
        _recover(2, amount, minReceived);
    }

    function pendingRewards(address owner) external view returns (uint256[3] memory pending) {
        Account memory a = accounts[owner];
        uint256[3] memory weights = [a.principal, a.nftWeight, a.bonusWeight];
        for (uint256 i; i < 3; ++i) {
            Pool storage p = pools[i];
            Reward storage r = rewards[owner][i];
            uint256 index = p.rewardPerWeight;
            if (p.totalWeight != 0) {
                index += Math.mulDiv(_vested(p.budget) - p.emitted, SCALE, p.totalWeight);
            }
            (uint256 whole,) = _earned(weights[i], index - r.index, r.remainder);
            pending[i] = r.accrued + whole;
        }
    }

    function poolInfo(uint256 poolId) external view returns (Pool memory) {
        return pools[poolId];
    }

    /// @notice Tier comes from the collection, not the mystery token ID. Pending NFTs earn nothing.
    function nftWeight(uint256 tokenId) public view returns (uint256) {
        if (address(collection) == address(0)) revert NotConfigured();
        if (tokenId == 0 || tokenId > 500) revert InvalidNFT();
        if (!collection.isArtworkAssigned(tokenId)) revert PendingReveal();
        IBMCIlluminatiPass.Tier tier = collection.tierOf(tokenId);
        if (tier == IBMCIlluminatiPass.Tier.Pending) revert PendingReveal();
        if (tokenId == 1) {
            if (tier != IBMCIlluminatiPass.Tier.LegendaryGenesis) revert InvalidNFT();
            return 5;
        }
        if (tokenId <= 40) {
            if (tier != IBMCIlluminatiPass.Tier.EarlyGenesis) revert InvalidNFT();
            return 3;
        }
        if (tier == IBMCIlluminatiPass.Tier.RandomGenesis) return 2;
        if (tier == IBMCIlluminatiPass.Tier.Standard) return 1;
        revert InvalidNFT();
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata)
        external
        view
        returns (bytes4)
    {
        if (
            msg.sender != address(collection) || operator != address(this) || from != expectedNFTOwner
                || from == address(0) || tokenId != expectedNFTId
        ) revert InvalidNFT();
        return IERC721Receiver.onERC721Received.selector;
    }

    function _checkpoint(address owner) internal {
        _updatePools();
        Account storage a = accounts[owner];
        uint256[3] memory weights = [a.principal, a.nftWeight, a.bonusWeight];
        for (uint256 i; i < 3; ++i) {
            Pool storage p = pools[i];
            Reward storage r = rewards[owner][i];
            (uint256 whole, uint256 remainder) = _earned(weights[i], p.rewardPerWeight - r.index, r.remainder);
            r.accrued += whole;
            p.accrued += whole;
            r.remainder = remainder;
            r.index = p.rewardPerWeight;
        }
    }

    function _updatePools() internal {
        for (uint256 i; i < 3; ++i) {
            Pool storage p = pools[i];
            uint256 vested = _vested(p.budget);
            uint256 emission = vested - p.emitted;
            p.emitted = vested;
            if (p.totalWeight != 0) {
                p.allocated += emission;
                p.rewardPerWeight += Math.mulDiv(emission, SCALE, p.totalWeight);
            }
        }
    }

    function _vested(uint256 budget) internal view returns (uint256) {
        if (!active) return 0;
        return Math.mulDiv(budget, Math.min(block.timestamp, end) - start, duration);
    }

    function _earned(uint256 weight, uint256 indexDelta, uint256 previousRemainder)
        internal
        pure
        returns (uint256 whole, uint256 remainder)
    {
        whole = Math.mulDiv(weight, indexDelta, SCALE);
        remainder = mulmod(weight, indexDelta, SCALE) + previousRemainder;
        whole += remainder / SCALE;
        remainder %= SCALE;
    }

    function _refreshBonus(address owner) internal {
        Account storage a = accounts[owner];
        uint256 next = 0;
        if (a.principal >= minimumBMC && a.nftWeight != 0) {
            uint256 linked = Math.min(a.principal, a.nftWeight * linkedBMCPerWeight);
            next = Math.mulDiv(linked, BONUS_BPS, 10_000);
        }
        if (next != a.bonusWeight) {
            pools[BONUS_POOL].totalWeight = pools[BONUS_POOL].totalWeight - a.bonusWeight + next;
            a.bonusWeight = next;
            emit BonusWeightChanged(owner, next);
        }
    }

    function _receiveBMC(uint256 amount, uint256 minReceived) internal returns (uint256 received) {
        if (amount == 0 || amount > MAX_AMOUNT) revert InvalidAmount();
        uint256 beforeBalance = BMC.balanceOf(address(this));
        BMC.safeTransferFrom(msg.sender, address(this), amount);
        uint256 afterBalance = BMC.balanceOf(address(this));
        if (afterBalance <= beforeBalance || afterBalance - beforeBalance > amount) {
            revert UnsupportedTokenBehavior();
        }
        received = afterBalance - beforeBalance;
        if (received < minReceived) revert InsufficientReceived();
    }

    function _sendBMC(address recipient, uint256 amount, uint256 minReceived)
        internal
        returns (uint256 received)
    {
        uint256 beforeBalance = BMC.balanceOf(address(this));
        uint256 beforeRecipient = BMC.balanceOf(recipient);
        BMC.safeTransfer(recipient, amount);
        uint256 afterBalance = BMC.balanceOf(address(this));
        uint256 afterRecipient = BMC.balanceOf(recipient);
        if (
            afterBalance > beforeBalance || beforeBalance - afterBalance != amount
                || afterRecipient < beforeRecipient || afterRecipient - beforeRecipient > amount
        ) revert UnsupportedTokenBehavior();
        if (afterBalance < totalPrincipal) revert Insolvent();
        received = afterRecipient - beforeRecipient;
        if (received < minReceived) revert InsufficientReceived();
    }

    function _recover(uint8 kind, uint256 amount, uint256 minReceived) internal {
        _assertSolvent();
        rewardReserve -= amount;
        totalTreasuryRecovered += amount;
        uint256 received = _sendBMC(treasury, amount, minReceived);
        _assertSolvent();
        emit TreasuryRecovered(kind, amount, received);
    }

    function _assertSolvent() internal view {
        if (BMC.balanceOf(address(this)) < totalPrincipal + rewardReserve) revert Insolvent();
    }

    function _requireConfigured() internal view {
        if (address(collection) == address(0) || minimumBMC == 0) revert NotConfigured();
    }

    function _requireDepositsOpen() internal view {
        if (!active) revert NotActive();
        if (block.timestamp >= end) revert ProgramEnded();
        if (depositsPaused) revert Paused();
    }

    function _requireEnded() internal view {
        if (!active || block.timestamp < end) revert ProgramNotEnded();
    }

    function _requireMultisig() internal view {
        if (treasury.code.length == 0) revert InvalidTreasury();
        uint256 threshold = IMultisigTreasury(treasury).getThreshold();
        address[] memory owners = IMultisigTreasury(treasury).getOwners();
        if (threshold < 2 || threshold > owners.length || owners.length > 50) revert InvalidTreasury();
        for (uint256 i; i < owners.length; ++i) {
            if (owners[i] == address(0)) revert InvalidTreasury();
            for (uint256 j; j < i; ++j) {
                if (owners[i] == owners[j]) revert InvalidTreasury();
            }
        }
    }
}
