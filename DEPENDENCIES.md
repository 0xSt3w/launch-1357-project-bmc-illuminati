# Vendored dependencies

All Solidity dependencies are committed as ordinary source files. No submodule, symlink, package installation, compiler binary or `node_modules` directory is required to build or test. `foundry.toml` contains the complete remapping and compiler configuration. Vendored files are not locally modified and are excluded from project formatting.

| Dependency | Pinned version | Vendored contents | License |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | 5.0.2 | Transitive closure of `SafeERC20`, `IERC20`, `IERC721`, `IERC721Receiver`, `IERC165`, `ReentrancyGuard`, `Math`, and ERC20/ERC721 test mock bases | [MIT](lib/openzeppelin-contracts/LICENSE) |
| forge-std | 1.9.7 | `src/` test utilities | [MIT](lib/forge-std/LICENSE-MIT) / [Apache-2.0](lib/forge-std/LICENSE-APACHE) |

OpenZeppelin publishes tagged release and audit information through its [Contracts security center](https://contracts.openzeppelin.com/security) and [release documentation](https://docs.openzeppelin.com/contracts/5.x). The selected 5.0.2 files retain their original SPDX headers. Audited library use does not audit the application. Independent reviewers must reassess relevant advisories at release time.

Download provenance (used during implementation, **not** needed during verification):

| Archive | Source | SHA-256 |
| --- | --- | --- |
| `contracts-5.0.2.tgz` | `https://registry.npmjs.org/@openzeppelin/contracts/-/contracts-5.0.2.tgz` | `709a5996fd3fdccc1b3b38c4b87dcafa103b9126b63839f248c4172ba21093fa` |
| `forge-std` tag `v1.9.7` tarball | `https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7` | `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94` |

The OpenZeppelin license was obtained from its `v5.0.2` repository tag. [The file hash list](docs/checks/dependency-sha256.txt) covers the delivered dependency sources and licenses. The upstream security reference supplied with the assignment was read as a checklist; it is not a runtime or test dependency and no removed `.imd/reads` inputs are imported by the project.
