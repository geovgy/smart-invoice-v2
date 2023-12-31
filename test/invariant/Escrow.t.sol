// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {Escrow} from "../../src/Escrow.sol";
import {TestERC20} from "../utils/TestERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


contract InvariantEscrowTest is Test {
    uint256 private constant _MAX_BASIS_POINTS = 10000;
    uint256 private constant _MAX_AMOUNT = (2**256 - 1) / _MAX_BASIS_POINTS;
    
    Escrow public escrow;
    TestERC20 public token;

    function setUp() public {
        escrow = new Escrow(address(this), "Escrow", "ESCROW");
        token =  new TestERC20("TestERC20", "TEST", 0);
    }

    function invariant_balances() public {
        uint256 escrowBalance = token.balanceOf(address(escrow));
        uint256 ownerBalance = token.balanceOf(address(this));
        uint256 totalDeposits;
        uint256 totalPayeeBalance;
        uint256 totalFeeBalance;

        Escrow.EscrowInfo memory escrowInfo;
        for(uint256 i; i < escrow.totalSupply(); i++) {
            escrowInfo = escrow.getEscrow(i);
            for(uint256 j; j < escrowInfo.payments.length; j++) {
                if(escrowInfo.payments[j].funded) {
                    totalDeposits += escrowInfo.payments[j].amount;
                }
                if(escrowInfo.payments[j].paid) {
                    totalFeeBalance += escrow.getFee(escrowInfo.payments[j].amount);
                    totalPayeeBalance += token.balanceOf(escrowInfo.payee);
                }
            }
        }
        
        assertEq(totalFeeBalance, ownerBalance);
        assertEq(totalDeposits, escrowBalance + totalPayeeBalance + totalFeeBalance);
    }
}