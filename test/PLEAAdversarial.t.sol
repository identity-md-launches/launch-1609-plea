// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PLEA} from "src/PLEA.sol";

/// @dev A local holder fixture. ERC-20 transfers must not depend on a receiver callback.
contract PLEAContractHolder {
    fallback() external {
        revert("unexpected callback");
    }

    function forward(PLEA token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

/// @dev Extends the original suite with allowance lifecycle, aliasing and rollback properties.
/// forge-config: default.fuzz.runs = 1000
contract PLEAAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    PLEA private token;
    address private alice;
    address private bob;
    address private spender;
    address private otherSpender;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new PLEA();
        alice = makeAddr("adversarial alice");
        bob = makeAddr("adversarial bob");
        spender = makeAddr("adversarial spender");
        otherSpender = makeAddr("adversarial other spender");
    }

    function test_OneMinorUnitAllowanceCannotBeReusedAfterBalanceIsReplenished() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);

        vm.prank(bob);
        assertTrue(token.transfer(alice, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferAmountRevertsWithoutOverflowOrAllowanceLoss() public {
        uint256 maximum = type(uint256).max;
        bytes memory error =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum);
        vm.expectRevert(error);
        token.transfer(alice, maximum);

        assertTrue(token.approve(spender, maximum));
        vm.expectRevert(error);
        vm.prank(spender);
        token.transferFrom(address(this), alice, maximum);
        assertEq(token.allowance(address(this), spender), maximum);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_LargestFiniteAllowanceIsConsumed() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(bob), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteAllowanceCanBeReducedAndRevokedAfterSpending() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 2, 3));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 3);
        assertEq(token.allowance(address(this), spender), 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), 1);

        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_ApprovalIsScopedToBothOwnerAndSpender() public {
        assertTrue(token.transfer(alice, 100));
        assertTrue(token.transfer(bob, 100));
        vm.prank(alice);
        assertTrue(token.approve(spender, 20));
        vm.prank(bob);
        assertTrue(token.approve(otherSpender, 40));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, otherSpender, 0, 1));
        vm.prank(otherSpender);
        token.transferFrom(alice, otherSpender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(bob, spender, 1);

        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 100);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.allowance(alice, spender), 20);
        assertEq(token.allowance(bob, otherSpender), 40);
        assertEq(token.allowance(alice, otherSpender), 0);
        assertEq(token.allowance(bob, spender), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, 20));
        vm.prank(otherSpender);
        assertTrue(token.transferFrom(bob, otherSpender, 40));
        assertEq(token.balanceOf(alice), 80);
        assertEq(token.balanceOf(bob), 60);
        assertEq(token.balanceOf(spender), 20);
        assertEq(token.balanceOf(otherSpender), 40);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(bob, otherSpender), 0);
    }

    function test_ZeroSenderGuardsCannotReachMintOrApprovalLogic() public {
        // Synthetic boundary caller used only to exercise the public zero-address guards.
        // No storage writes or harness exposing the token's internal mint function are used.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender, type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(0), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroApprovalStillRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroDelegatedTransferToZeroRevertsForFiniteAndInfiniteAllowances() public {
        uint256[3] memory approvals = [uint256(0), 1, type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            assertTrue(token.approve(spender, approvals[i]));
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(address(this), address(0), 0);
            assertEq(token.allowance(address(this), spender), approvals[i]);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(address(0)), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_DelegatedSelfTransferCannotBypassBalanceCheck() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, alice, 1);
        assertTrue(token.transfer(alice, 7));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 7, 8));
        vm.prank(spender);
        token.transferFrom(alice, alice, 8);
        assertEq(token.balanceOf(alice), 7);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_BurnFromIsUnavailableEvenToAnApprovedSpender() public {
        assertTrue(token.transfer(alice, 100));
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        (bool success,) = address(token).call(abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1));
        assertFalse(success);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 100));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 100);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_NonpayableMutationsRejectEtherWithoutChangingState() public {
        assertTrue(token.approve(spender, 10));
        assertTrue(token.approve(address(this), 1));
        vm.deal(address(this), 3);
        bytes[3] memory calls = [
            abi.encodeWithSelector(token.transfer.selector, alice, 1),
            abi.encodeWithSelector(token.approve.selector, spender, 0),
            abi.encodeWithSelector(token.transferFrom.selector, address(this), bob, 1)
        ];
        for (uint256 i; i < calls.length; ++i) {
            // Each call would otherwise be valid, so a different failure cannot mask payability.
            (bool success,) = address(token).call{value: 1}(calls[i]);
            assertFalse(success);
            assertEq(address(token).balance, 0);
            assertEq(address(this).balance, 3);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(bob), 0);
            assertEq(token.allowance(address(this), spender), 10);
            assertEq(token.allowance(address(this), address(this)), 1);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_ContractHolderCanReceiveAndForwardWithoutCallbacks() public {
        PLEAContractHolder holder = new PLEAContractHolder();
        assertTrue(token.transfer(address(holder), SUPPLY));
        assertEq(token.balanceOf(address(holder)), SUPPLY);
        assertTrue(holder.forward(token, bob, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(holder)), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementOnlyChangesChosenPair(uint256 first, uint256 replacement) public {
        vm.startPrank(alice);
        assertTrue(token.approve(spender, first));
        assertTrue(token.approve(otherSpender, 17));
        vm.stopPrank();
        vm.prank(bob);
        assertTrue(token.approve(spender, 31));

        for (uint256 i; i < 2; ++i) {
            vm.expectEmit(true, true, false, true, address(token));
            emit Approval(alice, spender, replacement);
            vm.prank(alice);
            assertTrue(token.approve(spender, replacement));
            assertEq(token.allowance(alice, spender), replacement);
            assertEq(token.allowance(alice, otherSpender), 17);
            assertEq(token.allowance(bob, spender), 31);
            assertEq(token.allowance(spender, alice), 0);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(bob), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function testFuzz_FailedSpendCanBeRetriedAfterFunding(uint256 balance, uint256 amount, bool infinite) public {
        amount = bound(amount, 1, SUPPLY);
        balance = bound(balance, 0, amount - 1);
        assertTrue(token.transfer(alice, balance));
        uint256 approved = infinite ? type(uint256).max : amount;
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);

        assertTrue(token.transfer(alice, amount - balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), infinite ? approved : 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DirectRoundTripPreservesBalancesAndApproval(uint256 balance, uint256 amount, uint256 approval)
        public
    {
        balance = bound(balance, 1, SUPPLY);
        amount = bound(amount, 1, balance);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approval));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), balance - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.allowance(alice, spender), approval);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedTransferSupportsAliasedRoles(uint256 amount, uint8 roles, bool infinite) public {
        amount = bound(amount, 0, SUPPLY);
        roles %= 4;
        // owner == spender; owner == recipient; spender == recipient; or all three equal.
        address caller = roles == 0 || roles == 3 ? alice : spender;
        address recipient = roles == 1 || roles == 3 ? alice : roles == 2 ? spender : bob;
        assertTrue(token.transfer(alice, SUPPLY));
        uint256 approved = infinite ? type(uint256).max : amount;
        vm.prank(alice);
        assertTrue(token.approve(caller, approved));
        vm.prank(caller);
        assertTrue(token.transferFrom(alice, recipient, amount));
        assertEq(token.balanceOf(alice), recipient == alice ? SUPPLY : SUPPLY - amount);
        if (recipient != alice) assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(alice, caller), infinite ? approved : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitAndSingleDelegatedTransfersAgree(uint256 amount, uint256 first) public {
        amount = bound(amount, 1, SUPPLY);
        first = bound(first, 0, amount);
        PLEA splitToken = new PLEA();
        assertTrue(token.approve(spender, amount));
        assertTrue(splitToken.approve(spender, amount));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), bob, amount));
        assertTrue(splitToken.transferFrom(address(this), bob, first));
        assertTrue(splitToken.transferFrom(address(this), bob, amount - first));
        vm.stopPrank();
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(splitToken.balanceOf(bob), token.balanceOf(bob));
        assertEq(splitToken.balanceOf(address(this)), token.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(splitToken.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(splitToken.totalSupply(), SUPPLY);
    }
}
