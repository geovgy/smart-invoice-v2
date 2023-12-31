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
    mapping(uint256 tokenId => EscrowInfo escrow) internal _escrows;


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
        _escrows[tokenId] = escrow;

        _increment();
        _safeMint(escrow.payee, tokenId);
    }

    function depositPayment(uint256 tokenId, uint256 index) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(index < _escrows[tokenId].payments.length, "Escrow: index out of bounds");
        require(!_escrows[tokenId].payments[index].unlocked, "Escrow: payment already unlocked");
        require(!_escrows[tokenId].payments[index].funded, "Escrow: payment already funded");

        IERC20(_escrows[tokenId].token).transferFrom(msg.sender, address(this), _escrows[tokenId].payments[index].amount);
        _escrows[tokenId].payments[index].funded = true;
    }

    function depositPayments(uint256 tokenId, uint256[] calldata indices) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(indices.length > 0, "Escrow: indices is empty");

        uint256 amount;
        for (uint256 i = 0; i < indices.length; i++) {
            require(indices[i] < _escrows[tokenId].payments.length, "Escrow: index out of bounds");
            require(!_escrows[tokenId].payments[indices[i]].unlocked, "Escrow: payment already unlocked");
            require(!_escrows[tokenId].payments[indices[i]].funded, "Escrow: payment already funded");
            amount += _escrows[tokenId].payments[indices[i]].amount;
        }
        
        IERC20(_escrows[tokenId].token).transferFrom(msg.sender, address(this), amount);

        for (uint256 i = 0; i < indices.length; i++) {
            _escrows[tokenId].payments[indices[i]].funded = true;
        }
    }

    function unlockPayment(uint256 tokenId, uint256 index) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(index < _escrows[tokenId].payments.length, "Escrow: index out of bounds");
        require(_escrows[tokenId].payer == msg.sender, "Escrow: caller is not the payer");
        require(_escrows[tokenId].payments[index].funded, "Escrow: payment not funded");
        require(!_escrows[tokenId].payments[index].unlocked, "Escrow: payment already unlocked");

        _escrows[tokenId].payments[index].unlocked = true;
    }

    function unlockPayments(uint256 tokenId, uint256[] calldata indices) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(indices.length > 0, "Escrow: indices is empty");
        require(_escrows[tokenId].payer == msg.sender, "Escrow: caller is not the payer");

        for (uint256 i = 0; i < indices.length; i++) {
            require(indices[i] < _escrows[tokenId].payments.length, "Escrow: index out of bounds");
            require(_escrows[tokenId].payments[indices[i]].funded, "Escrow: payment not funded");
            require(!_escrows[tokenId].payments[indices[i]].unlocked, "Escrow: payment already unlocked");
        }

        for (uint256 i = 0; i < indices.length; i++) {
            _escrows[tokenId].payments[indices[i]].unlocked = true;
        }
    }

    function withdrawPayment(uint256 tokenId, uint256 index) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(index < _escrows[tokenId].payments.length, "Escrow: index out of bounds");
        require(_escrows[tokenId].payee == msg.sender, "Escrow: caller is not the payee");
        require(_escrows[tokenId].payments[index].funded, "Escrow: payment not funded");
        require(_escrows[tokenId].payments[index].unlocked, "Escrow: payment not unlocked");
        require(!_escrows[tokenId].payments[index].paid, "Escrow: payment already paid");

        _escrows[tokenId].payments[index].paid = true;
        IERC20(_escrows[tokenId].token).transfer(_escrows[tokenId].payee, _escrows[tokenId].payments[index].amount);
    }

    function withdrawPayments(uint256 tokenId, uint256[] calldata indices) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(indices.length > 0, "Escrow: indices is empty");
        require(_escrows[tokenId].payee == msg.sender, "Escrow: caller is not the payee");

        uint256 amount;
        for (uint256 i = 0; i < indices.length; i++) {
            require(indices[i] < _escrows[tokenId].payments.length, "Escrow: index out of bounds");
            require(_escrows[tokenId].payments[indices[i]].funded, "Escrow: payment not funded");
            require(_escrows[tokenId].payments[indices[i]].unlocked, "Escrow: payment not unlocked");
            require(!_escrows[tokenId].payments[indices[i]].paid, "Escrow: payment already paid");
            amount += _escrows[tokenId].payments[indices[i]].amount;
        }

        for (uint256 i = 0; i < indices.length; i++) {
            _escrows[tokenId].payments[indices[i]].paid = true;
        }

        IERC20(_escrows[tokenId].token).transfer(_escrows[tokenId].payee, amount);
    }

    function withdrawAll(uint256 tokenId) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(_escrows[tokenId].payee == msg.sender, "Escrow: caller is not the payee");

        uint256 amount;
        Payment[] storage payments = _escrows[tokenId].payments;
        for (uint256 i = 0; i < _escrows[tokenId].payments.length; i++) {
            bool funded = payments[i].funded;
            bool unlocked = payments[i].unlocked;
            bool paid = payments[i].paid;
            if (funded && unlocked && !paid) {
                amount += payments[i].amount;
                payments[i].paid = true;
            }
        }

        IERC20(_escrows[tokenId].token).transfer(_escrows[tokenId].payee, amount);
        _escrows[tokenId].payments = payments;
    }

    function getEscrow(uint256 tokenId) external view returns (EscrowInfo memory) {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        return _escrows[tokenId];
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