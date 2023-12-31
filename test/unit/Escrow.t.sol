// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Escrow} from "../../src/Escrow.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


contract EscrowTest is Test {
    Escrow public escrow;
    TestERC20 public token;

    function setUp() public {
        escrow = new Escrow(address(this), "Escrow", "ESCROW");
        token =  new TestERC20("TestERC20", "TEST", 0);
    }

    function test_createEscrow() public {
        Escrow.Payment[] memory payments = new Escrow.Payment[](1);
        payments[0] = Escrow.Payment({
            amount: 1,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            payee: vm.addr(1),
            token: address(token),
            payments: payments
        });
        escrow.createEscrow(escrowInfo);
        assertEq(escrow.balanceOf(vm.addr(1)), 1);
    }

    function test_getEscrow() public {
        Escrow.Payment[] memory payments = new Escrow.Payment[](1);
        payments[0] = Escrow.Payment({
            amount: 1,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            payee: vm.addr(1),
            token: address(token),
            payments: payments
        });
        escrow.createEscrow(escrowInfo);
        Escrow.EscrowInfo memory escrowInfo2 = escrow.getEscrow(0);
        assertEq(escrowInfo2.payer, msg.sender);
        assertEq(escrowInfo2.payee, vm.addr(1));
        assertEq(escrowInfo2.token, address(token));
        assertEq(escrowInfo2.payments[0].amount, 1);
        assertEq(escrowInfo2.payments[0].funded, false);
        assertEq(escrowInfo2.payments[0].unlocked, false);
        assertEq(escrowInfo2.payments[0].paid, false);
    }

    function test_depositPayment() public {
        Escrow.Payment[] memory payments = new Escrow.Payment[](1);
        payments[0] = Escrow.Payment({
            amount: 1,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            payee: vm.addr(1),
            token: address(token),
            payments: payments
        });
        token.mint(msg.sender, 1);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 1);
        escrow.createEscrow(escrowInfo);
        escrow.depositPayment(0, 0);
        vm.stopPrank();
        assertEq(token.balanceOf(address(escrow)), 1);
        Escrow.EscrowInfo memory escrowInfo2 = escrow.getEscrow(0);
        assertEq(escrowInfo2.payments[0].funded, true);
    }

    function test_unlockPayment() public {
        Escrow.Payment[] memory payments = new Escrow.Payment[](1);
        payments[0] = Escrow.Payment({
            amount: 1,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            payee: vm.addr(1),
            token: address(token),
            payments: payments
        });
        token.mint(msg.sender, 1);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 1);
        escrow.createEscrow(escrowInfo);
        escrow.depositPayment(0, 0);
        vm.stopPrank();
        assertEq(token.balanceOf(address(escrow)), 1);
        Escrow.EscrowInfo memory escrowInfo2 = escrow.getEscrow(0);
        assertEq(escrowInfo2.payments[0].funded, true);
        vm.prank(msg.sender);
        escrow.unlockPayment(0, 0);
        Escrow.EscrowInfo memory escrowInfo3 = escrow.getEscrow(0);
        assertEq(escrowInfo3.payments[0].unlocked, true);
    }

    function test_withdrawPayment() public {
        Escrow.Payment[] memory payments = new Escrow.Payment[](1);
        payments[0] = Escrow.Payment({
            amount: 1,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            payee: vm.addr(1),
            token: address(token),
            payments: payments
        });
        token.mint(msg.sender, 1);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 1);
        escrow.createEscrow(escrowInfo);
        escrow.depositPayment(0, 0);
        vm.stopPrank();
        assertEq(token.balanceOf(address(escrow)), 1);
        Escrow.EscrowInfo memory escrowInfo2 = escrow.getEscrow(0);
        assertEq(escrowInfo2.payments[0].funded, true);
        vm.prank(msg.sender);
        escrow.unlockPayment(0, 0);
        Escrow.EscrowInfo memory escrowInfo3 = escrow.getEscrow(0);
        assertEq(escrowInfo3.payments[0].unlocked, true);
        vm.prank(vm.addr(1));
        escrow.withdrawPayment(0, 0);
        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        assertEq(escrowInfo4.payments[0].paid, true);
        assertEq(token.balanceOf(address(vm.addr(1))), 1);
    }

    function test_depositPayments() public {
        Escrow.Payment[] memory payments = new Escrow.Payment[](2);
        payments[0] = Escrow.Payment({
            amount: 1,
            funded: false,
            unlocked: false,
            paid: false
        });
        payments[1] = Escrow.Payment({
            amount: 2,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            payee: vm.addr(1),
            token: address(token),
            payments: payments
        });
        token.mint(msg.sender, 3);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 3);
        escrow.createEscrow(escrowInfo);
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 1;
        escrow.depositPayments(0, indices);
        vm.stopPrank();
        assertEq(token.balanceOf(address(escrow)), 3);
        Escrow.EscrowInfo memory escrowInfo2 = escrow.getEscrow(0);
        assertEq(escrowInfo2.payments[0].funded, true);
        assertEq(escrowInfo2.payments[1].funded, true);
    }

    function test_unlockPayments() public {
        Escrow.Payment[] memory payments = new Escrow.Payment[](2);
        payments[0] = Escrow.Payment({
            amount: 1,
            funded: false,
            unlocked: false,
            paid: false
        });
        payments[1] = Escrow.Payment({
            amount: 2,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            payee: vm.addr(1),
            token: address(token),
            payments: payments
        });
        token.mint(msg.sender, 3);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 3);
        escrow.createEscrow(escrowInfo);
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 1;
        escrow.depositPayments(0, indices);
        vm.stopPrank();
        assertEq(token.balanceOf(address(escrow)), 3);
        Escrow.EscrowInfo memory escrowInfo2 = escrow.getEscrow(0);
        assertEq(escrowInfo2.payments[0].funded, true);
        assertEq(escrowInfo2.payments[1].funded, true);
        vm.prank(msg.sender);
        escrow.unlockPayments(0, indices);
        Escrow.EscrowInfo memory escrowInfo3 = escrow.getEscrow(0);
        assertEq(escrowInfo3.payments[0].unlocked, true);
        assertEq(escrowInfo3.payments[1].unlocked, true);
    }

    function test_withdrawPayments() public {
        Escrow.Payment[] memory payments = new Escrow.Payment[](2);
        payments[0] = Escrow.Payment({
            amount: 1,
            funded: false,
            unlocked: false,
            paid: false
        });
        payments[1] = Escrow.Payment({
            amount: 2,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            payee: vm.addr(1),
            token: address(token),
            payments: payments
        });
        token.mint(msg.sender, 3);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 3);
        escrow.createEscrow(escrowInfo);
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 1;
        escrow.depositPayments(0, indices);
        vm.stopPrank();
        assertEq(token.balanceOf(address(escrow)), 3);
        Escrow.EscrowInfo memory escrowInfo2 = escrow.getEscrow(0);
        assertEq(escrowInfo2.payments[0].funded, true);
        assertEq(escrowInfo2.payments[1].funded, true);
        vm.prank(msg.sender);
        escrow.unlockPayments(0, indices);
        Escrow.EscrowInfo memory escrowInfo3 = escrow.getEscrow(0);
        assertEq(escrowInfo3.payments[0].unlocked, true);
        assertEq(escrowInfo3.payments[1].unlocked, true);
        vm.prank(vm.addr(1));
        escrow.withdrawPayments(0, indices);
        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        assertEq(escrowInfo4.payments[0].paid, true);
        assertEq(escrowInfo4.payments[1].paid, true);
        assertEq(token.balanceOf(address(vm.addr(1))), 3);
    }

    function test_withdrawAll() public {
        Escrow.Payment[] memory payments = new Escrow.Payment[](2);
        payments[0] = Escrow.Payment({
            amount: 1,
            funded: false,
            unlocked: false,
            paid: false
        });
        payments[1] = Escrow.Payment({
            amount: 2,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            payee: vm.addr(1),
            token: address(token),
            payments: payments
        });
        token.mint(msg.sender, 3);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 3);
        escrow.createEscrow(escrowInfo);
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 1;
        escrow.depositPayments(0, indices);
        vm.stopPrank();
        assertEq(token.balanceOf(address(escrow)), 3);
        Escrow.EscrowInfo memory escrowInfo2 = escrow.getEscrow(0);
        assertEq(escrowInfo2.payments[0].funded, true);
        assertEq(escrowInfo2.payments[1].funded, true);
        vm.prank(msg.sender);
        escrow.unlockPayment(0, 1);
        Escrow.EscrowInfo memory escrowInfo3 = escrow.getEscrow(0);
        assertEq(escrowInfo3.payments[0].unlocked, false);
        assertEq(escrowInfo3.payments[1].unlocked, true);
        vm.prank(vm.addr(1));
        escrow.withdrawAll(0);
        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        assertEq(escrowInfo4.payments[0].paid, false);
        assertEq(escrowInfo4.payments[1].paid, true);
        assertEq(token.balanceOf(vm.addr(1)), 2);
    }

    function test_setFee() public {
        escrow.setFee(1000);
        assertEq(escrow.getFee(2 * 10), 2);

        vm.startPrank(vm.addr(3));
        vm.expectRevert();
        escrow.setFee(10001);
        vm.stopPrank();
    }

    function test_withdrawPayment_withFee() public {
        escrow.setFee(1000);
        Escrow.Payment[] memory payments = new Escrow.Payment[](1);
        payments[0] = Escrow.Payment({
            amount: 10,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            payee: vm.addr(1),
            token: address(token),
            payments: payments
        });
        token.mint(msg.sender, 10);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 10);
        escrow.createEscrow(escrowInfo);
        escrow.depositPayment(0, 0);
        vm.stopPrank();
        assertEq(token.balanceOf(address(escrow)), 10);
        Escrow.EscrowInfo memory escrowInfo2 = escrow.getEscrow(0);
        assertEq(escrowInfo2.payments[0].funded, true);
        vm.prank(msg.sender);
        escrow.unlockPayment(0, 0);
        Escrow.EscrowInfo memory escrowInfo3 = escrow.getEscrow(0);
        assertEq(escrowInfo3.payments[0].unlocked, true);
        vm.prank(vm.addr(1));
        escrow.withdrawPayment(0, 0);
        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        assertEq(escrowInfo4.payments[0].paid, true);
        assertEq(token.balanceOf(address(vm.addr(1))), 9);
        assertEq(token.balanceOf(address(escrow)), 1);
    }

    function test_withdrawPayments_withFee() public {
        escrow.setFee(1000);
        Escrow.Payment[] memory payments = new Escrow.Payment[](2);
        payments[0] = Escrow.Payment({
            amount: 10,
            funded: false,
            unlocked: false,
            paid: false
        });
        payments[1] = Escrow.Payment({
            amount: 20,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            payee: vm.addr(1),
            token: address(token),
            payments: payments
        });
        token.mint(msg.sender, 30);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 30);
        escrow.createEscrow(escrowInfo);
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 1;
        escrow.depositPayments(0, indices);
        vm.stopPrank();
        assertEq(token.balanceOf(address(escrow)), 30);
        Escrow.EscrowInfo memory escrowInfo2 = escrow.getEscrow(0);
        assertEq(escrowInfo2.payments[0].funded, true);
        assertEq(escrowInfo2.payments[1].funded, true);
        vm.prank(msg.sender);
        escrow.unlockPayments(0, indices);
        Escrow.EscrowInfo memory escrowInfo3 = escrow.getEscrow(0);
        assertEq(escrowInfo3.payments[0].unlocked, true);
        assertEq(escrowInfo3.payments[1].unlocked, true);
        vm.prank(vm.addr(1));
        escrow.withdrawPayments(0, indices);
        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        assertEq(escrowInfo4.payments[0].paid, true);
        assertEq(escrowInfo4.payments[1].paid, true);
        assertEq(token.balanceOf(address(vm.addr(1))), 27);
        assertEq(token.balanceOf(address(escrow)), 3);
    }

    function test_withdrawAll_withFee() public {
        escrow.setFee(1000);
        Escrow.Payment[] memory payments = new Escrow.Payment[](2);
        payments[0] = Escrow.Payment({
            amount: 10,
            funded: false,
            unlocked: false,
            paid: false
        });
        payments[1] = Escrow.Payment({
            amount: 20,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            payee: vm.addr(1),
            token: address(token),
            payments: payments
        });
        token.mint(msg.sender, 30);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 30);
        escrow.createEscrow(escrowInfo);
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 1;
        escrow.depositPayments(0, indices);
        vm.stopPrank();
        assertEq(token.balanceOf(address(escrow)), 30);
        Escrow.EscrowInfo memory escrowInfo2 = escrow.getEscrow(0);
        assertEq(escrowInfo2.payments[0].funded, true);
        assertEq(escrowInfo2.payments[1].funded, true);
        vm.prank(msg.sender);
        escrow.unlockPayment(0, 1);
        Escrow.EscrowInfo memory escrowInfo3 = escrow.getEscrow(0);
        assertEq(escrowInfo3.payments[0].unlocked, false);
        assertEq(escrowInfo3.payments[1].unlocked, true);
        vm.prank(vm.addr(1));
        escrow.withdrawAll(0);
        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        assertEq(escrowInfo4.payments[0].paid, false);
        assertEq(escrowInfo4.payments[1].paid, true);
        assertEq(token.balanceOf(vm.addr(1)), 18);
        assertEq(token.balanceOf(address(escrow)), 2 + 10);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}