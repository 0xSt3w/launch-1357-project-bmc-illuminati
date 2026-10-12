# BMC Illuminati staking

Source-only implementation of a fixed-duration, fully prefunded staking program on Ethereum mainnet (chain ID 1). **Not deployed or independently audited. Do not enable staking or fund a deployment until independent review and explicit requester authorization are complete.**

The sole production contract is [BMCStaking](src/BMCStaking.sol). BMC at `0x38224239f2BDae357D47cb864BC533d7f72dF961` is the only principal/reward ERC-20. There is no token issuance, proxy, oracle, trading, bridge, IMD reward, buyback or burning integration. Test mocks are fixtures, never launch contracts.

## Build and verify

Run from this repository's root:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity **0.8.26**, Cancun, optimizer 200 runs. All imported Solidity dependencies are ordinary files under `lib/`; no installation, submodules, network, environment variables, FFI or filesystem cheatcode permissions are needed by the build/tests. A Foundry installation and the pinned compiler must already be available. Dependency provenance is in [DEPENDENCIES.md](DEPENDENCIES.md); observed results and IMD responses are in [docs/VERIFICATION.md](docs/VERIFICATION.md).

## Reward program

Funding is pulled only from the designated multisig through `fundRewards`, measured by the contract's BMC balance increase. Multiple funding deposits are allowed **before activation only**. The treasury then calls `activate` once; all three budgets and the finish timestamp are fixed permanently. Neither funding transfers nor user principal can increase a budget after activation.

| Use | Allocation from net funding | User weight |
| --- | ---: | --- |
| Token staking | 55% | Actual BMC principal credited |
| NFT staking | 25% | Sum of eligible deposited NFT weights |
| Combined bonus | 15% | Formula below |
| Uncommitted reserve | 5%, plus allocation rounding | No reward accrual |

Each of the three budgets is rounded down independently; the remaining raw units go to the reserve. Default duration is **365 days**, the explicit interpretation of the requested initial 12 months. The multisig can configure a duration between 1 and 730 days before activation; use 365 days for the initial program unless the requester explicitly revises it. Start is the activation transaction's timestamp; end is exclusive for new stakes. Rewards end at `start + duration` and can be claimed indefinitely afterward. There is no guaranteed APY, fixed account payout, auto-compounding or new BMC minting.

For pool budget `B`, cumulative released rewards at time `t` are:

```text
vested(t) = floor(B * min(max(t - start, 0), duration) / duration)
new emission = vested(now) - previously emitted
index increase = floor(new emission * 2^128 / total eligible weight)
```

If total weight is zero, that interval's emission is unallocated; it is never paid to later depositors. Each account checkpoints its old weights before any change. Account fractional rewards are carried across checkpoints using `mulmod`, avoiding systematic loss from frequent claims. Global division residue stays in the pool until final settlement. The math and conservation argument are in [docs/ACCOUNTING.md](docs/ACCOUNTING.md).

## Staking and withdrawals

Anyone may stake their own BMC with an **exact-amount** token allowance. Deposits credit only actual incoming BMC. Only that account can withdraw its principal or claim its rewards; claims and BMC withdrawals pay that account. There are no contract deposit/withdrawal penalties, minimum holding period in seconds, or administrator principal withdrawals. A token withdrawal must occur in a block strictly after that account's latest BMC deposit. Claiming must occur after its latest BMC or NFT deposit. This one-block condition and checkpointing prevent flash-loan and same-block round-trip reward capture.

NFTs are held in custody during staking. Only their current owner can deposit them, even if an operator is approved. Use a per-token approval and `stakeNFT`; do not send NFTs directly. The recorded depositor alone can withdraw an NFT, to an address of their choice, after its deposit block. Safe transfers to contracts require `IERC721Receiver`. Rejected receivers roll back the entire withdrawal. Existing rewards belong to the depositor who earned them even if the NFT is later transferred to a different owner.

| NFT classification | Weight | Validation |
| --- | ---: | --- |
| Legendary Genesis | 5 | ID 1 **and** collection-reported Legendary tier |
| Early Genesis | 3 | IDs 2–40 **and** collection-reported Early tier |
| Random Genesis | 2 | IDs 41–500 with collection-reported Random Genesis tier |
| Standard | 1 | IDs 41–500 with collection-reported Standard tier |

The collection's verified tier and final artwork-assignment flag are both required. Pending NFTs are rejected, keep their owner's custody, and receive no retroactive rewards after reveal. Mystery rarity is never inferred from ID. The collection must enforce 37 additional random Genesis and 423 Standard NFTs itself; staking does not assign rarity or randomness. The 500-token range, known ID classes and reported tiers are checked. A staked NFT's final weight is snapshotted; final tiers/artwork must be immutable. Withdrawals use that snapshot and never call rarity/artwork getters, so a metadata outage cannot trap NFTs. Collection transfer restrictions can still affect custody; these must be reviewed.

## Combined bonus rules

The multisig must publicly configure two **raw BMC unit** parameters before activation: `minimumBMC` and `linkedBMCPerWeight`. There are no guessed launch values or decimal assumptions.

```text
eligible = principal >= minimumBMC AND NFT weight > 0
linked principal = min(principal, NFT weight * linkedBMCPerWeight)
bonus weight = eligible ? floor(linked principal * 20 / 100) : 0
```

Thus one standard NFT links at most `linkedBMCPerWeight` principal units; a legendary links five times that cap. The same principal and NFT appear in only one account position and one bonus weight. More NFTs cannot push bonus weight above 20% of that account's principal. No separate bonus registration exists. Both staking orders work. Withdrawals reduce the weight immediately; losing all NFTs, all principal, or the minimum threshold stops bonus accrual. Remaining eligible stake continues earning at the newly calculated weight.

**The 20% limit is a weight limit, not a cap on the ratio of bonus payout to token-pool payout.** Pools have independent denominators. For example, a sole eligible participant throughout the program can receive nearly all of both the 55% token allocation and 15% bonus allocation; `15 / 55` is about 27.27%. Actual distributions always stay within each separately funded budget. This economic interpretation must be accepted in independent review before launch; if a maximum 20% *payout* top-up is intended instead, the design must be revised and reviewed.

## Fees and solvency

The contract charges **no fee**. BMC may charge its own transfer fee:

- Funding and staking use the net incoming balance increase. A 100-unit transfer with a 10-unit fee credits 90 units.
- Withdrawals and claims debit their **gross recorded amount**; the owner receives the amount left after BMC's outgoing fee. A withdrawal of 90 units with a 9-unit fee reduces principal by 90 and delivers 81.
- `minReceived` lets the caller reject unexpected fees atomically. Claim/recovery caps count the full amount debited, including the token's fee, not just the recipient's net gain.
- Supported tokens must debit exactly the requested outgoing amount. Sender surcharges, reflection and rebasing are unsupported. Balance checks reject detectable incompatible transfers and insufficient reserves. A malicious token cannot be made safe by balance checks alone.

`totalPrincipal` and `rewardReserve` are separate ledgers. Normal operation preserves `BMC balance >= totalPrincipal + rewardReserve`. Reward claims and treasury recoveries cannot consume principal. If external token behavior creates a reward-only deficit, reward payouts and new deposits stop; principal withdrawals remain possible while the full remaining principal is backed. If BMC freezes transfers or destroys principal balances, this contract cannot override BMC. Token ownership, upgrade, pause, blocklist and fee powers require independent review.

## Treasury powers and settlement

The constructor takes a real, independently verified multisig treasury address. It is immutable and is never inferred from the deployer or factory. Every treasury action checks Safe-compatible `getThreshold()`/`getOwners()` with at least two signatures, distinct nonzero owners and at most 50 owners. These shape checks **do not prove a wallet is a genuine multisig**; reviewers must verify its implementation, signers, modules and threshold policy.

The treasury can configure the program before activation, bind the verified NFT collection once, fund before activation, activate once, pause/unpause **new deposits only**, and perform these bounded recoveries to itself:

| Recovery | Earliest time | Bound |
| --- | --- | --- |
| `recoverReserve` | After activation | Remaining uncommitted reserve only |
| `recoverUnallocated` | At/after end | Emissions from zero-weight intervals only |
| `recoverRemainder` | At/after end and all BMC/NFT positions exited | Unallocated rewards and rounding dust, excluding all accrued whole-unit claims |

Claims never expire. There is no arbitrary rescue/sweep, administrator withdrawal of a user's tokens/NFTs, treasury rotation, proxy upgrade or early program termination. Funding is irrevocably committed until the applicable recovery rule allows its return. A pause does not stop the clock or reduce earned rewards. Forgotten positions can delay final dust recovery indefinitely. Direct BMC donations are not principal or funding and remain outside these recovery powers. Unsolicited safe NFT transfers are rejected; unsafe `transferFrom` donations cannot be prevented and cannot be rescued. The interface must clearly warn against either kind of direct transfer.

## Deployment blockers and delivery

This work intentionally supplies **source, offline tests and documentation only**. No deployment, activation, wallet approval, token transfer, paid IMD request or repository publication was performed. Repository/PR publication belongs to the contributor-network delivery process; no fabricated remote URL is supplied.

Before any future deployment, resolve:

1. **NFT address and ABI:** requester must supply the independently reviewed deployed collection. [IBMCIlluminatiPass](src/interfaces/IBMCIlluminatiPass.sol) is an explicit proposed integration contract, not a verified description of a live NFT. Confirm exact tier encoding, `isArtworkAssigned`, ERC165 support, tier finality, supply/rarity counts, transfers and ownership; adapt the source and repeat review if they differ. Do not deploy NFT/combined staking with a guessed collection or postpone this prerequisite until after launch.
2. **Treasury and economics:** obtain the actual multisig address, reviewed wallet configuration, approved net budget, raw-unit minimum and linked-principal cap. Source defaults deliberately do not invent them. Confirm the duration and the distinction between weight and payout caps.
3. **BMC compatibility:** verify live source and implementation against the fixed address, decimals, transfers/fees, administrative powers and runtime. The saved public-RPC snapshot is evidence of limited reads only; mock tests are not live integration verification.
4. **Independent security review and explicit launch authorization:** follow [docs/SECURITY_REVIEW.md](docs/SECURITY_REVIEW.md). Passing tests and the free IMD input check are not security audits or approval to hold funds.

See [deployment/funding responsibilities](docs/DEPLOYMENT.md), [public interface specification](docs/INTERFACE.md), and [verification report](docs/VERIFICATION.md).
