# Public staking interface specification

The canonical ABI is produced by `forge inspect BMCStaking abi`. All user amounts are raw BMC units; the UI must obtain and verify BMC decimals. Pool IDs are token `0`, NFT `1`, bonus `2`. This is an interface specification, not a deployed website.

## User transactions

| Method | Caller/input | Effect and return |
| --- | --- | --- |
| `stakeBMC(uint256 amount, uint256 minReceived)` | Any owner of BMC with sufficient exact allowance | Credits measured net BMC to caller; returns credited amount |
| `withdrawBMC(uint256 amount, uint256 minReceived)` | Owner of recorded principal | Debits gross principal and sends BMC to caller; returns recipient net |
| `stakeNFT(uint256 tokenId)` | Current collection owner; per-NFT approval | Validates final assignment/tier, transfers custody, records weight and depositor |
| `withdrawNFT(uint256 tokenId, address recipient)` | Recorded depositor only | Checkpoints rewards, removes weight, safely returns that NFT to chosen recipient |
| `claim(uint256 minReceived)` | Owner of earned account rewards | Claims all three modes to caller; returns `(gross, received)` |

Deposits require activation, an unexpired program, no deposit pause and solvent reserves. Empty/oversized deposits are rejected. BMC withdrawals require a positive amount no greater than caller's recorded principal. NFT transfers reject zero/self recipients and receivers that do not accept safe ERC721 transfers. No method accepts an arbitrary address whose stake can be claimed or withdrawn.

Allow one new block after a BMC deposit before a BMC withdrawal, one after an NFT's deposit before its withdrawal, and one after any deposit before claiming. Adding a small BMC amount resets the token withdrawal block for that same account; a third party cannot reset it. Partial exits are supported. Paused/expired programs still allow safe exits and claims. Claims with no whole-unit reward revert.

`minReceived` is user-selected protection against transfer-fee changes. Show the gross debit and estimated net independently. A zero minimum waives that protection, including against a confiscatory recipient-side fee. Never label a gross reward as guaranteed net received. This contract does not charge its own fee.

## Reads

| Getter | UI usage |
| --- | --- |
| `BMC`, `treasury`, `collection`, `collectionReviewHash` | Verify immutable token, designated wallet, collection and published review artifact |
| `active`, `depositsPaused`, `start`, `end`, `duration` | Show not-configured/funded/active/paused/expired state and remaining program time |
| `minimumBMC`, `linkedBMCPerWeight`, `BONUS_BPS` | Explain combined eligibility and principal exposure cap |
| `accounts(owner)` | `(principal, nftWeight, bonusWeight, lastTokenDepositBlock, lastStakeBlock)` |
| `nftPositions(tokenId)` | `(staker, weight, depositBlock)`; zero staker means no registered custody |
| `pendingRewards(owner)` | Current whole-unit gross amounts `[token, NFT, bonus]`, including uncheckpointed rewards |
| `rewards(owner, poolId)` | Stored `(index, accrued, remainder)`; not a live reward quote by itself |
| `poolInfo(poolId)` / `pools(poolId)` | Budget, emission, allocated/paid/recovered values, weight and scaled index; see ACCOUNTING.md |
| `totalFunded`, `totalPrincipal`, `rewardReserve`, `uncommittedReserve`, `totalRewardsPaid`, `totalTreasuryRecovered` | Display funding and liabilities with gross accounting labels |
| `nftWeight(tokenId)` | Validate eligibility; returns 1/2/3/5 or a clear pending/configuration/invalid-tier revert |

`active` means the single program has been activated; it remains true after expiry. Compute active deposit availability with `active && timestamp < end && !depositsPaused`. Amounts in `poolInfo` other than live weights/budgets reflect the last transaction checkpoint; use `pendingRewards` for current user estimates. Direct token donations can make the onchain balance greater than recorded funding plus principal; never treat the entire balance as a reward budget.

There is no onchain account/NFT enumeration. Index `TokenDeposited`, `TokenWithdrawn`, `NFTStaked`, `NFTWithdrawn`, `RewardClaimed`, `BonusWeightChanged`, configuration, funding, activation, pause and recovery events. Reconcile events against state, handle reorgs, and display confirmed transaction receipts. `RewardClaimed` separates gross mode amounts and the combined recipient net. `TreasuryRecovered.kind` is `0` reserve, `1` idle emissions, `2` final remainder.

## UI flow

1. Check chain ID, independently published staking deployment, BMC and collection address. Show the review status and finite funded budgets; disable transactional UI until launch authorization is documented.
2. Load confirmed balance/allowance and state. For BMC, quote transfer-fee-aware receipt, request the user's exact-amount approval, then the staking transaction. For NFTs, list only current owner holdings, read final assignment and tier, approve each selected token ID and call `stakeNFT`. Pending NFTs should explain that they must reveal first.
3. Show each staking mode's weight, principal, gross pending reward, fee-dependent net estimate and program end. Explain that APR/APY is not guaranteed; bonus weight does not translate to a fixed payout ratio.
4. On withdrawal show the actual principal debit and estimated net BMC received, or the NFT and chosen safe recipient. Preserve withdraw/claim controls during deposit pause and after expiry. Show the one-block wait only when applicable.
5. Do not offer direct transfers, an unlimited approval, a new reward token, automatic trading or automatic restaking. Do not portray treasury recovery or reserve accounting as a user withdrawal mechanism.

## Proposed NFT integration ABI

`IBMCIlluminatiPass` extends ERC721. The final collection must additionally support the custom ERC165 interface ID of:

```solidity
function tierOf(uint256 tokenId) external view returns (Tier);
function isArtworkAssigned(uint256 tokenId) external view returns (bool);
// Tier ABI encoding (uint8): Pending=0, Standard=1, RandomGenesis=2,
// EarlyGenesis=3, LegendaryGenesis=4.
```

`isArtworkAssigned` must mean **final artwork and rarity assignment**, not placeholder URI availability. A revealed tier must never change. Standard/Genesis classification for mystery IDs comes exclusively from this verified tier read. Check actual function selectors and enum encodings against the eventual source. The current interface and mocks are proposed semantics only; no verified live NFT address or ABI has yet been supplied. An ERC165 claim can be forged, so code review is mandatory.

## Failures and recovery

Relevant custom errors include `NotConfigured`, `NotActive`, `ProgramEnded`, `Paused`, `SameBlock`, `PendingReveal`, `InvalidNFT`, `AlreadyStaked`, `NotStakeOwner`, `NothingToClaim`, `InvalidAmount`, `InsufficientReceived`, `UnsupportedTokenBehavior`, `Insolvent`, and `Unauthorized`. Treasury actions can additionally fail with `InvalidTreasury`, `AlreadyActive`, `ProgramNotEnded`, `PositionsRemain`, `InvalidConfiguration`, or `WrongChain`. OpenZeppelin/dependency errors may bubble up for missing allowance, insufficient balances, invalid recipients or failed NFT/ERC20 transfers. Failed transactions revert every accounting change; refresh state before retrying.
