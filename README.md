# PLEA

A fixed-supply ERC-20 token for **imdacc.fun**.

| Parameter | Value |
| --- | --- |
| Solidity contract | `PLEA` in `src/PLEA.sol` |
| Name / symbol | `PLEA` / `PLEA` |
| Decimals | 18 |
| Supply | 1,000,000,000 PLEA |
| Supply in smallest units | `1000000000000000000000000000` (10^27) |
| Constructor arguments | None (`[]`) |
| Initial recipient | The deploying account, `msg.sender` |
| Launch chain | Ethereum, chain ID 1 |

## Design and assumptions

The complete supply is minted once in the constructor, emitting
`Transfer(address(0), deployer, 10^27)`. There is no external mint or burn function,
owner, administrator, initializer, pause, blacklist, tax, rebase, upgrade mechanism,
or token recovery function. Neither the deployer nor anyone else can change the
metadata, increase supply, or move a holder's tokens without that holder's approval.

The brief specifies a plain custom token, so the implementation uses the unmodified
OpenZeppelin Contracts v5.4.0 ERC-20 implementation with a constructor-only supply
mechanism. The website is project information documented here and in the contract's
NatSpec; the token makes no website calls and has no mutable website setting.

Transfers deliver the exact requested amount and return `true` on success. Invalid
operations revert with ERC-20 custom errors. Zero-value transfers are supported;
zero-address transfer recipients and approval spenders are rejected. Finite
allowances decrease when spent; a `uint256` maximum allowance remains unchanged.
`approve` emits `Approval`; allowance consumption by `transferFrom` does not emit a
separate `Approval` event. A holder calling `transferFrom` on their own balance
still needs an allowance; `transfer` needs none.

## Build and test

Install Foundry and make Solidity **0.8.26** available to it. All Solidity libraries
are vendored as ordinary files in `lib/`; no package installation, submodule,
network RPC, environment variables, FFI, or filesystem permissions are needed by
the tests. See [dependency provenance](lib/README.md).

```sh
forge build
forge test
forge fmt --check
```

The root `foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimization
with 200 runs, and `bytecode_hash = "none"`. An offline verification machine needs
Foundry and the pinned compiler preinstalled; no compiler binary is vendored.

Tests cover metadata, mint events, actual CREATE2 factory deployment, exact launch
allocation transfers, onward claims, transfers in both directions with a simulated
pool account, approvals, allowance consumption and revocation, zero and maximum
values, self-transfers, unauthorized transfers, failed-operation rollback, absent
administrative entrypoints, and rejection of ordinary ETH payments. Four fuzz
tests run 512 cases each. A stateful invariant runs 256 sequences of 64 calls and
compares every tracked balance and allowance with an independent ledger, including
failed transfers interspersed with successful operations.

The local allocation test models token movements only. It does not deploy Uniswap
or verify Merkle proofs. The supplied protected integration harness belongs to the
network's verifier and requires its factory, pool implementation, launch parameters,
and creation-bytecode configuration; it is not part of this standalone test suite.

## Deployment and operations

Deploy the creation bytecode of `src/PLEA.sol:PLEA` with **no constructor arguments
and no ETH value**. No initialization calls, linked libraries, owner address,
external contracts, or additional application contracts are required. The
constructor makes no external calls. `forge inspect src/PLEA.sol:PLEA bytecode`
prints the creation bytecode for review; this command does not broadcast anything.

For the intended factory launch, the factory is `msg.sender` and receives all
10^27 units. The user who calls the factory does not receive the constructor mint.
A direct deployment by a wallet instead gives the wallet the full supply. Any
deployment intermediary must be able to distribute the tokens it receives.

Distribution is the launch factory's responsibility, not token logic. The supplied
launch terms allocate 10% (100,000,000 PLEA) to the launch's distributor, 87%
(870,000,000 PLEA) to liquidity, and 3% (30,000,000 PLEA) to
`0xee2aaa315cf7ed169f93148d30d24af9318dbb66`. These percentages and addresses are not
hardcoded in PLEA, and no balance is reserved inside this token. The launch's
separate manifest step owns `launch.json` and the pool configuration.

### After launch

There are no owner-settable values or maintenance transactions. The network's
deployer must verify the deployed source and build settings, check `name`, `symbol`,
`decimals`, and `totalSupply`, confirm the constructor mint recipient and subsequent
factory distributions, and publish the actual token address on the project's
website. The launch operator is responsible for the pool and distributor setup.

Holders manage their own custody and allowances. An approved spender can move
tokens up to its allowance; replacing a nonzero allowance can race with spending,
so applications should revoke an existing allowance before granting a replacement
and prefer bounded amounts. There is no privileged recovery of mistaken transfers.
Sending tokens to this token contract or to a recipient unable to send them onward
can lock them permanently. Ordinary ETH payments revert; forcibly delivered ETH
also has no recovery path.

## Security review boundary

The implementation and vendored ERC-20 were reviewed against the supplied security
reference for mint reachability, authorization, arithmetic, external calls, and
launch transfer compatibility. Production code has no external calls, oracle,
randomness, signature verification, delegatecall, or administrative entrypoints.
The ERC-20 implementation enforces balance and allowance checks, and the only
reachable mint is during construction. No transfer hooks require exemptions for
the factory, distributor, or pool manager.

Local Foundry testing is not an independent security audit. Slither and Mythril
were not run. The network's independent review and full protected launch integration
checks remain release responsibilities. This project does not sign, broadcast,
deploy to a live chain, or claim an explorer-verified address.
