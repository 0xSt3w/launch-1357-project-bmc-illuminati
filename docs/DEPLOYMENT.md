# Deployment and funding responsibilities

**Instructions for a later authorized launch only. No transaction was executed or requested in this assignment.** The current repository contains no broadcast script or launch manifest. The deployment coordinator must create a reviewed manifest only after the missing inputs are supplied. Do not deploy any part of this NFT/combined program before verifying the collection address and exact interface.

## Inputs to obtain before deployment

| Input | Source and validation |
| --- | --- |
| Chain | Ethereum mainnet, chain ID 1, from the brief; funding/activation enforce it |
| BMC | Fixed source constant `0x38224239f2BDae357D47cb864BC533d7f72dF961`; verify explorer source, runtime, decimals, supply/authority and transfer behavior |
| Treasury | Requester's actual reviewed Safe-compatible multisig; never the factory, deployer, single EOA, test address or guessed address |
| NFT collection | Requester's independently reviewed deployed BMC Illuminati Pass; verify code, ownership, safe transfers, final tiers, assignment function and ERC165 support |
| Review hash | Hash of the review/integration artifact covering the exact collection runtime and semantics; publish the artifact |
| Program funding | Treasury-approved gross funding and minimum acceptable net funding after BMC fees |
| `minimumBMC` | Requester-approved minimum combined principal, expressed in confirmed BMC raw units |
| `linkedBMCPerWeight` | Requester-approved maximum linked principal per unit of NFT weight, in raw units |
| Duration | Default 31,536,000 seconds (365 days); publish any authorized preactivation revision |

No deployment addresses or economic amounts are prefilled in a script or manifest. Test fixture choices are not recommended or authorized launch parameters. The fixed 55/25/15/5 split cannot be changed. A different split or a payout-percentage bonus cap requires new source and independent review.

## Review and deployment sequence

1. Obtain all real inputs above. Review the exact repository revision and dependency hashes. Complete the separate review in [SECURITY_REVIEW.md](SECURITY_REVIEW.md), including mainnet BMC and final NFT integration tests. Resolve all launch-blocking findings. Obtain explicit requester approval to deploy.
2. Publish the approved parameters, budgets, intended bytecode and review artifacts. The deployment coordinator should verify the treasury's implementation, distinct signers, threshold at least two, modules, fallback handler and absence of unilateral bypasses. Interface introspection alone is not security verification.
3. The authorized coordinator deploys **only** `BMCStaking(realTreasuryAddress)`, without a proxy and without creating a token. The constructor makes no external calls and sets no factory ownership. It has one argument and fits the deployment contract-name/argument constraints. Source-verify the deployed bytecode before funding.
4. The designated multisig calls `configureProgram(365 days, approvedMinimumRaw, approvedLinkedCapRaw)` and `configureCollection(verifiedCollection, reviewArtifactHash)`. The collection can be set only once, before activation. The program remains inert until both settings and funding exist. Confirm onchain getters and emitted events against the signed parameter sheet. Check ERC165 support for both ERC721 and the custom interface ID generated from the final reviewed ABI.
5. After separately authorized manual funding, the multisig approves **exactly** the intended gross BMC amount to staking and calls `fundRewards(gross, minimumNet)`. No other caller may fund through this entry point. Record `RewardsFunded.received`; confirm balance, `totalFunded` and `rewardReserve`. Revoke any unused allowance if the token leaves one. **Do not transfer BMC directly to the contract:** it will not be counted as funding and cannot be swept.
6. Compute the 55/25/15 budgets from actual cumulative net funding, with residue in reserve. If more funding is needed, make another authorized exact-allowance funding call now. Funding is irrevocably committed, and there is no preactivation cancellation/refund or active-program top-up.
7. With explicit authorization to enable staking, the multisig calls `activate()`. Record the returned event's start, end, budgets and reserve. If deposits were previously paused, only an authorized multisig unpause opens them. Activation does not certify that a review happened; offchain release control is essential.
8. Publish only the independently verified deployed address and reviewed UI. All participants should see real net/gross amounts, withdrawal conditions and the finite funded budgets before choosing to stake.

## After launch

| Setting/control | Responsible party | Operational rule |
| --- | --- | --- |
| `configureCollection` | Treasury, once **before activation** | Use the deployed address supplied by the NFT project and covered by independent review; never a placeholder. Required verification occurs before deploying staking itself. |
| `configureProgram` | Treasury, **before activation** | Use requester-approved raw-unit minimum/cap and duration; public events record changes. Immutable after activation. |
| `setDepositsPaused(bool)` | Treasury | Stop new stakes during an incident. Claims, withdrawals, reward time and earned amounts continue. |
| Multisig signers/threshold/modules | Treasury governance | Maintain the independently approved security policy; reducing threshold below two disables treasury calls but not user exits. No staking treasury rotation exists. |
| Reserve recovery | Treasury | Bound to remaining uncommitted reserve; record gross and net. Cannot use principal. |
| Expiry settlement | Treasury | Recover idle emissions at/after end; recover rounding remainder only once all BMC and NFT positions are gone. Repeated calls cannot recover the same units twice. |
| Unclaimed rewards | Users | Claim indefinitely; exits do not forfeit whole-unit rewards. |
| Monitoring | Operator/reviewer | Check principal/reserve backing, reward caps, dependencies, pause events, Safe changes and unexpected direct transfers. No operator custody or extra onchain privileges. |

The contract has no automatic reinvestment or program restart. A future program requires its own independently reviewed deployment; user principal cannot be automatically migrated.

## Incident handling

Pause new deposits if appropriate, publish the incident and preserve withdrawal/claim access. There is no administrator emergency sweep or force-withdrawal. Users withdraw their own backed principal/NFTs. Metadata outages do not block NFT exits; collection-level transfer freezes may. Unsupported BMC behavior may require a separately reviewed external response, but cannot justify taking other users' principal or changing accrued rewards. Never claim that a pause by this contract can override restrictions imposed by BMC or the NFT contract.
