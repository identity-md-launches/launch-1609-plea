# Vendored dependencies

These are ordinary source files, not git submodules. No dependency install step is
needed. Upstream source files and licenses are unmodified; `SHA256SUMS` records their
individual hashes relative to the repository root.

| Directory | Upstream release | Included files | License |
| --- | --- | --- | --- |
| `openzeppelin-contracts/` | [OpenZeppelin Contracts v5.4.0](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.4.0) | `ERC20.sol` and its four transitive imports, plus license | MIT |
| `forge-std/` | [Forge Standard Library v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `src/` and both license files | MIT OR Apache-2.0 |

Downloaded from the corresponding release-tag archives at
`https://codeload.github.com/<owner>/<repo>/tar.gz/refs/tags/<version>`.
The SHA-256 hashes of the downloaded archives were:

```text
b89829be48bc501051002191733268a93ef6e238a4bb65d8fd1cbdf3969050d1  OpenZeppelin/openzeppelin-contracts v5.4.0
45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94  foundry-rs/forge-std v1.9.7
```

Verify individual files from the project root:

```sh
sha256sum --check lib/SHA256SUMS
```

Only the OpenZeppelin subset is used by production code. Forge Standard Library is
used only by local tests. Neither dependency needs linked deployed libraries.
