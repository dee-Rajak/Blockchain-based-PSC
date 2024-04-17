// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ProductManager.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract BatchManager is ProductManager {
    using Counters for Counters.Counter;

    struct Batch {
        uint256 id;
        uint256 productId;
        uint256 quantity;
        uint256 manufacturedDate;
        uint256 expiryDate;
        string batchNumber;
        address manufacturer;
    }

    Counters.Counter private _batchIdCounter;

    mapping(uint256 => Batch) internal _batches;
    mapping(uint256 => uint256[]) internal _productBatches;

    event BatchCreated(uint256 indexed batchId, uint256 indexed productId, uint256 quantity, address indexed manufacturer);

    function createBatch(
        uint256 productId,
        uint256 quantity,
        uint256 manufacturedDate,
        uint256 expiryDate,
        string memory batchNumber
    ) public onlyManufacturer {
        require(_isProductApproved(productId), "Product is not approved");

        uint256 batchId = _batchIdCounter.current();
        _batchIdCounter.increment();

        Batch memory newBatch = Batch({
            id: batchId,
            productId: productId,
            quantity: quantity,
            manufacturedDate: manufacturedDate,
            expiryDate: expiryDate,
            batchNumber: batchNumber,
            manufacturer: msg.sender
        });

        _batches[batchId] = newBatch;
        _productBatches[productId].push(batchId);

        emit BatchCreated(batchId, productId, quantity, msg.sender);
    }

    function getBatchDetails(uint256 batchId)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            string memory,
            address
        )
    {
        require(_batches[batchId].manufacturer != address(0), "Invalid batch ID");

        Batch memory batch = _batches[batchId];

        return (
            batch.id,
            batch.productId,
            batch.quantity,
            batch.manufacturedDate,
            batch.expiryDate,
            batch.batchNumber,
            batch.manufacturer
        );
    }

    function getBatchesByProduct(uint256 productId) public view returns (uint256[] memory) {
        return _productBatches[productId];
    }

    function _isProductApproved(uint256 productId) internal view returns (bool) {
        (, , , , , , , , bool approved) = getApprovedProductDetails(productId);
        return approved;
    }
}