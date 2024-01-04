// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Escrow} from "../../src/Escrow.sol";

contract BaseEscrow is Escrow {
    bytes32 private constant ARBITRATOR_REQUEST_TYPE_HASH = keccak256("ArbitratorRequest(uint256 invoiceId,address oldArbitrator,address newArbitrator,uint256 salt)");

    constructor(
        address owner,
        string memory name, 
        string memory symbol
    ) Escrow(owner, name, symbol) {}

    function hashArbitratorRequestStruct(ArbitratorRequest calldata request)
        public
        view
        returns (bytes32)
    {
        return super._hashArbitratorRequestStruct(request);
    }

    function isValidSignature(
        address signer,
        bytes32 hash,
        bytes calldata signature
    ) public view returns (bool) {
        return super._isValidSignature(signer, hash, signature);
    }
}