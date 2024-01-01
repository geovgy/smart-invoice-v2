// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Escrow} from "../../src/Escrow.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


contract FuzzEscrowTest is Test {
    uint256 private constant _MAX_BASIS_POINTS = 10000;
    uint256 private constant _MAX_AMOUNT = (2**256 - 1) / _MAX_BASIS_POINTS;
    
    Escrow public escrow;
    TestERC20 public token;

    address public arbitrator;

    function setUp() public {
        escrow = new Escrow(address(this), "Escrow", "ESCROW");
        token =  new TestERC20("TestERC20", "TEST", 0);
        arbitrator = vm.addr(uint256(keccak256("arbitrator")));
        escrow.setArbitrator(arbitrator, 0);
    }

    function testFuzz_depositPayment(uint256 amount) public {
        vm.assume(amount > 0 && amount < _MAX_AMOUNT);
        Escrow.Payment[] memory payments = new Escrow.Payment[](1);
        payments[0] = Escrow.Payment({
            amount: amount,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            token: address(token),
            details: "",
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, amount);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), amount);
        escrow.createEscrow(vm.addr(1), escrowInfo);
        escrow.depositPayment(0, 0);
        vm.stopPrank();
        assertEq(token.balanceOf(address(escrow)), amount);
        Escrow.EscrowInfo memory escrowInfo2 = escrow.getEscrow(0);
        assertEq(escrowInfo2.payments[0].funded, true);
    }

    function testFuzz_depositPayments(uint8 index1, uint8 index2) public {
        vm.assume(index1 != index2);
        uint256 length = index1 > index2 ? index1 : index2;
        uint256[] memory indices = new uint256[](2);
        uint256[] memory amounts = new uint256[](length + 1);

        uint256 total;
        for(uint256 i; i < amounts.length; i++) {
            amounts[i] = 1;
            total += 1;
        }
        Escrow.Payment[] memory payments = new Escrow.Payment[](amounts.length);
        for(uint256 i; i < amounts.length; i++) {
            payments[i] = Escrow.Payment({
                amount: amounts[i],
                funded: false,
                unlocked: false,
                paid: false
            });
        }
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            token: address(token),
            details: "",
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, total);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), total);
        escrow.createEscrow(vm.addr(1), escrowInfo);
        escrow.depositPayments(0, indices);
        vm.stopPrank();
        Escrow.EscrowInfo memory escrowInfo2 = escrow.getEscrow(0);
        uint totalDeposit;
        for(uint256 i; i < indices.length; i++) {
            assertEq(escrowInfo2.payments[indices[i]].funded, true);
            totalDeposit += amounts[indices[i]];
        }
        assertEq(token.balanceOf(address(escrow)), totalDeposit);
    }

    function testFuzz_withdrawPayments(uint8 index1, uint8 index2) public {
        vm.assume(index1 != index2);
        uint256 length = index1 > index2 ? index1 : index2;
        uint256[] memory indices = new uint256[](2);
        uint256[] memory amounts = new uint256[](length + 1);

        uint256 total;
        for(uint256 i; i < amounts.length; i++) {
            amounts[i] = 1;
            total += 1;
        }
        Escrow.Payment[] memory payments = new Escrow.Payment[](amounts.length);
        for(uint256 i; i < amounts.length; i++) {
            payments[i] = Escrow.Payment({
                amount: amounts[i],
                funded: false,
                unlocked: false,
                paid: false
            });
        }
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            token: address(token),
            details: "",
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, total);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), total);
        escrow.createEscrow(vm.addr(1), escrowInfo);
        escrow.depositPayments(0, indices);
        escrow.unlockPayments(0, indices);
        vm.stopPrank();
        vm.prank(vm.addr(1));
        escrow.collectPayments(0, indices);
        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        uint totalDeposit;
        for(uint256 i; i < indices.length; i++) {
            assertEq(escrowInfo4.payments[indices[i]].funded, true);
            assertEq(escrowInfo4.payments[indices[i]].unlocked, true);
            assertEq(escrowInfo4.payments[indices[i]].paid, true);
            totalDeposit += amounts[indices[i]];
        }
        assertEq(token.balanceOf(vm.addr(1)), totalDeposit);
    }

    function testFuzz_withdrawAll(uint128[] calldata amounts) public {
        vm.assume(amounts.length > 0);
        for(uint256 i; i < amounts.length; i++) {
            vm.assume(amounts[i] > 0 && amounts[i] < _MAX_AMOUNT);
        }
        
        Escrow.Payment[] memory payments = new Escrow.Payment[](amounts.length);
        uint256 total;
        for(uint256 i; i < amounts.length; i++) {
            payments[i] = Escrow.Payment({
                amount: amounts[i],
                funded: false,
                unlocked: false,
                paid: false
            });
            total += amounts[i];
        }
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            token: address(token),
            details: "",
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, total);
        vm.startPrank(msg.sender);
        token.approve(address(escrow), total);
        escrow.createEscrow(vm.addr(1), escrowInfo);
        uint256[] memory indices = new uint256[](amounts.length);
        for(uint256 i; i < indices.length; i++) {
            indices[i] = i;
        }
        escrow.depositPayments(0, indices);
        assertEq(token.balanceOf(address(escrow)), total);
        escrow.unlockPayments(0, indices);
        vm.stopPrank();

        vm.prank(vm.addr(1));
        escrow.collectPayments(0);
        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        for(uint256 i; i < indices.length; i++) {
            assertEq(escrowInfo4.payments[indices[i]].funded, true);
            assertEq(escrowInfo4.payments[indices[i]].unlocked, true);
            assertEq(escrowInfo4.payments[indices[i]].paid, true);
        }
        assertEq(token.balanceOf(vm.addr(1)), total);
    }

    function testFuzz_withdrawPayment_withFee(uint256 amount, uint8 feeBasisPts) public {
        vm.assume(amount > 0 && amount < _MAX_AMOUNT);

        escrow.setFee(feeBasisPts);
        Escrow.Payment[] memory payments = new Escrow.Payment[](1);
        payments[0] = Escrow.Payment({
            amount: amount,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            token: address(token),
            details: "",
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, amount);
        
        vm.startPrank(msg.sender);
        token.approve(address(escrow), amount);
        escrow.createEscrow(vm.addr(1), escrowInfo);
        escrow.depositPayment(0, 0);
        escrow.unlockPayment(0, 0);
        vm.stopPrank();

        vm.prank(vm.addr(1));
        escrow.collectPayment(0, 0);
        
        uint256 feeAmount = escrow.getFee(amount);
        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        assertEq(escrowInfo4.payments[0].paid, true);
        assertEq(token.balanceOf(address(vm.addr(1))), amount - feeAmount);
        assertEq(token.balanceOf(address(escrow)), feeAmount);
    }

    function testFuzz_collectFee(uint256 amount, uint8 feeBasisPts) public {
        vm.assume(amount > 10000 && amount < _MAX_AMOUNT);
        vm.assume(feeBasisPts > 0 && feeBasisPts < _MAX_BASIS_POINTS);

        escrow.setFee(feeBasisPts);
        Escrow.Payment[] memory payments = new Escrow.Payment[](1);
        payments[0] = Escrow.Payment({
            amount: amount,
            funded: false,
            unlocked: false,
            paid: false
        });
        Escrow.EscrowInfo memory escrowInfo = Escrow.EscrowInfo({
            payer: msg.sender,
            token: address(token),
            details: "",
            payments: payments,
            arbitrator: arbitrator,
            deadline: block.timestamp + 3600,
            locked: false
        });
        token.mint(msg.sender, amount);
        
        vm.startPrank(msg.sender);
        token.approve(address(escrow), amount);
        escrow.createEscrow(vm.addr(1), escrowInfo);
        escrow.depositPayment(0, 0);
        escrow.unlockPayment(0, 0);
        vm.stopPrank();

        vm.prank(vm.addr(1));
        escrow.collectPayment(0, 0);
        
        uint256 feeAmount = escrow.getFee(amount);
        Escrow.EscrowInfo memory escrowInfo4 = escrow.getEscrow(0);
        assertEq(escrowInfo4.payments[0].paid, true);
        assertEq(token.balanceOf(address(vm.addr(1))), amount - feeAmount);
        assertEq(token.balanceOf(address(escrow)), feeAmount);

        escrow.collectFee(address(token));
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(token.balanceOf(address(this)), feeAmount);
    }
}