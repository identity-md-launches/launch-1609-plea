// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PLEA} from "../src/PLEA.sol";

/// @dev Keeps an independent ledger for a closed set of local test actors.
contract PLEAHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
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

    /// @dev Exercise revocation and both sides of the infinite-allowance sentinel deliberately.
    function approveEdge(uint256 owner, uint256 spender, uint8 edge) external {
        owner %= actors.length;
        spender %= actors.length;
        uint256[5] memory amounts = [uint256(0), 1, SUPPLY, type(uint256).max - 1, type(uint256).max];
        _approve(owner, spender, amounts[edge % amounts.length]);
    }

    /// @dev Ordinary transferFrom still uses historical approvals. This additional action ensures
    /// positive delegated spends are reachable even early in a sequence, before approvals accumulate.
    function approveAndSpend(uint256 from, uint256 spender, uint256 to, uint256 amount, bool infinite) external {
        from = _fundedActor(from);
        spender %= actors.length;
        to %= actors.length;
        amount = bound(amount, 1, expectedBalance[from]);
        uint256 approval = infinite ? type(uint256).max : amount;
        _approve(from, spender, approval);
        vm.prank(actors[spender]);
        assertTrue(token.transferFrom(actors[from], actors[to], amount));
        expectedAllowance[from][spender] = infinite ? approval : 0;
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function transferFromOverAllowance(uint256 from, uint256 spender, uint256 to, uint256 approval) external {
        from %= actors.length;
        spender %= actors.length;
        to %= actors.length;
        approval = bound(approval, 0, type(uint256).max - 1);
        _approve(from, spender, approval);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, actors[spender], approval, approval + 1
            )
        );
        vm.prank(actors[spender]);
        token.transferFrom(actors[from], actors[to], approval + 1);
        // No ghost update: the invariant checks every balance and allowance for rollback.
    }

    function transferFromOverBalance(uint256 from, uint256 spender, uint256 to, uint128 excess, bool infinite)
        external
    {
        from %= actors.length;
        spender %= actors.length;
        to %= actors.length;
        uint256 amount = expectedBalance[from] + uint256(excess) + 1;
        _approve(from, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, actors[from], expectedBalance[from], amount
            )
        );
        vm.prank(actors[spender]);
        token.transferFrom(actors[from], actors[to], amount);
    }

    function rejectZeroAddress(uint256 from, uint256 spender, uint256 amount, uint8 action) external {
        from %= actors.length;
        spender %= actors.length;
        amount = bound(amount, 0, expectedBalance[from]);
        action %= 3;
        if (action == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(actors[from]);
            token.transfer(address(0), amount);
        } else if (action == 1) {
            _approve(from, spender, amount);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(actors[spender]);
            token.transferFrom(actors[from], address(0), amount);
        } else {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            vm.prank(actors[from]);
            token.approve(address(0), amount);
        }
    }

    /// @dev A positive round trip must return every minor unit and leave approvals untouched.
    function roundTrip(uint256 from, uint256 to, uint256 amount) external {
        from = _fundedActor(from);
        to = (from + 1 + to % (actors.length - 1)) % actors.length;
        amount = bound(amount, 1, expectedBalance[from]);
        vm.prank(actors[from]);
        assertTrue(token.transfer(actors[to], amount));
        assertEq(token.balanceOf(actors[from]), expectedBalance[from] - amount);
        assertEq(token.balanceOf(actors[to]), expectedBalance[to] + amount);
        vm.prank(actors[to]);
        assertTrue(token.transfer(actors[from], amount));
        // Net-zero operation: leaving the independent ledger unchanged checks the inverse.
    }

    function _approve(uint256 owner, uint256 spender, uint256 amount) private {
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _fundedActor(uint256 seed) private view returns (uint256) {
        uint256 start = seed % actors.length;
        for (uint256 i; i < actors.length; ++i) {
            uint256 candidate = (start + i) % actors.length;
            if (expectedBalance[candidate] > 0) return candidate;
        }
        revert("ghost ledger lost the entire supply");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract PLEAInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    PLEAHandler private handler;
    PLEA private token;

    function setUp() public {
        handler = new PLEAHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = PLEAHandler.transfer.selector;
        selectors[1] = PLEAHandler.approve.selector;
        selectors[2] = PLEAHandler.transferFrom.selector;
        selectors[3] = PLEAHandler.transferTooMuch.selector;
        selectors[4] = PLEAHandler.approveEdge.selector;
        selectors[5] = PLEAHandler.approveAndSpend.selector;
        selectors[6] = PLEAHandler.transferFromOverAllowance.selector;
        selectors[7] = PLEAHandler.transferFromOverBalance.selector;
        selectors[8] = PLEAHandler.rejectZeroAddress.selector;
        selectors[9] = PLEAHandler.roundTrip.selector;
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
        assertEq(token.name(), "PLEA");
        assertEq(token.symbol(), "PLEA");
        assertEq(token.decimals(), 18);
        for (uint256 i; i < 4; ++i) {
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
        }
    }

    /// @dev Every holder must still be able to move their entire balance after any sequence,
    /// including after failed transfers, revoked approvals and self-transfers.
    function afterInvariant() public {
        for (uint256 i = 1; i < 4; ++i) {
            handler.transfer(i, 0, handler.expectedBalance(i));
            assertEq(token.balanceOf(handler.actors(i)), 0);
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
        invariant_FixedSupplyAndExactAccounting();
    }
}
