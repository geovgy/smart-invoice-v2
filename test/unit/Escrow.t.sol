// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Escrow} from "../../src/Escrow.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


contract EscrowTest is Test {
    Escrow public escrow;
    TestERC20 public token;

    address public arbitrator;

    function setUp() public {
        escrow = new Escrow(address(this), "Escrow", "ESCROW");
        token =  new TestERC20("TestERC20", "TEST", 0);
        arbitrator = vm.addr(uint256(keccak256("arbitrator")));
        escrow.setArbitrator(arbitrator, 0);
    }

    //
    // TO DO:
    // - test changeArbitrator
    // - test changePayer
    // - test withdrawPayments
    //

    function test_dispute() public {
        Escrow.Payment[] memory payments = new Escrow.Payment[](1);
        payments[0] = Escrow.Payment({
            amount: 1,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo1 = Escrow.EscrowInfo({
            payer: msg.sender,
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        escrow.createEscrow(vm.addr(1), escrowInfo1);

        vm.startPrank(vm.addr(uint256(keccak256("random"))));
        vm.expectRevert();
        escrow.dispute(0, bytes32(0));
        vm.stopPrank();

        vm.prank(msg.sender);
        escrow.dispute(0, bytes32(0));

        Escrow.EscrowInfo memory escrowInfo3 = escrow.getEscrow(0);
        assertEq(escrowInfo3.locked, true);
    }

    function test_resolve() public {
        escrow.setArbitrator(arbitrator, 600);
        escrow.setFee(400);
        Escrow.Payment[] memory payments = new Escrow.Payment[](1);
        payments[0] = Escrow.Payment({
            amount: 10000,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo1 = Escrow.EscrowInfo({
            payer: msg.sender,
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        escrow.createEscrow(vm.addr(1), escrowInfo1);
        
        token.mint(msg.sender, 10000);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 10000);
        escrow.depositPayment(0, 0);
        escrow.dispute(0, bytes32(0));

        uint256 payerAmount = (10000 - 600 - 400) / 3;
        uint256 payeeAmount = payerAmount * 2;
        
        vm.startPrank(vm.addr(uint256(keccak256("random"))));
        vm.expectRevert();
        escrow.resolve(0, payerAmount, payeeAmount, bytes32(0));
        vm.stopPrank();

        vm.prank(arbitrator);
        escrow.resolve(0, payerAmount, payeeAmount, bytes32(0));

        Escrow.EscrowInfo memory escrowInfo3 = escrow.getEscrow(0);
        assertEq(escrowInfo3.locked, false);
        assertEq(escrowInfo3.payments[0].paid, true);
        assertEq(token.balanceOf(address(vm.addr(1))), payeeAmount);
        assertEq(token.balanceOf(address(msg.sender)), payerAmount);
        assertEq(token.balanceOf(address(arbitrator)), 600);
        assertEq(token.balanceOf(address(escrow)), 400);
    }

    function test_getArbitrator() public {
        (bool valid, uint256 fee) = escrow.getArbitrator(arbitrator);
        assertTrue(valid);
        assertEq(fee, 0);

        (bool valid2, uint256 fee2) = escrow.getArbitrator(vm.addr(1));
        assertFalse(valid2);
        assertEq(fee2, 0);
    }

    function test_setArbitrator() public {
        escrow.setArbitrator(vm.addr(3), 100);
        (bool valid, uint256 fee) = escrow.getArbitrator(vm.addr(3));
        assertTrue(valid);
        assertEq(fee, 100);

        vm.startPrank(vm.addr(4));
        vm.expectRevert();
        escrow.setArbitrator(vm.addr(4), 200);
        vm.stopPrank();
        (bool valid2, uint256 fee2) = escrow.getArbitrator(vm.addr(4));
        assertFalse(valid2);
        assertEq(fee2, 0);
    }

    function test_removeArbitrator() public {
        escrow.setArbitrator(vm.addr(3), 100);
        (bool valid, uint256 fee) = escrow.getArbitrator(vm.addr(3));
        assertTrue(valid);
        assertEq(fee, 100);

        escrow.removeArbitrator(vm.addr(3));
        (bool valid2, uint256 fee2) = escrow.getArbitrator(vm.addr(3));
        assertFalse(valid2);
        assertEq(fee2, 0);
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
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        escrow.createEscrow(vm.addr(1), escrowInfo);
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
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        escrow.createEscrow(vm.addr(1), escrowInfo);
        Escrow.EscrowInfo memory escrowInfo2 = escrow.getEscrow(0);
        assertEq(escrowInfo2.payer, msg.sender);
        assertEq(escrow.ownerOf(0), vm.addr(1));
        assertEq(escrowInfo2.token, address(token));
        assertEq(escrowInfo2.payments[0].amount, 1);
        assertEq(escrowInfo2.payments[0].funded, false);
        assertEq(escrowInfo2.payments[0].unlocked, false);
        assertEq(escrowInfo2.payments[0].paid, false);
    }

    function test_totalSupply() public {
        Escrow.Payment[] memory payments = new Escrow.Payment[](1);
        payments[0] = Escrow.Payment({
            amount: 1,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo1 = Escrow.EscrowInfo({
            payer: msg.sender,
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });

        Escrow.EscrowInfo memory escrowInfo2 = Escrow.EscrowInfo({
            payer: msg.sender,
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });

        escrow.createEscrow(vm.addr(1), escrowInfo1);
        escrow.createEscrow(vm.addr(2), escrowInfo2);
        assertEq(escrow.totalSupply(), 2);
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
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, 1);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 1);
        escrow.createEscrow(vm.addr(1), escrowInfo);
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
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, 1);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 1);
        escrow.createEscrow(vm.addr(1), escrowInfo);
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

    function test_collectPayment() public {
        Escrow.Payment[] memory payments = new Escrow.Payment[](1);
        payments[0] = Escrow.Payment({
            amount: 1,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, 1);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 1);
        escrow.createEscrow(vm.addr(1), escrowInfo);
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
        escrow.collectPayment(0, 0);
        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        assertEq(escrowInfo4.payments[0].paid, true);
        assertEq(token.balanceOf(address(vm.addr(1))), 1);
    }

    function test_collectPayment_afterTransferToNewPayee() public {
        Escrow.Payment[] memory payments = new Escrow.Payment[](1);
        payments[0] = Escrow.Payment({
            amount: 1,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        
        vm.startPrank(msg.sender);
        token.mint(msg.sender, 1);
        token.approve(address(escrow), 1);
        escrow.createEscrow(vm.addr(1), escrowInfo);
        escrow.depositPayment(0, 0);
        escrow.unlockPayment(0, 0);
        vm.stopPrank();
        
        vm.startPrank(vm.addr(1));
        escrow.safeTransferFrom(vm.addr(1), vm.addr(2), 0);

        vm.expectRevert();
        escrow.collectPayment(0, 0);
        vm.stopPrank();

        vm.prank(vm.addr(2));
        escrow.collectPayment(0, 0);

        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        assertEq(escrowInfo4.payments[0].paid, true);
        assertEq(token.balanceOf(address(vm.addr(2))), 1);
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
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, 3);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 3);
        escrow.createEscrow(vm.addr(1), escrowInfo);
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
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, 3);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 3);
        escrow.createEscrow(vm.addr(1), escrowInfo);
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

    function test_collectPayments() public {
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
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, 3);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 3);
        escrow.createEscrow(vm.addr(1), escrowInfo);
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
        escrow.collectPayments(0, indices);
        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        assertEq(escrowInfo4.payments[0].paid, true);
        assertEq(escrowInfo4.payments[1].paid, true);
        assertEq(token.balanceOf(address(vm.addr(1))), 3);
    }

    function test_collectAll() public {
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
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, 3);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 3);
        escrow.createEscrow(vm.addr(1), escrowInfo);
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
        escrow.collectPayments(0);
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

    function test_collectPayment_withFee() public {
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
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, 10);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 10);
        escrow.createEscrow(vm.addr(1), escrowInfo);
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
        escrow.collectPayment(0, 0);
        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        assertEq(escrowInfo4.payments[0].paid, true);
        assertEq(token.balanceOf(address(vm.addr(1))), 9);
        assertEq(token.balanceOf(address(escrow)), 1);
    }

    function test_collectPayments_withFee() public {
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
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, 30);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 30);
        escrow.createEscrow(vm.addr(1), escrowInfo);
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
        escrow.collectPayments(0, indices);
        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        assertEq(escrowInfo4.payments[0].paid, true);
        assertEq(escrowInfo4.payments[1].paid, true);
        assertEq(token.balanceOf(address(vm.addr(1))), 27);
        assertEq(token.balanceOf(address(escrow)), 3);
    }

    function test_collectAll_withFee() public {
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
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, 30);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 30);
        escrow.createEscrow(vm.addr(1), escrowInfo);
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
        escrow.collectPayments(0);
        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        assertEq(escrowInfo4.payments[0].paid, false);
        assertEq(escrowInfo4.payments[1].paid, true);
        assertEq(token.balanceOf(vm.addr(1)), 18);
        assertEq(token.balanceOf(address(escrow)), 2 + 10);
    }

    function test_collectFee() public {
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
            token: address(token),
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, 30);
        
        vm.startPrank(msg.sender);
        token.approve(address(escrow), 30);
        escrow.createEscrow(vm.addr(1), escrowInfo);
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 1;
        escrow.depositPayments(0, indices);
        assertEq(token.balanceOf(address(escrow)), 30);
        escrow.unlockPayment(0, 1);
        vm.stopPrank();
        
        Escrow.EscrowInfo memory escrowInfo3 = escrow.getEscrow(0);
        assertEq(escrowInfo3.payments[0].unlocked, false);
        assertEq(escrowInfo3.payments[1].unlocked, true);

        vm.prank(vm.addr(1));
        escrow.collectPayments(0);

        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        assertEq(escrowInfo4.payments[0].paid, false);
        assertEq(escrowInfo4.payments[1].paid, true);
        assertEq(token.balanceOf(vm.addr(1)), 18);
        assertEq(token.balanceOf(address(escrow)), 2 + 10);

        escrow.collectFee(address(token));
        assertEq(token.balanceOf(address(escrow)), 10);
        assertEq(token.balanceOf(address(this)), 2);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}