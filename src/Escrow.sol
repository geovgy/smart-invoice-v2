// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


contract Escrow is ERC721, Ownable, ReentrancyGuard {
    struct Payment {
        uint256 amount;
        bool funded;
        bool unlocked;
        bool paid;
    }

    struct EscrowInfo {
        address payer;
        address payee;
        address token;
        Payment[] payments;
    }

    uint256 internal _counter;
    mapping(uint256 tokenId => EscrowInfo escrow) public escrows;


    constructor(
        address owner,
        string memory name, 
        string memory symbol
    ) ERC721(name, symbol) Ownable(owner) {}


    function createEscrow(
        EscrowInfo calldata escrow
    ) external nonReentrant {
        require(escrow.payee != address(0), "Escrow: payee is the zero address");
        require(escrow.token != address(0), "Escrow: token is the zero address");
        for (uint256 i = 0; i < escrow.payments.length; i++) {
            require(escrow.payments[i].amount > 0, "Escrow: amount is zero");
            require(!escrow.payments[i].funded, "Escrow: payment already funded");
            require(!escrow.payments[i].unlocked, "Escrow: payment already unlocked");
            require(!escrow.payments[i].paid, "Escrow: payment already paid");
        }

        uint256 tokenId = _counter;
        escrows[tokenId] = escrow;

        _increment();
        _safeMint(msg.sender, tokenId);
    }

    function depositPayment(uint256 tokenId, uint256 index) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(index < escrows[tokenId].payments.length, "Escrow: index out of bounds");
        require(!escrows[tokenId].payments[index].unlocked, "Escrow: payment already unlocked");
        require(!escrows[tokenId].payments[index].funded, "Escrow: payment already funded");

        IERC20(escrows[tokenId].token).transferFrom(msg.sender, address(this), escrows[tokenId].payments[index].amount);
        escrows[tokenId].payments[index].funded = true;
    }

    function depositPayments(uint256 tokenId, uint256[] calldata indices) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(indices.length > 0, "Escrow: indices is empty");

        uint256 amount;
        for (uint256 i = 0; i < indices.length; i++) {
            require(indices[i] < escrows[tokenId].payments.length, "Escrow: index out of bounds");
            require(!escrows[tokenId].payments[indices[i]].unlocked, "Escrow: payment already unlocked");
            require(!escrows[tokenId].payments[indices[i]].funded, "Escrow: payment already funded");
            amount += escrows[tokenId].payments[indices[i]].amount;
        }
        
        IERC20(escrows[tokenId].token).transferFrom(msg.sender, address(this), amount);

        for (uint256 i = 0; i < indices.length; i++) {
            escrows[tokenId].payments[indices[i]].funded = true;
        }
    }

    function unlockPayment(uint256 tokenId, uint256 index) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(index < escrows[tokenId].payments.length, "Escrow: index out of bounds");
        require(escrows[tokenId].payer == msg.sender, "Escrow: caller is not the payer");
        require(escrows[tokenId].payments[index].funded, "Escrow: payment not funded");
        require(!escrows[tokenId].payments[index].unlocked, "Escrow: payment already unlocked");

        escrows[tokenId].payments[index].unlocked = true;
    }

    function withdrawPayment(uint256 tokenId, uint256 index) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(index < escrows[tokenId].payments.length, "Escrow: index out of bounds");
        require(escrows[tokenId].payee == msg.sender, "Escrow: caller is not the payee");
        require(escrows[tokenId].payments[index].funded, "Escrow: payment not funded");
        require(escrows[tokenId].payments[index].unlocked, "Escrow: payment not unlocked");
        require(!escrows[tokenId].payments[index].paid, "Escrow: payment already paid");

        escrows[tokenId].payments[index].paid = true;
        IERC20(escrows[tokenId].token).transfer(escrows[tokenId].payee, escrows[tokenId].payments[index].amount);
    }

    function withdrawPayments(uint256 tokenId, uint256[] calldata indices) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(indices.length > 0, "Escrow: indices is empty");
        require(escrows[tokenId].payee == msg.sender, "Escrow: caller is not the payee");

        uint256 amount;
        for (uint256 i = 0; i < indices.length; i++) {
            require(indices[i] < escrows[tokenId].payments.length, "Escrow: index out of bounds");
            require(escrows[tokenId].payments[indices[i]].funded, "Escrow: payment not funded");
            require(escrows[tokenId].payments[indices[i]].unlocked, "Escrow: payment not unlocked");
            require(!escrows[tokenId].payments[indices[i]].paid, "Escrow: payment already paid");
            amount += escrows[tokenId].payments[indices[i]].amount;
        }

        for (uint256 i = 0; i < indices.length; i++) {
            escrows[tokenId].payments[indices[i]].paid = true;
        }

        IERC20(escrows[tokenId].token).transfer(escrows[tokenId].payee, amount);
    }

    function withdrawAll(uint256 tokenId) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(escrows[tokenId].payee == msg.sender, "Escrow: caller is not the payee");

        uint256 amount;
        uint256[] memory indices;
        for (uint256 i = 0; i < escrows[tokenId].payments.length; i++) {
            bool funded = escrows[tokenId].payments[i].funded;
            bool unlocked = escrows[tokenId].payments[i].unlocked;
            bool paid = escrows[tokenId].payments[i].paid;
            if (funded && unlocked && !paid) {
                amount += escrows[tokenId].payments[i].amount;
                indices[indices.length] = i;
            }
        }
        
        for (uint256 i = 0; i < indices.length; i++) {
            bool funded = escrows[tokenId].payments[indices[i]].funded;
            bool unlocked = escrows[tokenId].payments[indices[i]].unlocked;
            bool paid = escrows[tokenId].payments[indices[i]].paid;
            if (funded && unlocked && !paid) {
                escrows[tokenId].payments[indices[i]].paid = true;
            }
        }

        IERC20(escrows[tokenId].token).transfer(escrows[tokenId].payee, amount);
    }

    function _increment() internal {
        unchecked {
            _counter++;
        }
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return tokenId < _counter && _ownerOf(tokenId) != address(0);
    }
}