# PLEA test coverage

The suite deploys the actual `src/PLEA.sol` with the existing vendored libraries.
It requires no RPC, environment variables, downloaded test dependencies, FFI, or
changes to the token's storage. Actor addresses and the contract-holder fixture
are local test participants, not launch configuration.

| File | Properties |
| --- | --- |
| `PLEA.t.sol` | Exact name, symbol, decimals and constructor mint; CREATE2 factory ownership; untaxed distribution; events; transfers and approvals; invalid addresses, balances and allowances; absent mint, burn and administration entrypoints. |
| `PLEAAdversarial.t.sol` | Exhausted approval cannot be reused after replenishment; maximum finite versus infinite allowance; reduction and revocation; owner/spender isolation; failed-spend rollback and successful retry; overlapping caller/owner/recipient roles; round trips and split-transfer equivalence; nonpayable calls; contract recipients. |
| `PLEAInvariant.t.sol` | Random operation sequences checked against an independent ledger, followed by full-balance transfer liveness. |

## Stateful properties

Four actors form a closed set: the handler initially transfers the complete
constructor mint to one actor, and every successful transfer stays within that
set. Ghost balances and the entire 4-by-4 allowance matrix are updated from the
requested operations, not copied from token getters. After each handler call:

- Each balance and allowance must equal its independently tracked value.
- The sum of actor balances and `totalSupply()` must both equal `10**27`.
- Metadata must remain `PLEA`, `PLEA`, and 18 decimals.
- No tokens may appear at the zero address, token, or emptied deployer, and no
  actor may have approved the zero spender.

Ten targeted handler actions exercise transfers, approvals, delegated transfers,
approval boundaries, positive approved spending, round trips, insufficient
balances, insufficient allowances, and invalid recipients/spenders. Failed calls
must return the exact custom error and leave the ledger unchanged. Allowances
are allowed to exceed supply; only `uint256.max` has infinite-approval semantics.

The ordinary delegated-transfer action uses approvals left by earlier actions.
An additional approve-and-spend action deliberately selects a funded actor and a
positive amount, so the campaign exercises real spends. Round trips also use
positive amounts and distinct accounts, with balance checks at the midpoint.
The `afterInvariant` hook transfers every remaining balance into one actor and
rechecks the complete ledger, verifying that any preceding call sequence leaves
holders able to move their tokens.

Inline configuration runs each of nine fuzz properties 1,000 times and the
invariant for 256 sequences of 128 handler calls. Unexpected handler reverts fail
the campaign. Bounds generate useful inputs without discarded assumptions.
Deterministic tests also pin zero, one minor unit, full supply, `uint256.max - 1`,
and `uint256.max`.

## Running locally

With Foundry and Solidity 0.8.26 installed:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

Plain `forge build` and `forge test` also work. The flags above keep generated
artifacts inside the assignment's scratch directory; the submitted tests do not
import or depend on anything there.

The supplied protected launch harness was read as an acceptance reference. Its
Uniswap pool and live launch configuration are not present in this standalone
repository, so these tests do not claim to execute that integration. The existing
factory distribution test checks token amounts using local actors.
