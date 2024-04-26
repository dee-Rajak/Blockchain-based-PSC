// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ProductManager.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract BatchManager is ProductManager {
    using Counters for Counters.Counter;

    struct Batch {
        uint256 id;
        uint256 productId;
        uint256 rootDistributionId;
        uint256 manufactureDate;
        uint256 expiryDate;
        uint256 quantity;
        address manufacturer;
    }

    struct Distribution {
        uint256 id;
        uint256 batchId;
        uint256 totalQuantity;
        uint256 remainingQuantity;
        uint256 price;
        address from;
        address to;
        uint256 timestamp;
        string billingPhotoIPFSHash;
    }

    struct DistributionNode {
        Distribution distribution;
        uint256[] childIds;
    }

    struct UnitSale {
        uint256 batchId;
        uint256 saleId;
        address pharmacy;
        address consumer;
        uint256 quantity;
        uint256 timestamp;
    }

    Counters.Counter private _batchIdCounter;
    Counters.Counter private _distributionIdCounter;
    Counters.Counter private _saleIdCounter;

    mapping(uint256 => Batch) private _batches;
    mapping(uint256 => DistributionNode) private _distributions;
    mapping(uint256 => uint256[]) private _productBatches;
    mapping(uint256 => mapping(address => uint256)) private _stakeholderDistributionIds;
    mapping(uint256 => mapping(uint256 => UnitSale)) private _unitSales;

    event BatchCreated(uint256 indexed batchId, uint256 indexed productId, address indexed manufacturer, uint256 quantity);
    event BatchTransferred(
        uint256 indexed batchId,
        uint256 indexed distributionId,
        address indexed from,
        address to,
        uint256 quantity,
        uint256 price,
        string billingPhotoIPFSHash
    );
    event UnitsSold(
        uint256 indexed batchId,
        uint256 indexed saleId,
        address indexed pharmacy,
        address consumer,
        uint256 quantity,
        uint256 timestamp
    );

    function createBatch(
        uint256 productId,
        uint256 quantity,
        uint256 price,
        uint256 manufactureDate,
        uint256 expiryDate
    ) public onlyManufacturer {
        (, , , address productManufacturer, , , , , ) = getApprovedProductDetails(productId);
        require(productManufacturer == msg.sender, "Product does not belong to the manufacturer");

        uint256 batchId = _batchIdCounter.current();
        _batchIdCounter.increment();
        if (_distributionIdCounter.current() == 0) {
            _distributionIdCounter.increment();
        }
        uint256 rootDistributionId = _distributionIdCounter.current();
        _distributionIdCounter.increment();

        Distribution memory rootDistribution = Distribution({
            id: rootDistributionId,
            batchId: batchId,
            totalQuantity: quantity,
            remainingQuantity: quantity,
            price: price,
            from: address(0),
            to: msg.sender,
            timestamp: block.timestamp,
            billingPhotoIPFSHash: "Batch Creation Successful"
        });

        _distributions[rootDistributionId] = DistributionNode({
            distribution: rootDistribution,
            childIds: new uint256[](0)
        });

        _batches[batchId] = Batch({
            id: batchId,
            productId: productId,
            rootDistributionId: rootDistributionId,
            manufactureDate: manufactureDate,
            expiryDate: expiryDate,
            quantity: quantity,
            manufacturer: msg.sender
        });

        _productBatches[productId].push(batchId);
        _stakeholderDistributionIds[batchId][msg.sender] = rootDistributionId;

        emit BatchCreated(batchId, productId, msg.sender, quantity);
    }

    function transferBatch(
        uint256 batchId,
        address to,
        uint256 quantity,
        uint256 price,
        string memory billingPhotoIPFSHash
    ) public {
        require(isManufacturerBatch(batchId, msg.sender) || isStakeholderBatch(batchId, msg.sender), "Not authorized to transfer the batch");
        require(isManufacturer(to) || isDistributor(to) || isWholesaler(to) || isPharmacy(to), "Recipient is not a valid stakeholder");
        if (isManufacturer(msg.sender)) { require(isDistributor(to), "Recipient is not a distributor."); }
        else if (isDistributor(msg.sender)) { require(isWholesaler(to), "Recipient is not a distributor."); }
        else if (isWholesaler(msg.sender)) { require(isPharmacy(to), "Recipient is not a distributor."); }
        require(quantity <= getRemainingQuantity(batchId, msg.sender), "Insufficient quantity");

        uint256 distributionId = _distributionIdCounter.current();
        _distributionIdCounter.increment();

        Distribution memory newDistribution = Distribution({
            id: distributionId,
            batchId: batchId,
            totalQuantity: quantity,
            remainingQuantity: quantity,
            price: price,
            from: msg.sender,
            to: to,
            timestamp: block.timestamp,
            billingPhotoIPFSHash: billingPhotoIPFSHash
        });

        _distributions[distributionId] = DistributionNode({
            distribution: newDistribution,
            childIds: new uint256[](0)
        });

        uint256 parentDistributionId;
        if (isManufacturerBatch(batchId, msg.sender)) {
            parentDistributionId = _batches[batchId].rootDistributionId;
        } else {
            parentDistributionId = _stakeholderDistributionIds[batchId][msg.sender];
            require(parentDistributionId != 0, "Stakeholder does not have any distribution for the batch");
        }

        _distributions[parentDistributionId].distribution.remainingQuantity -= quantity;
        _distributions[parentDistributionId].childIds.push(distributionId);
        _stakeholderDistributionIds[batchId][to] = distributionId;

        emit BatchTransferred(batchId, distributionId, msg.sender, to, quantity, price, billingPhotoIPFSHash);
    }

    function sellUnitsToConsumer(uint256 batchId, address pharmacy, uint256 quantity) public {
        if (isPharmacy(msg.sender)) {
            // If the caller is a pharmacy
            require(isPharmacyBatch(batchId, msg.sender), "Pharmacy does not have units from this batch");
            uint256 pharmacyDistributionId = _stakeholderDistributionIds[batchId][msg.sender];
            require(quantity <= _distributions[pharmacyDistributionId].distribution.remainingQuantity, "Insufficient units available");

            uint256 saleId = _saleIdCounter.current();
            _saleIdCounter.increment();

            _unitSales[batchId][saleId] = UnitSale({
                batchId: batchId,
                saleId: saleId,
                pharmacy: msg.sender,
                consumer: pharmacy,
                quantity: quantity,
                timestamp: block.timestamp
            });

            _distributions[pharmacyDistributionId].distribution.remainingQuantity -= quantity;

            emit UnitsSold(batchId, saleId, msg.sender, pharmacy, quantity, block.timestamp);
        } else if (isConsumer(msg.sender)) {
            // If the caller is a consumer
            require(isPharmacy(pharmacy), "Invalid pharmacy address");
            require(isPharmacyBatch(batchId, pharmacy), "Pharmacy does not have units from this batch");
            uint256 pharmacyDistributionId = _stakeholderDistributionIds[batchId][pharmacy];
            require(quantity <= _distributions[pharmacyDistributionId].distribution.remainingQuantity, "Insufficient units available");

            uint256 saleId = _saleIdCounter.current();
            _saleIdCounter.increment();

            _unitSales[batchId][saleId] = UnitSale({
                batchId: batchId,
                saleId: saleId,
                pharmacy: pharmacy,
                consumer: msg.sender,
                quantity: quantity,
                timestamp: block.timestamp
            });

            _distributions[pharmacyDistributionId].distribution.remainingQuantity -= quantity;

            emit UnitsSold(batchId, saleId, pharmacy, msg.sender, quantity, block.timestamp);
        } else {
            // If the caller is neither a pharmacy nor a consumer
            revert("Caller must be either a pharmacy or a consumer");
        }
    }

    function getDistributionHistory(uint256 batchId, address stakeholder) public view returns (Distribution[] memory) {
        uint256 distributionId = _stakeholderDistributionIds[batchId][stakeholder];
        require(distributionId != 0, "Stakeholder does not have any distribution for the batch");

        Distribution[] memory distributions = new Distribution[](0);
        uint256 currentId = distributionId;

        while (currentId != 0) {
            Distribution memory currentDistribution = _distributions[currentId].distribution;
            distributions = _appendDistribution(distributions, currentDistribution);
            currentId = _getParentDistributionId(batchId, currentDistribution.from);
        }

        return _reverseDistributionArray(distributions);
    }

    function getProductBatches(uint256 productId) public view returns (uint256[] memory) {
        return _productBatches[productId];
    }

    function _getParentDistributionId(uint256 batchId, address stakeholder) private view returns (uint256) {
        return _stakeholderDistributionIds[batchId][stakeholder];
    }

    function _appendDistribution(Distribution[] memory array, Distribution memory distribution) private pure returns (Distribution[] memory) {
        Distribution[] memory newArray = new Distribution[](array.length + 1);
        for (uint256 i = 0; i < array.length; i++) {
            newArray[i] = array[i];
        }
        newArray[array.length] = distribution;
        return newArray;
    }

    function _reverseDistributionArray(Distribution[] memory array) private pure returns (Distribution[] memory) {
        uint256 length = array.length;
        Distribution[] memory reversedArray = new Distribution[](length);
        for (uint256 i = 0; i < length; i++) {
            reversedArray[i] = array[length - 1 - i];
        }
        return reversedArray;
    }

    function isManufacturerBatch(uint256 batchId, address manufacturer) public view returns (bool) {
        return _batches[batchId].manufacturer == manufacturer;
    }

    function isStakeholderBatch(uint256 batchId, address stakeholder) public view returns (bool) {
        return _stakeholderDistributionIds[batchId][stakeholder] != 0;
    }

    function isPharmacyBatch(uint256 batchId, address pharmacy) public view returns (bool) {
        uint256 distributionId = _stakeholderDistributionIds[batchId][pharmacy];
        return distributionId != 0 && _distributions[distributionId].distribution.to == pharmacy;
    }

    function getUnitSale(uint256 batchId, uint256 saleId) public view returns (UnitSale memory) {
        return _unitSales[batchId][saleId];
    }

    function getRemainingQuantity(uint256 batchId, address stakeholder) public view returns (uint256) {
        uint256 distributionId = _stakeholderDistributionIds[batchId][stakeholder];
        require(distributionId != 0, "Stakeholder does not have any distribution for the batch");

        return _distributions[distributionId].distribution.remainingQuantity;
    }

    function getBatchDetails(uint256 batchId)
        public
        view
        returns (
            uint256,
            uint256,
            // uint256,
            uint256,
            uint256,
            uint256,
            address
        )
    {
        require(_batches[batchId].id != 0, "Invalid batch ID");
        
        Batch memory batch = _batches[batchId];
        return (
            batch.id,
            batch.productId,
            // batch.rootDistributionId,
            batch.manufactureDate,
            batch.expiryDate,
            batch.quantity,
            batch.manufacturer
        );
    }
}