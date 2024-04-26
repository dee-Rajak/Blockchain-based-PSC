// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BatchManager.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract TraceabilityManager is BatchManager {
    using Counters for Counters.Counter;

    struct Transaction {
        uint256 id;
        uint256 batchId;
        address from;
        address to;
        uint256 quantity;
        uint256 timestamp;
    }

    Counters.Counter private _transactionIdCounter;

    mapping(uint256 => Transaction) private _transactions;
    mapping(uint256 => uint256[]) private _batchTransactions;
    mapping(address => mapping(uint256 => uint256)) private _pharmacyProductBatches;

    event TransactionRecorded(uint256 indexed transactionId, uint256 indexed batchId, address indexed from, address to, uint256 quantity);
    event ProductPurchased(address indexed pharmacy, uint256 indexed productId, uint256 indexed batchId, address consumer);

    function recordTransaction(
        uint256 batchId,
        address to,
        uint256 quantity
    ) public {
        require(_batches[batchId].manufacturer != address(0), "Invalid batch ID");
        require(
            isManufacturer(msg.sender) ||
            isDistributor(msg.sender) ||
            isWholesaler(msg.sender) ||
            isPharmacy(msg.sender) ||
            isConsumer(msg.sender),
            "Caller is not authorized to record transactions"
        );

        uint256 transactionId = _transactionIdCounter.current();
        _transactionIdCounter.increment();

        Transaction memory newTransaction = Transaction({
            id: transactionId,
            batchId: batchId,
            from: msg.sender,
            to: to,
            quantity: quantity,
            timestamp: block.timestamp
        });

        _transactions[transactionId] = newTransaction;
        _batchTransactions[batchId].push(transactionId);

        emit TransactionRecorded(transactionId, batchId, msg.sender, to, quantity);
    }

    function purchaseProduct(uint256 productId, address pharmacy) public onlyConsumer {
        require(isPharmacy(pharmacy), "Invalid pharmacy address");
        require(_isProductApproved(productId), "Product is not approved");

        uint256[] memory pharmacyBatches = _getPharmacyBatchesByProduct(pharmacy, productId);
        require(pharmacyBatches.length > 0, "Product not available at the pharmacy");

        uint256 batchId = pharmacyBatches[0];
        recordTransaction(batchId, msg.sender, 1);

        _pharmacyProductBatches[pharmacy][productId] = batchId;

        emit ProductPurchased(pharmacy, productId, batchId, msg.sender);
    }

    function getTrackHistory(uint256 batchId)
        public
        view
        returns (Transaction[] memory)
    {
        uint256[] memory transactionIds = _batchTransactions[batchId];
        Transaction[] memory trackHistory = new Transaction[](transactionIds.length);

        for (uint256 i = 0; i < transactionIds.length; i++) {
            trackHistory[i] = _transactions[transactionIds[i]];
        }

        return trackHistory;
    }

    function _getPharmacyBatchesByProduct(address pharmacy, uint256 productId)
        private
        view
        returns (uint256[] memory)
    {
        uint256[] memory pharmacyBatches = new uint256[](10);
        uint256 count = 0;

        uint256[] memory productBatches = getBatchesByProduct(productId);
        for (uint256 i = 0; i < productBatches.length; i++) {
            uint256 batchId = productBatches[i];
            uint256[] memory batchTransactions = _batchTransactions[batchId];

            for (uint256 j = 0; j < batchTransactions.length; j++) {
                Transaction memory transaction = _transactions[batchTransactions[j]];
                if (transaction.to == pharmacy) {
                    pharmacyBatches[count] = batchId;
                    count++;
                    break;
                }
            }
        }

        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = pharmacyBatches[i];
        }

        return result;
    }
}