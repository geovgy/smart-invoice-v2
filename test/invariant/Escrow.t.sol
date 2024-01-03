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

    address public arbitrator;

    function setUp() public {
        escrow = new Escrow(address(this), "Escrow", "ESCROW");
        token =  new TestERC20("TestERC20", "TEST", 0);
        arbitrator = vm.addr(uint256(keccak256("arbitrator")));
        escrow.setArbitrator(arbitrator, 0);
    }

    // NEEDS TO BE FIXED
    function invariant_balances() public {
        uint256 escrowBalance = token.balanceOf(address(escrow));
        uint256 ownerBalance = token.balanceOf(address(this));
        uint256 totalDeposits;
        uint256 totalPayerBalance;
        uint256 totalPayeeBalance;
        uint256 totalArbitratorBalance;

        Escrow.EscrowInfo memory escrowInfo;
        for(uint256 i; i < escrow.totalSupply(); i++) {
            escrowInfo = escrow.getEscrow(i);
            for(uint256 j; j < escrowInfo.payments.length; j++) {
                if(escrowInfo.payments[j].funded) {
                    totalDeposits += escrowInfo.payments[j].amount;
                }
                if(escrowInfo.payments[j].paid) {
                    totalArbitratorBalance += token.balanceOf(escrowInfo.arbitrator);
                    totalPayeeBalance += token.balanceOf(escrow.payeeOf(i));
                    totalPayerBalance += token.balanceOf(escrow.payerOf(i));
                }
            }
        }
        
        assertEq(totalDeposits, escrowBalance + ownerBalance + totalPayeeBalance + totalPayerBalance + totalArbitratorBalance);
    }

    function invariant_supply() public {
        assertEq(escrow.totalSupply(), escrow.totalEscrows() * 2);
    }
}