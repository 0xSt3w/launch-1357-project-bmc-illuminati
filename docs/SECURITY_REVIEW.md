# Independent security review and release gates

Status: **required and not completed**. The implementation author's tests, accounting notes, lint triage and free IMD input check are not an independent security audit. An independent reviewer/contributor must assess the exact final source revision, vendored dependencies, configured economics and real external contracts before deployment. The requester must then explicitly approve deployment and activation. This assignment authorizes neither.

## Required review scope

1. **Reward math and economics.** Prove cumulative vesting, per-share indices and per-account fractions cannot overpay under adversarial sequences. Independently model tiny budgets, very large amounts, repeated checkpoints, empty intervals, entry/exit at boundaries, and tier-weight changes on ownership transfer. Review `uint128` aggregate bounds and all `Math.mulDiv`/`mulmod` assumptions. Confirm that the 20% rule caps bonus weight, not realized payout relative to the token pool. Obtain written agreement to this interpretation and the chosen minimum/exposure cap.
2. **Solvency and settlement.** Reproduce principal/reward conservation across incoming/outgoing fees, claims, donations and each treasury recovery order. Review every path capable of transferring BMC or NFTs. Verify that active position liabilities cannot be mistaken for `Pool.accrued`, and that final dust recovery preserves all unclaimed whole-unit rewards indefinitely. Consider held-open positions delaying dust recovery. Check insolvency behavior without granting first-withdrawer priority over unbacked principal.
3. **Permissions.** Verify constructor ownership is the actual designated multisig, never the factory or deployer by default. Independently verify the wallet bytecode, signers, threshold, modules and upgrade/control paths; a fake contract can answer `getOwners`/`getThreshold`. Confirm no single-key execution bypass, no treasury rotation, no proxy, no arbitrary sweep, and no administrative route to user principal/NFTs. Check funding sources, recovery recipients and all event/state relationships.
4. **Actual BMC integration.** Obtain verified mainnet source, source-to-runtime match and any implementation/admin contracts. Check confirmed decimals, actual balance movements, fee ownership/exemptions/limits, rounding, transfer return values, ability to pause/blocklist/confiscate/change behavior, callbacks, supply changes and token upgrades. Reproduce funding, staking, withdrawal and claims against the actual mainnet code in an isolated fork at a pinned block. Mock minting in `test/` is never a production dependency. Sender surcharges, reflection and rebasing are unsupported; fail the launch if actual behavior is incompatible.
5. **Actual NFT integration.** Review the final deployed collection and the exact proposed ABI. Verify the 500 supply, ID classes, 37 mystery Genesis, 423 Standard, reveal/assignment mechanism and final-tier immutability. Check ERC165 IDs, return encodings, nonexistent IDs, placeholder artwork, unusual recipients, ownership changes and any token/collection pause or seizure controls. Prove stake custody cannot leave the vault through another authorization path. Confirm final artwork/tier functions and safe transfer mechanics cannot be spoofed. If signatures or function names differ, revise the integration and repeat review before any staking deployment.
6. **Adversarial calls.** Exercise malicious token callbacks, inbound/outbound ERC721 callbacks, receiver failures, stale allowances, same-block round trips, flash loans, malicious Safe-compatible introspection and direct/unsafe NFT sends. Review every external-call boundary, including read-only calls and fee balance measurements. Check metadata failures cannot block withdrawals.
7. **Operations and interface.** Match UI reads/actions to the public interface. Verify gross versus net amounts, no APY promise, exact approvals, one-block withdrawal restrictions, public configuration, fixed finish time, pause semantics, indefinite claims and direct-transfer warnings. Simulate full lifecycle and incident response with the real multisig and dependencies. Review activation and manual funding separately.

## Evidence and acceptance

The reviewer should produce a signed or independently published report identifying the repository revision, Solidity/compiler settings, dependency hashes, deployable bytecode hash, chain/block snapshots, treasury, NFT and token source/runtime hashes, exact parameters, tools and test seeds. Each finding should include severity, impacted invariant, minimal reproduction and resolution/retest evidence. Launch-blocking findings must be resolved, and accepted residual risks must be explicitly approved by the requester. Any source, dependency, ABI or economic change after review invalidates the reviewed build until rechecked.

Run at minimum the delivered Foundry suite, adversarial reference-model tests, extended fuzzing and stateful invariants against the proposed final configuration. Use Slither and/or an equivalent analyzer and independent manual review of the fund-flow and external dependency code. Tools must be pinned and their findings adjudicated; a green report is not proof of safety. Slither/Mythril were not installed in this assignment's provided toolset and were not run.

## Author's local lint triage (not independent findings)

`forge build` runs Foundry's lint pass and reports pattern warnings. They remain visible in the saved build log:

| Pattern | Local assessment to independently verify |
| --- | --- |
| Reentrancy around ERC721 transfers or events after calls | All state-changing entry points use OpenZeppelin `nonReentrant`; reward/withdrawal state changes precede sends. Token/NFT reentry tests confirm rejection. Inbound deposits measure receipts under the guard. The ERC721 receiver is a read-only exact-transfer gate. Net-received events necessarily follow measurement. |
| Transient NFT receive-gate ID lacks a separate event | `expectedNFTId`/owner exist only during the guarded deposit transfer; final `NFTStaked` records ID and owner. This is not a changeable authority. |
| Timestamp comparisons | Deliberate fixed program time boundaries; timestamps are not randomness or price inputs. Review miner/validator boundary effects. |
| Reverts inside loops | Explicit cap checks across three pools and validation of at most 50 multisig owners. No unbounded user enumeration appears in staking actions. |

No external review or production-safe status is claimed by these assessments. See the verification report for actual local commands, limits and the free IMD input-check response.

## Known operational limitations requiring acceptance

- The immutable treasury has no rotation; its signer governance must remain functional. At least two signatures and at most 50 distinct owners are required on privileged calls, but actual multisig semantics remain an external trust assumption.
- The collection binds once before activation. An incorrectly reviewed ABI/address requires abandoning this deployment; there is no arbitrary metadata adapter or administrator replacement.
- Funding cannot be canceled or topped up after activation. Before activation it has no refund route. A program that is funded but never activated has committed funds locked; review all settings first.
- All emissions during zero-weight intervals expire as unallocated. Pause blocks deposits but does not stop time or existing rewards.
- Finalized NFT tiers are assumed immutable. Existing position snapshots do not dynamically follow unauthorized later tier edits.
- Token/NFT dependency freezes can prevent their transfers. BMC-level sender surcharges/reflection/rebases are unsupported. External confiscation cannot be repaired by changing earned balances or taking other users' principal.
- Direct BMC donations and unsafe NFT transfers are not registered deposits and have no rescue function. Safe unsolicited NFT transfers are rejected. No generalized rescue power was added that could be used against legitimate custody.
- The requested repository/PR is supplied through the contributor-network submission process. This source-only task does not itself publish a remote repository or deploy a website.
