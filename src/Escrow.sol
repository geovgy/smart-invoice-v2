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
        address token;
        string details;
        Payment[] payments;
        address arbitrator;
        uint256 deadline;
        bool locked;
    }

    uint256 internal _counter;
    uint256 internal _feeBasisPts;
    mapping(address token => uint256 amount) internal _feeBalances;
    mapping(uint256 invoiceId => EscrowInfo escrow) internal _escrows;
    mapping(uint256 invoiceId => uint256 tokenId) internal _payerId;
    mapping(uint256 invoiceId => uint256 tokenId) internal _payeeId;
    mapping(uint256 invoiceId => uint256 fee) internal _escrowArbitrationFeeBP;
    mapping(address arbitrator => bool valid) internal _arbitrators;
    mapping(address arbitrator => uint256 fee) internal _arbitratorFeeBasisPts;


    event Create(uint256 invoiceId, address payer, address payee, address token, uint256 amount, address arbitrator);
    event Deposit(uint256 invoiceId, uint256 index, uint256 amount, address from);
    event DepositBatch(uint256 invoiceId, uint256[] indices, uint256 amount, address from);
    event Unlock(uint256 invoiceId, uint256 index);
    event UnlockBatch(uint256 invoiceId, uint256[] indices);
    event Paid(uint256 invoiceId, uint256 index, address to, uint256 amount);
    event PaidBatch(uint256 invoiceId, address to, uint256 amount);
    event Dispute(uint256 invoiceId, address from, bytes32 details);
    event Resolve(uint256 invoiceId, address arbitrator, uint256 payerAmount, uint256 payeeAmount, bytes32 details);
    event Withdraw(uint256 invoiceId, address to, uint256 amount);


    modifier whenEscrowIsNotLocked(uint256 invoiceId) {
        require(_exists(invoiceId), "Escrow: invoiceId does not exist");
        require(!_escrows[invoiceId].locked, "Escrow: escrow is locked");
        _;
    }

    modifier onlyArbitrator(uint256 invoiceId) {
        require(_exists(invoiceId), "Escrow: invoiceId does not exist");
        require(
            _escrows[invoiceId].arbitrator == msg.sender, 
            "Escrow: caller is not the arbitrator"
        );
        _;
    }

    modifier onlyPayee(uint256 invoiceId) {
        require(_exists(invoiceId), "Escrow: invoiceId does not exist");
        require(
            payeeOf(invoiceId) == msg.sender, 
            "Escrow: caller is not the payee"
        );
        _;
    }


    constructor(
        address owner,
        string memory name, 
        string memory symbol
    ) ERC721(name, symbol) Ownable(owner) {}

    // TO DO:
    // - function for payee or payer to burn escrow after payout/withdrawal


    function createEscrow(
        address payee,
        address payer,
        EscrowInfo calldata escrow
    ) external nonReentrant {
        require(payee != address(0), "Escrow: payee is the zero address");
        require(payer != address(0), "Escrow: payer is the zero address");
        require(escrow.token != address(0), "Escrow: token is the zero address");
        require(
            escrow.arbitrator != address(0) && _arbitrators[escrow.arbitrator], 
            "Escrow: arbitrator is the zero address or not valid"
        );
        require(escrow.payments.length > 0, "Escrow: payments is empty");
        require(escrow.deadline > block.timestamp, "Escrow: deadline is in the past");
        uint256 total;
        for (uint256 i; i < escrow.payments.length; i++) {
            require(
                escrow.payments[i].amount > 0 && escrow.payments[i].amount <= _MAX_AMOUNT, 
                "Escrow: amount is zero or exceeds maximum limit"
            );
            require(!escrow.payments[i].funded, "Escrow: payment cannot be already funded");
            require(!escrow.payments[i].unlocked, "Escrow: payment cannot be already unlocked");
            require(!escrow.payments[i].paid, "Escrow: payment cannot be already paid");
            total += escrow.payments[i].amount;
        }

        uint256 invoiceId = _counter;
        uint256 tokenId = _counter * 2;
        uint256 tokenId2 = tokenId + 1;
        uint256 arbBP = _arbitratorFeeBasisPts[escrow.arbitrator];
        
        _escrows[invoiceId] = escrow;
        _payerId[invoiceId] = tokenId;
        _payeeId[invoiceId] = tokenId2;
        _escrowArbitrationFeeBP[invoiceId] = arbBP;

        unchecked {
            _counter++;
        }

        _safeMint(payer, tokenId);
        _safeMint(payee, tokenId2);

        emit Create(tokenId, payer, payee, escrow.token, total, escrow.arbitrator);
    }

    function depositPayment(
        uint256 invoiceId, 
        uint256 index
    ) external whenEscrowIsNotLocked(invoiceId) nonReentrant {
        require(index < _escrows[invoiceId].payments.length, "Escrow: index out of bounds");
        require(!_escrows[invoiceId].payments[index].unlocked, "Escrow: payment already unlocked");
        require(!_escrows[invoiceId].payments[index].funded, "Escrow: payment already funded");

        IERC20(_escrows[invoiceId].token).transferFrom(msg.sender, address(this), _escrows[invoiceId].payments[index].amount);
        _escrows[invoiceId].payments[index].funded = true;

        emit Deposit(invoiceId, index, _escrows[invoiceId].payments[index].amount, msg.sender);
    }

    function depositPayments(
        uint256 invoiceId, 
        uint256[] calldata indices
    ) external whenEscrowIsNotLocked(invoiceId) nonReentrant {
        require(indices.length > 0, "Escrow: indices is empty");

        uint256 amount;
        for (uint256 i; i < indices.length; i++) {
            require(indices[i] < _escrows[invoiceId].payments.length, "Escrow: index out of bounds");
            require(!_escrows[invoiceId].payments[indices[i]].unlocked, "Escrow: payment already unlocked");
            require(!_escrows[invoiceId].payments[indices[i]].funded, "Escrow: payment already funded");
            amount += _escrows[invoiceId].payments[indices[i]].amount;
        }
        
        IERC20(_escrows[invoiceId].token).transferFrom(msg.sender, address(this), amount);

        for (uint256 i; i < indices.length; i++) {
            _escrows[invoiceId].payments[indices[i]].funded = true;
        }

        emit DepositBatch(invoiceId, indices, amount, msg.sender);
    }

    function unlockPayment(
        uint256 invoiceId, 
        uint256 index
    ) external whenEscrowIsNotLocked(invoiceId) nonReentrant {
        require(index < _escrows[invoiceId].payments.length, "Escrow: index out of bounds");
        require(payerOf(invoiceId) == msg.sender, "Escrow: caller is not the payer");
        require(_escrows[invoiceId].payments[index].funded, "Escrow: payment not funded");
        require(!_escrows[invoiceId].payments[index].unlocked, "Escrow: payment already unlocked");

        _escrows[invoiceId].payments[index].unlocked = true;

        emit Unlock(invoiceId, index);
    }

    function unlockPayments(
        uint256 invoiceId, 
        uint256[] calldata indices
    ) external whenEscrowIsNotLocked(invoiceId) nonReentrant {
        require(indices.length > 0, "Escrow: indices is empty");
        require(payerOf(invoiceId) == msg.sender, "Escrow: caller is not the payer");

        for (uint256 i; i < indices.length; i++) {
            require(indices[i] < _escrows[invoiceId].payments.length, "Escrow: index out of bounds");
            require(_escrows[invoiceId].payments[indices[i]].funded, "Escrow: payment not funded");
            require(!_escrows[invoiceId].payments[indices[i]].unlocked, "Escrow: payment already unlocked");
        }

        for (uint256 i; i < indices.length; i++) {
            _escrows[invoiceId].payments[indices[i]].unlocked = true;
        }

        emit UnlockBatch(invoiceId, indices);
    }

    function collectPayment(
        uint256 invoiceId, 
        uint256 index
    ) external onlyPayee(invoiceId) nonReentrant {
        require(index < _escrows[invoiceId].payments.length, "Escrow: index out of bounds");
        require(_escrows[invoiceId].payments[index].funded, "Escrow: payment not funded");
        require(_escrows[invoiceId].payments[index].unlocked, "Escrow: payment not unlocked");
        require(!_escrows[invoiceId].payments[index].paid, "Escrow: payment already paid");

        uint256 fee = getFee(_escrows[invoiceId].payments[index].amount);
        uint256 amount = _escrows[invoiceId].payments[index].amount - fee;

        _escrows[invoiceId].payments[index].paid = true;
        _feeBalances[_escrows[invoiceId].token] += fee;

        IERC20(_escrows[invoiceId].token).transfer(msg.sender, amount);

        emit Paid(invoiceId, index, msg.sender, amount);
    }

    function collectPayments(
        uint256 invoiceId, 
        uint256[] calldata indices
    ) external onlyPayee(invoiceId) nonReentrant {
        require(indices.length > 0, "Escrow: indices is empty");

        uint256 amount;
        for (uint256 i; i < indices.length; i++) {
            require(indices[i] < _escrows[invoiceId].payments.length, "Escrow: index out of bounds");
            require(_escrows[invoiceId].payments[indices[i]].funded, "Escrow: payment not funded");
            require(_escrows[invoiceId].payments[indices[i]].unlocked, "Escrow: payment not unlocked");
            require(!_escrows[invoiceId].payments[indices[i]].paid, "Escrow: payment already paid");
            amount += _escrows[invoiceId].payments[indices[i]].amount;
        }

        uint256 fee = getFee(amount);
        amount -= fee;

        for (uint256 i = 0; i < indices.length; i++) {
            _escrows[invoiceId].payments[indices[i]].paid = true;
        }
        _feeBalances[_escrows[invoiceId].token] += fee;

        IERC20(_escrows[invoiceId].token).transfer(msg.sender, amount);

        emit PaidBatch(invoiceId, msg.sender, amount);
    }

    function collectPayments(uint256 invoiceId) external onlyPayee(invoiceId) nonReentrant {
        uint256 amount;
        EscrowInfo storage escrow = _escrows[invoiceId];
        for (uint256 i; i < _escrows[invoiceId].payments.length; i++) {
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

        _escrows[invoiceId] = escrow;
        _feeBalances[_escrows[invoiceId].token] += fee;

        IERC20(_escrows[invoiceId].token).transfer(msg.sender, amount);

        emit PaidBatch(invoiceId, msg.sender, amount);
    }

    function withdrawPayments(uint256 invoiceId) external whenEscrowIsNotLocked(invoiceId) nonReentrant {
        require(payerOf(invoiceId) == msg.sender, "Escrow: caller is not the payer");
        require(_escrows[invoiceId].deadline < block.timestamp, "Escrow: deadline has not passed");
        
        uint256 amount;
        bool funded;
        bool unlocked;
        bool paid;
        EscrowInfo storage escrow = _escrows[invoiceId];
        for (uint256 i; i < _escrows[invoiceId].payments.length; i++) {
            funded = escrow.payments[i].funded;
            unlocked = escrow.payments[i].unlocked;
            paid = escrow.payments[i].paid;
            if (funded && !unlocked && !paid) {
                escrow.payments[i].funded = false;
                amount += escrow.payments[i].amount;
            }
        }

        _escrows[invoiceId] = escrow;
        IERC20(_escrows[invoiceId].token).transfer(msg.sender, amount);

        emit Withdraw(invoiceId, msg.sender, amount);
    }

    function changeArbitrator(
        uint256 invoiceId, 
        address arbitrator
    ) external whenEscrowIsNotLocked(invoiceId) nonReentrant {
        require(
            payerOf(invoiceId) == msg.sender || payeeOf(invoiceId) == msg.sender, 
            "Escrow: caller is not the payer or payee"
        );
        require(arbitrator != address(0), "Escrow: arbitrator is the zero address");
        require(_arbitrators[arbitrator], "Escrow: arbitrator is not valid");
        require(
            payerOf(invoiceId) != arbitrator && payeeOf(invoiceId) != arbitrator, 
            "Escrow: arbitrator cannot be payer or payee"
        );

        _escrows[invoiceId].arbitrator = arbitrator;
        _escrowArbitrationFeeBP[invoiceId] = _arbitratorFeeBasisPts[arbitrator];
    }

    function dispute(
        uint256 invoiceId, 
        bytes32 disputeDetails
    ) external whenEscrowIsNotLocked(invoiceId) nonReentrant {
        require(
            payerOf(invoiceId) == msg.sender || payeeOf(invoiceId) == msg.sender, 
            "Escrow: caller is not the payer or payee"
        );
        bool isLockable;
        for(uint256 i; i < _escrows[invoiceId].payments.length; i++) {
            if (!_escrows[invoiceId].payments[i].unlocked) {
                isLockable = true;
                break;
            }
        }
        require(isLockable, "Escrow: escrow is not lockable");

        _escrows[invoiceId].locked = true;

        emit Dispute(invoiceId, msg.sender, disputeDetails);
    }

    function resolve(
        uint256 invoiceId,
        uint256 payerAmount,
        uint256 payeeAmount,
        bytes32 details
    ) external onlyArbitrator(invoiceId) nonReentrant {
        require(_exists(invoiceId), "Escrow: tokenId does not exist");
        require(_escrows[invoiceId].locked, "Escrow: escrow is not locked");

        EscrowInfo storage escrow = _escrows[invoiceId];

        uint256 total;
        for(uint256 i; i < escrow.payments.length; i++) {
            if (!escrow.payments[i].unlocked && escrow.payments[i].funded) {
                total += escrow.payments[i].amount;

                escrow.payments[i].unlocked = true;
                escrow.payments[i].paid = true;
            }
        }
        uint256 fee = getFee(total);
        uint256 arbitrationFee = total * _escrowArbitrationFeeBP[invoiceId] / _MAX_BASIS_POINTS;

        require(
            payerAmount + payeeAmount == total - arbitrationFee - fee,
            "Escrow: sum of resolution amounts does not equal total minus fees"
        );

        if (payeeAmount > 0) {
            IERC20(escrow.token).transfer(payeeOf(invoiceId), payeeAmount);
        }
        if (payerAmount > 0) {
            IERC20(escrow.token).transfer(payerOf(invoiceId), payerAmount);
        }
        if (arbitrationFee > 0) {
            IERC20(escrow.token).transfer(escrow.arbitrator, arbitrationFee);
        }

        _feeBalances[escrow.token] += fee;
        escrow.locked = false;
        _escrows[invoiceId] = escrow;

        emit Resolve(invoiceId, msg.sender, payerAmount, payeeAmount, details);
    }

    function setFee(uint256 basisPoints) external onlyOwner {
        require(basisPoints <= _MAX_BASIS_POINTS, "Escrow: basisPoints exceeds maximum limit");
        _feeBasisPts = basisPoints;
    }

    function collectFee(address token) external onlyOwner nonReentrant {
        require(_feeBalances[token] > 0, "Escrow: fee balance is zero");
        uint256 rev = _feeBalances[token];
        _feeBalances[token] = 0;
        IERC20(_escrows[0].token).transfer(owner(), rev);
    }

    function setArbitrator(
        address arbitrator, 
        uint256 fee
    ) external onlyOwner {
        require(arbitrator != address(0), "Escrow: arbitrator is the zero address");
        require(fee <= _MAX_BASIS_POINTS, "Escrow: fee exceeds maximum limit");
        _arbitrators[arbitrator] = true;
        _arbitratorFeeBasisPts[arbitrator] = fee;
    }

    function removeArbitrator(address arbitrator) external onlyOwner {
        require(arbitrator != address(0), "Escrow: arbitrator is the zero address");
        _arbitrators[arbitrator] = false;
        _arbitratorFeeBasisPts[arbitrator] = 0;
    }

    function getArbitrator(address arbitrator) external view returns (bool valid, uint256 basisPoints) {
        return (_arbitrators[arbitrator], _arbitratorFeeBasisPts[arbitrator]);
    }

    function getEscrow(uint256 invoiceId) external view returns (EscrowInfo memory) {
        require(_exists(invoiceId), "Escrow: tokenId does not exist");
        return _escrows[invoiceId];
    }

    function getFee(uint256 amount) public view returns (uint256) {
        return amount * _feeBasisPts / _MAX_BASIS_POINTS;
    }

    function totalEscrows() external view returns (uint256) {
        return _counter;
    }

    function totalSupply() external view returns (uint256) {
        return _counter * 2;
    }

    function payerOf(uint256 invoiceId) public view returns (address) {
        return _ownerOf(_payerId[invoiceId]);
    }

    function payeeOf(uint256 invoiceId) public view returns (address) {
        return _ownerOf(_payeeId[invoiceId]);
    }

    function _exists(uint256 invoiceId) internal view returns (bool) {
        return invoiceId < _counter;
    }
}