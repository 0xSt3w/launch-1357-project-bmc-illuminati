# Accounting and invariants

All amounts are raw units. No `decimals()` assumption enters arithmetic. Funding and total principal are each bounded by `2^128 - 1`; individual account values cannot exceed these totals. NFT IDs are bounded to the 500-item collection. Pools use OpenZeppelin `Math.mulDiv` with a `2^128` index scale.

## Budget conservation

Let `F` be the total actual funding received, `P` principal, `R` remaining reward reserve, `C` gross rewards paid and `T` gross recovered by treasury. Direct uncredited donations are `D`.

```text
F = R + C + T
balance = P + R + D           (for supported ERC20 behavior)
token budget = floor(F * 55 / 100)
NFT budget   = floor(F * 25 / 100)
bonus budget = floor(F * 15 / 100)
reserve      = F - sum(budgets)
```

Every principal deposit increases `P` by the contract's measured balance gain. Every principal withdrawal decreases `P` by the exact balance debit. Neither changes `R`, `F`, or a reward budget. Reward payouts decrease `R` and increase `C` by the gross debit; treasury recoveries similarly move value from `R` to `T`. Transfer fees deducted within the gross transfer are included in that debit. The recipient's net balance gain is separately measured and emitted.

Before reward transfers/recoveries, and before new BMC/NFT deposits, the contract checks full principal-plus-reserve backing. Outgoing transfer checks enforce exact debit and remaining principal backing. Reward sends also recheck full backing afterward. Principal exits deliberately do not require reward-reserve solvency, so a reward-only external balance loss does not block backed principal.

## Per-pool state

| Field | Meaning |
| --- | --- |
| `budget` | Fixed allocation from actual funding |
| `emitted` | Cumulative vested amount as of the last checkpoint |
| `allocated` | Cumulative emission during intervals with nonzero weight |
| `totalWeight` | Current sum of eligible account weights |
| `rewardPerWeight` | Monotonic scaled reward index |
| `accrued` | Sum of whole-unit rewards already checkpointed into accounts and not paid |
| `paid` | Cumulative gross claims charged to this pool |
| `recovered` | Cumulative treasury returns from this pool |
| `idleRecovered` | Portion of zero-weight emissions already returned |

At all times:

```text
0 <= allocated <= emitted <= budget
paid + accrued <= allocated
paid + accrued + recovered <= budget
sum(account pending rewards) + paid + recovered <= budget
sum(budget - paid - recovered) + uncommittedReserve == rewardReserve
```

`accrued` alone is **not** the entire current reward liability while weights remain: some users have not yet checkpointed. The contract never uses it as the sole reserve requirement during an active position. Only after expiry and every position exits is it complete; each exit checkpoints before reducing weight, including bonus weight. This is the basis of safe final dust recovery.

## Timing and rounding

Vesting uses a cumulative floor of `budget * elapsed / duration`, not a prematurely truncated integer reward rate. This releases every budget unit by expiry even for budgets smaller than the number of program seconds. A pool checkpoint records the entire newly vested amount as emitted. If total weight is zero it remains unallocated; otherwise it is allocated and its scaled index is advanced by a floor division.

For each account, the index difference is multiplied by its **old** weight. `Math.mulDiv` gives whole units, and `mulmod` gives the fraction. The previous fraction is added; any full unit is carried into accrued rewards and the residual fraction is retained. Checkpointing happens before both increases and decreases of every affected weight. This avoids retroactive rewards and reward-debt rounding exploits when principal/NFTs move.

Per-pool index rounding only loses value into dust, never creates obligations. With pool total weight at most `2^128 - 1` for tokens (bonus is smaller), each global index division discards less than one raw BMC unit of reward value. NFT weights are far smaller. Each account carries less than one unit of fractional entitlement. Fractions cannot become claimable after expiry once all weights are zero, so they are part of recoverable final dust. Earned whole units remain claimable forever. In extreme repeated checkpointing, dust can accumulate; this is visible and cannot increase attacker rewards.

The total index is bounded above by `budget * 2^128`, which fits `uint256` because funding is bounded by `uint128`. `Math.mulDiv` handles intermediate products; adding two account remainders is below `2^129`. The known collection range also bounds NFT-weight multiplication by the configured `uint128` linked cap.

## Bonus uniqueness and timing

There is one principal balance, NFT weight and derived bonus weight per account. NFT custody maps each ID to exactly one depositor. The bonus pool cannot consume the token or NFT pools' allocations. Every stake or withdrawal checkpoints all three modes before recalculating the bonus. There is no separate enrollment, receipt token or transferable reward ownership.

New deposits have no prior index entitlement. Timestamps do not advance inside a block, and the contract additionally disallows BMC withdrawals in the latest BMC-deposit block, NFT withdrawals in their deposit block, and claims in the latest stake block. These rules prevent conventional atomic flash deposits. Rewards over distinct blocks reflect actual time exposed to staking; the contract does not attempt to prohibit ordinary short-duration staking across blocks.

## Model limits

Conservation assumes a truthful, non-rebasing ERC20 whose sender debit equals the requested gross transfer, and a truthful ERC721 that enforces custody and immutable finalized tiers. A balance check cannot make a malicious dependency safe. A token pause/blocklist, external confiscation or NFT collection transfer freeze can still affect users. These dependencies are explicit independent-review requirements.
