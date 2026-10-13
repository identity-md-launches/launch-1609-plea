// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PLEA} from "../src/PLEA.sol";

/// @dev Keeps an independent ledger for a closed set of local test actors.
contract PLEAHandler is Test {
    PLEA public immutable token;
    address[4] public actors;
    uint256[4] public expectedBalance;
    mapping(uint256 owner => mapping(uint256 spender => uint256 amount)) public expectedAllowance;

    constructor() {
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("invariant actor ", vm.toString(i)));
        }
        token = new PLEA();
        expectedBalance[0] = 1_000_000_000 * 10 ** 18;
        require(token.transfer(actors[0], expectedBalance[0]), "initial transfer failed");
    }

    function transfer(uint256 from, uint256 to, uint256 amount) external {
        from %= actors.length;
        to %= actors.length;
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(actors[from]);
        assertTrue(token.transfer(actors[to], amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 owner, uint256 spender, uint256 amount) external {
        owner %= actors.length;
        spender %= actors.length;
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spender, uint256 from, uint256 to, uint256 amount) external {
        spender %= actors.length;
        from %= actors.length;
        to %= actors.length;
        uint256 approved = expectedAllowance[from][spender];
        uint256 available = expectedBalance[from] < approved ? expectedBalance[from] : approved;
        amount = bound(amount, 0, available);
        vm.prank(actors[spender]);
        assertTrue(token.transferFrom(actors[from], actors[to], amount));
        if (approved != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function transferTooMuch(uint256 from, uint256 to, uint128 excess) external {
        from %= actors.length;
        to %= actors.length;
        uint256 amount = expectedBalance[from] + uint256(excess) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, actors[from], expectedBalance[from], amount
            )
        );
        vm.prank(actors[from]);
        token.transfer(actors[to], amount);
    }
}

contract PLEAInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    PLEAHandler private handler;
    PLEA private token;

    function setUp() public {
        handler = new PLEAHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = PLEAHandler.transfer.selector;
        selectors[1] = PLEAHandler.approve.selector;
        selectors[2] = PLEAHandler.transferFrom.selector;
        selectors[3] = PLEAHandler.transferTooMuch.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_FixedSupplyAndExactAccounting() public view {
        uint256 balances;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(i));
            balances += balance;
            for (uint256 j; j < 4; ++j) {
                assertEq(token.allowance(actor, handler.actors(j)), handler.expectedAllowance(i, j));
            }
        }
        assertEq(balances, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }
}
