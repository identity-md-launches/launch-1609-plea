// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title PLEA
/// @notice Fixed-supply ERC-20 for imdacc.fun, with 18 decimals.
/// @dev The deploying account receives the entire supply. When deployed by a
/// factory, the factory receives the tokens and handles their distribution.
contract PLEA is ERC20 {
    /// @notice One billion PLEA, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mint the complete, permanent supply once to the deployer.
    constructor() ERC20("PLEA", "PLEA") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
