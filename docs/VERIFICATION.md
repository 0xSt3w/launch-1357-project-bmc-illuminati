# Verification results

Local checks recorded on **2026-10-12 UTC**, using Foundry **1.8.5** (`51a52c59cffd940f76eddd0b4bb1791aa4b5ac7f`) and the compiler pinned in `foundry.toml`, **Solidity 0.8.26**. These are author-run checks, not an independent security review.

## Commands and outcomes

| Command | Observed result | Evidence |
| --- | --- | --- |
| `forge build` | Pass, exit 0 | [build log](checks/forge-build.log) |
| `forge test` | Pass: 80 reported cases, 0 failures/skips | [test log](checks/forge-test.log) |
| `forge test --match-test 'testFuzz.*' --fuzz-runs 10000` | Both fuzz tests pass, 10,000 runs each | [extended fuzz log](checks/extended-fuzz.log) |
| Empty environment, `forge test --threads 4` | Full suite passes: 80 reported cases | [empty-environment log](checks/empty-environment-test.log) |
| `forge coverage --no-match-contract StakingInvariantTest --report summary` | Pass; production contract metrics below | [coverage log](checks/coverage.log) |
| `forge fmt --check` | Pass, exit 0 | [format log](checks/format-check.log) |
| `imd launch check .` | Not runnable as a launch: no `launch.json`, exit 1 | [local launch-check log](checks/imd-launch-check.log) |
| Free `POST https://api.imd.fun/requests/check` | HTTP 200, `judged: true`, **`blockers: []`** on corrected source-only request | [request](checks/imd-check-request.json), [raw response](checks/imd-check-response.json) |

The delivered suite contains **79 unit/fuzz tests and five stateful invariants**. This Foundry version groups the five invariants into one reported case, yielding 80 total reported cases across nine suites. Each full stateful run performed **128 sequences × 128 actions = 16,384 calls with zero unexpected reverts**. Valid-action guards in the handler skip inapplicable actions; the unit suite separately tests their failure paths. `afterInvariant` expires the program, returns all principal/NFTs, claims all whole-unit rewards, recovers only allowable residues and checks complete conservation, leaving only direct donations.

No delivered test forks a live chain, reads environment variables, invokes shell/network tools, writes environment variables or requires FFI/filesystem cheatcode access. Tests mint/etch mocks locally at the fixed BMC address; this proves accounting behavior, not the live token implementation. The empty-environment run invoked the installed Forge binary by absolute path solely because `PATH` was absent. The project itself has no machine-specific compiler path.

## Coverage and bytecode

For `src/BMCStaking.sol`, the unit/fuzz coverage run reports:

| Measure | Result |
| --- | ---: |
| Lines | 282/282, 100% |
| Statements | 394/399, 98.75% |
| Branches | 54/59, 91.53% |
| Functions | 33/33, 100% |

Stateful invariants were excluded from coverage instrumentation and were run separately in both normal and empty-environment suites. Coverage uses Foundry's unoptimized instrumentation, not the production bytecode. High coverage is not a security guarantee; certain defensive conditions depend on unsupported/malicious external behavior and are not all independently reached.

Production optimizer output is **13,292 runtime bytes** and **13,572 initcode bytes before constructor arguments**. There are no external library link references. [Build details](checks/build-artifact.json) record hashes and the treasury immutable locations; a template runtime hash is not the hash of a future deployed instance. [Source hashes](checks/source-sha256.txt) and [dependency hashes](checks/dependency-sha256.txt) identify the checked source/configuration. The latter was also verified against the delivered files.

## Behavior exercised

| Area | Meaningful scenarios |
| --- | --- |
| Funding/control | Unset/set integration, unfunded start rejection, net funding, exact allocation and residue, funding aggregation, fixed postactivation settings, wrong chain, EOA/invalid multisig rejection, unauthorized administration, reserve cap |
| Token staking | Proportional/staggered deposits, partial/full exits, retained earned rewards, late-depositor exclusion from idle rewards, exhaustion, pause, same-block restrictions, ownership and allowance failures |
| Transfer fees | Funding/deposit/claim/withdrawal/recovery fees, changing fees, minimum receipts and rollback, zero receipts, optional-return tokens, false-return tokens, unsupported sender surcharges/reflection, raw-unit decimal independence |
| NFT staking | All four tier weights, pending/final assignment, no ID-based mystery inference, inconsistent tiers, owner/operator distinction, custody, double staking, ownership transfer, receiver failure, direct safe-transfer rejection, metadata outage exits |
| Combined bonus | Both deposit orders, net minimum threshold, exposure and 20% weight cap, immediate reduction/cessation on either exit, resumed eligibility without backpay, transfer between users without overlapping bonuses, separate funded cap |
| Settlement/math | Idle periods, recovery timing, final dust prerequisites, indefinite unclaimed whole units, all recovery orders, repeated claims and fractions, maximum funding/principal and single-unit stake index bounds |
| Adversarial calls | ERC20 transfer reentry into funding/deposit/withdrawal/claim/recovery, NFT recipient reentry, rejected receiver rollback, exogenous reward deficit with backed principal exits |
| Stateful invariants | Independent principal/custody ledgers, changing fees, pause, donations, NFT ownership transfer, payouts, recoveries, principal solvency, each pool's pending+paid cap and end-to-end closure |

Foundry lint emitted pattern warnings described and locally assessed in [SECURITY_REVIEW.md](SECURITY_REVIEW.md). They are not hidden. Slither and Mythril were not installed in the provided toolset and were not run. No independent reviewer has signed off.

## Free IMD check and blockers

The public free input check is documented at [IMD's request-check route](https://imd.fun/docs/#requests-check). It validates a request description/planning input; **it does not inspect or audit the source tree**. Only this free endpoint was called. No quote, paid submission, signature, wallet approval, token transfer, new work order or deployment was initiated.

The first `impl_tests_review` template request returned `bad_path_count` for the implementation/tests nodes. Supplying top-level paths alone produced the same result. The final request uses explicit steps with allowed paths on the implementation/test step and reports **no blockers**. Earlier request/response pairs are retained with `-initial` and `-template` filenames for transparency. The final response includes a nonblocking classification suggestion: it recognizes ordinary smart contracts and suggests the `contracts` kind. This was not used to authorize a launch.

Separately, the installed CLI's `imd launch check .` exits with `has no launch.json`. A launch manifest is intentionally absent: this is a source-only assignment, and neither real NFT/treasury deployment inputs nor launch authorization have been supplied. Do not invent a manifest or addresses just to make that distinct check pass. The authorized deployment coordinator must run it on the later reviewed launch package.

## Limited live BMC observation

A read-only public RPC observation at Ethereum block **26,173,332** found **2,847 runtime bytes** at the supplied BMC address and returned name **BMC Illuminati**, symbol **BMC**, and **18 decimals**. The timestamp, endpoint, exact read results and runtime SHA-256 are saved in [bmc-mainnet-read.json](checks/bmc-mainnet-read.json). Explorer source retrieval was unavailable (HTTP 403); the attempted Sourcify full-match metadata route returned 404. No assertion of source verification follows from either failure or the RPC reads.

Before deployment, independently verify live BMC source/behavior, the final NFT address and exact ABI, the actual multisig, minimum/exposure parameters and approved funding/duration. Complete the independent review, resolve findings and obtain explicit requester approval. No mainnet deployment or staking activation has occurred in this work.
