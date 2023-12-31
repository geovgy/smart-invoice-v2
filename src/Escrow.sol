// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


contract Escrow is ERC721, Ownable, ReentrancyGuard {
    uint256 private constant _MAX_BASIS_POINTS = 10000;
    uint256 private constant _MAX_AMOUNT = (2**256 - 1) / _MAX_BASIS_POINTS;

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
        address arbitrator;
        bool locked;
    }

    uint256 internal _counter;
    uint256 internal _basisPoints;
    mapping(address token => uint256 amount) internal _feeBalances;
    mapping(uint256 tokenId => EscrowInfo escrow) internal _escrows;
    mapping(uint256 tokenId => uint256 fee) internal _escrowArbBP;
    mapping(address arbitrator => bool valid) internal _arbitrators;
    mapping(address arbitrator => uint256 fee) internal _arbitratorBasisPoints;


    event Create(uint256 tokenId, address payer, address payee, address token, uint256 amount, address arbitrator);
    event Deposit(uint256 invoiceId, uint256 index, uint256 amount, address from);
    event DepositBatch(uint256 invoiceId, uint256[] indices, uint256 amount, address from);
    event Unlock(uint256 invoiceId, uint256 index);
    event UnlockBatch(uint256 invoiceId, uint256[] indices);
    event Paid(uint256 invoiceId, uint256 index, uint256 amount);
    event PaidBatch(uint256 invoiceId, uint256 amount);
    event Dispute(uint256 invoiceId, address from, bytes32 details);
    event Resolve(uint256 invoiceId, address arbitrator, uint256 payerAmount, uint256 payeeAmount, bytes32 details);


    modifier onlyArbitrator(uint256 tokenId) {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(
            _escrows[tokenId].arbitrator == msg.sender, 
            "Escrow: caller is not the arbitrator"
        );
        _;
    }


    constructor(
        address owner,
        string memory name, 
        string memory symbol
    ) ERC721(name, symbol) Ownable(owner) {}


    function createEscrow(
        EscrowInfo calldata escrow
    ) external nonReentrant {
        require(escrow.payer != address(0), "Escrow: payer is the zero address");
        require(escrow.payee != address(0), "Escrow: payee is the zero address");
        require(escrow.token != address(0), "Escrow: token is the zero address");
        require(
            escrow.arbitrator != address(0) && _arbitrators[escrow.arbitrator], 
            "Escrow: arbitrator is the zero address or not valid"
        );
        require(escrow.payments.length > 0, "Escrow: payments is empty");
        uint256 total;
        for (uint256 i = 0; i < escrow.payments.length; i++) {
            require(
                escrow.payments[i].amount > 0 && escrow.payments[i].amount <= _MAX_AMOUNT, 
                "Escrow: amount is zero or exceeds maximum limit"
            );
            require(!escrow.payments[i].funded, "Escrow: payment already funded");
            require(!escrow.payments[i].unlocked, "Escrow: payment already unlocked");
            require(!escrow.payments[i].paid, "Escrow: payment already paid");
            total += escrow.payments[i].amount;
        }

        uint256 tokenId = _counter;
        uint256 arbBP = _arbitratorBasisPoints[escrow.arbitrator];
        _escrows[tokenId] = escrow;
        _escrowArbBP[tokenId] = arbBP;

        _increment();
        _safeMint(escrow.payee, tokenId);

        emit Create(tokenId, escrow.payer, escrow.payee, escrow.token, total, escrow.arbitrator);
    }

    function depositPayment(uint256 tokenId, uint256 index) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(!_escrows[tokenId].locked, "Escrow: escrow is locked");
        require(index < _escrows[tokenId].payments.length, "Escrow: index out of bounds");
        require(!_escrows[tokenId].payments[index].unlocked, "Escrow: payment already unlocked");
        require(!_escrows[tokenId].payments[index].funded, "Escrow: payment already funded");

        IERC20(_escrows[tokenId].token).transferFrom(msg.sender, address(this), _escrows[tokenId].payments[index].amount);
        _escrows[tokenId].payments[index].funded = true;

        emit Deposit(tokenId, index, _escrows[tokenId].payments[index].amount, msg.sender);
    }

    function depositPayments(uint256 tokenId, uint256[] calldata indices) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(!_escrows[tokenId].locked, "Escrow: escrow is locked");
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

        emit DepositBatch(tokenId, indices, amount, msg.sender);
    }

    function unlockPayment(uint256 tokenId, uint256 index) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(!_escrows[tokenId].locked, "Escrow: escrow is locked");
        require(index < _escrows[tokenId].payments.length, "Escrow: index out of bounds");
        require(_escrows[tokenId].payer == msg.sender, "Escrow: caller is not the payer");
        require(_escrows[tokenId].payments[index].funded, "Escrow: payment not funded");
        require(!_escrows[tokenId].payments[index].unlocked, "Escrow: payment already unlocked");

        _escrows[tokenId].payments[index].unlocked = true;

        emit Unlock(tokenId, index);
    }

    function unlockPayments(uint256 tokenId, uint256[] calldata indices) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(!_escrows[tokenId].locked, "Escrow: escrow is locked");
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

        emit UnlockBatch(tokenId, indices);
    }

    function withdrawPayment(uint256 tokenId, uint256 index) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(index < _escrows[tokenId].payments.length, "Escrow: index out of bounds");
        require(_escrows[tokenId].payee == msg.sender, "Escrow: caller is not the payee");
        require(_escrows[tokenId].payments[index].funded, "Escrow: payment not funded");
        require(_escrows[tokenId].payments[index].unlocked, "Escrow: payment not unlocked");
        require(!_escrows[tokenId].payments[index].paid, "Escrow: payment already paid");

        uint256 fee = getFee(_escrows[tokenId].payments[index].amount);
        uint256 amount = _escrows[tokenId].payments[index].amount - fee;

        _escrows[tokenId].payments[index].paid = true;
        _feeBalances[_escrows[tokenId].token] += fee;

        IERC20(_escrows[tokenId].token).transfer(_escrows[tokenId].payee, amount);

        emit Paid(tokenId, index, amount);
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

        uint256 fee = getFee(amount);
        amount -= fee;

        for (uint256 i = 0; i < indices.length; i++) {
            _escrows[tokenId].payments[indices[i]].paid = true;
        }
        _feeBalances[_escrows[tokenId].token] += fee;

        IERC20(_escrows[tokenId].token).transfer(_escrows[tokenId].payee, amount);

        emit PaidBatch(tokenId, amount);
    }

    function withdrawAll(uint256 tokenId) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(_escrows[tokenId].payee == msg.sender, "Escrow: caller is not the payee");

        uint256 amount;
        EscrowInfo storage escrow = _escrows[tokenId];
        for (uint256 i = 0; i < _escrows[tokenId].payments.length; i++) {
            bool funded = escrow.payments[i].funded;
            bool unlocked = escrow.payments[i].unlocked;
            bool paid = escrow.payments[i].paid;
            if (funded && unlocked && !paid) {
                amount += escrow.payments[i].amount;
                escrow.payments[i].paid = true;
            }
        }

        uint256 fee = getFee(amount);
        amount -= fee;

        _escrows[tokenId] = escrow;
        _feeBalances[_escrows[tokenId].token] += fee;

        IERC20(_escrows[tokenId].token).transfer(_escrows[tokenId].payee, amount);

        emit PaidBatch(tokenId, amount);
    }

    function dispute(uint256 tokenId, bytes32 disputeDetails) external nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(!_escrows[tokenId].locked, "Escrow: escrow is locked");
        require(
            _escrows[tokenId].payer == msg.sender || _escrows[tokenId].payee == msg.sender, 
            "Escrow: caller is not the payer or payee"
        );
        bool isLockable;
        for(uint256 i = 0; i < _escrows[tokenId].payments.length; i++) {
            if (!_escrows[tokenId].payments[i].unlocked) {
                isLockable = true;
                break;
            }
        }
        require(isLockable, "Escrow: escrow is not lockable");

        _escrows[tokenId].locked = true;

        emit Dispute(tokenId, msg.sender, disputeDetails);
    }

    function resolve(
        uint256 tokenId,
        uint256 payerAmount,
        uint256 payeeAmount,
        bytes32 details
    ) external onlyArbitrator(tokenId) nonReentrant {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        require(_escrows[tokenId].locked, "Escrow: escrow is not locked");

        EscrowInfo storage escrow = _escrows[tokenId];

        uint256 total;
        for(uint256 i; i < escrow.payments.length; i++) {
            if (!escrow.payments[i].unlocked && escrow.payments[i].funded) {
                total += escrow.payments[i].amount;

                escrow.payments[i].unlocked = true;
                escrow.payments[i].paid = true;
            }
        }
        uint256 fee = getFee(total);
        uint256 arbitrationFee = total * _escrowArbBP[tokenId] / _MAX_BASIS_POINTS;

        require(
            payerAmount + payeeAmount == total - arbitrationFee - fee,
            "Escrow: resolution != remainder"
        );

        if (payeeAmount > 0) {
            IERC20(escrow.token).transfer(escrow.payee, payeeAmount);
        }
        if (payerAmount > 0) {
            IERC20(escrow.token).transfer(escrow.payer, payerAmount);
        }
        if (arbitrationFee > 0) {
            IERC20(escrow.token).transfer(escrow.arbitrator, arbitrationFee);
        }

        _feeBalances[escrow.token] += fee;
        escrow.locked = false;
        _escrows[tokenId] = escrow;

        emit Resolve(tokenId, msg.sender, payerAmount, payeeAmount, details);
    }

    function setFee(uint256 basisPoints) external onlyOwner {
        require(basisPoints <= _MAX_BASIS_POINTS, "Escrow: basisPoints exceeds maximum limit");
        _basisPoints = basisPoints;
    }

    function collectFee(address token) external onlyOwner nonReentrant {
        require(_feeBalances[token] > 0, "Escrow: fee balance is zero");
        uint256 rev = _feeBalances[token];
        _feeBalances[token] = 0;
        IERC20(_escrows[0].token).transfer(owner(), rev);
    }

    function setArbitrator(address arbitrator, uint256 fee) external onlyOwner {
        require(arbitrator != address(0), "Escrow: arbitrator is the zero address");
        require(fee <= _MAX_BASIS_POINTS, "Escrow: fee exceeds maximum limit");
        _arbitrators[arbitrator] = true;
        _arbitratorBasisPoints[arbitrator] = fee;
    }

    function removeArbitrator(address arbitrator) external onlyOwner {
        require(arbitrator != address(0), "Escrow: arbitrator is the zero address");
        _arbitrators[arbitrator] = false;
        _arbitratorBasisPoints[arbitrator] = 0;
    }

    function getArbitrator(address arbitrator) external view returns (bool valid, uint256 basisPoints) {
        return (_arbitrators[arbitrator], _arbitratorBasisPoints[arbitrator]);
    }

    function getEscrow(uint256 tokenId) external view returns (EscrowInfo memory) {
        require(_exists(tokenId), "Escrow: tokenId does not exist");
        return _escrows[tokenId];
    }

    function getFee(uint256 amount) public view returns (uint256) {
        return amount * _basisPoints / _MAX_BASIS_POINTS;
    }

    function totalSupply() external view returns (uint256) {
        return _counter;
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