// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StakeholderManager.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract ProductManager is StakeholderManager {
    using Counters for Counters.Counter;

    struct Product {
        uint256 id;
        string name;
        string description;
        address manufacturer;
        string manufacturerName;
        string[] ingredients;
        string photoURL;
        string certificateURL;
        bool approved;
    }

    Counters.Counter private _productIdCounter;
    Counters.Counter private _registrationIdCounter;

    mapping(uint256 => Product) internal _products;
    mapping(uint256 => uint256) private _registrationIdToProductId;
    mapping(uint256 => bool) private _isRegistrationIdInQueue;
    mapping(address => uint256[]) private _manufacturerProducts;
    uint256[] private _registrationQueue;
    uint256[] private _approvedProductIds;

    event ProductRegistered(uint256 indexed registrationId, string name, address indexed manufacturer);
    event ProductApproved(uint256 indexed productId, uint256 indexed registrationId, string name, address indexed manufacturer);
    event ProductRejected(uint256 indexed registrationId, string name, address indexed manufacturer);

    function registerProduct(
        string memory name,
        string memory description,
        string[] memory ingredients,
        string memory photoURL,
        string memory certificateURL
    ) public onlyManufacturer {
        uint256 registrationId = _registrationIdCounter.current();
        _registrationIdCounter.increment();

        (, string memory manufacturerName, , , , ,) = getStakeholderDetails(msg.sender);

        Product memory newProduct = Product({
            id: 0,
            name: name,
            description: description,
            manufacturer: msg.sender,
            manufacturerName: manufacturerName,
            ingredients: ingredients,
            photoURL: photoURL,
            certificateURL: certificateURL,
            approved: false
        });

        _products[registrationId] = newProduct;
        _registrationQueue.push(registrationId);
        _isRegistrationIdInQueue[registrationId] = true;

        emit ProductRegistered(registrationId, name, msg.sender);
    }

    function approveProduct(uint256 registrationId) public onlyAdmin {
        require(_products[registrationId].id == 0, "Product is already approved");
        require(_isRegistrationIdInQueue[registrationId], "Registration ID is not in the queue");

        uint256 productId = _productIdCounter.current();
        _productIdCounter.increment();

        _products[registrationId].id = productId;
        _products[registrationId].approved = true;
        _registrationIdToProductId[registrationId] = productId;
        _approvedProductIds.push(productId);
        _manufacturerProducts[_products[registrationId].manufacturer].push(productId);

        emit ProductApproved(productId, registrationId, _products[registrationId].name, _products[registrationId].manufacturer);

        _removeFromRegistrationQueue(registrationId);
        _isRegistrationIdInQueue[registrationId] = false;
    }

    function rejectProduct(uint256 registrationId) public onlyAdmin {
        require(_products[registrationId].id == 0, "Product is already approved");

        emit ProductRejected(registrationId, _products[registrationId].name, _products[registrationId].manufacturer);

        delete _products[registrationId];
        _removeFromRegistrationQueue(registrationId);
    }

    function getProductDetailsForApproval(uint256 registrationId)
        public
        view
        onlyAdmin
        returns (
            uint256,
            string memory,
            string memory,
            address,
            string memory,
            string[] memory,
            string memory,
            string memory,
            bool
        )
    {
        require(_products[registrationId].manufacturer != address(0), "Invalid registration ID");
        require(!_products[registrationId].approved, "Product is already approved");

        Product memory product = _products[registrationId];

        return (
            product.id,
            product.name,
            product.description,
            product.manufacturer,
            product.manufacturerName,
            product.ingredients,
            product.photoURL,
            product.certificateURL,
            product.approved
        );
    }

    function getApprovedProductDetails(uint256 productId)
        public
        view
        returns (
            uint256,
            string memory,
            string memory,
            address,
            string memory,
            string[] memory,
            string memory,
            string memory,
            bool
        )
    {
        uint256 registrationId = _getRegistrationIdByProductId(productId);
        require(_products[registrationId].approved, "Product is not approved");

        Product memory product = _products[registrationId];

        return (
            product.id,
            product.name,
            product.description,
            product.manufacturer,
            product.manufacturerName,
            product.ingredients,
            product.photoURL,
            product.certificateURL,
            product.approved
        );
    }

    function getRegistrationQueueIds() public view onlyAdmin returns (uint256[] memory) {
        return _registrationQueue;
    }

    function getApprovedProductIds() public view returns (uint256[] memory) {
        return _approvedProductIds;
    }

    function getRegistrationQueueLength() public view onlyAdmin returns (uint256) {
        return _registrationQueue.length;
    }

    function getApprovedProductsLength() public view returns (uint256) {
        return _approvedProductIds.length;
    }

    function getManufacturerProducts(address manufacturer) public view returns (uint256[] memory) {
        return _manufacturerProducts[manufacturer];
    }

    function _removeFromRegistrationQueue(uint256 registrationId) private {
        for (uint256 i = 0; i < _registrationQueue.length; i++) {
            if (_registrationQueue[i] == registrationId) {
                _registrationQueue[i] = _registrationQueue[_registrationQueue.length - 1];
                _registrationQueue.pop();
                break;
            }
        }
    }

    function _getRegistrationIdByProductId(uint256 productId) private view returns (uint256) {
        for (uint256 i = 0; i < _registrationIdCounter.current(); i++) {
            if (_registrationIdToProductId[i] == productId) {
                return i;
            }
        }
        revert("Product not found");
    }

    function isApprovedProduct(uint256 productId) public view returns (bool) {
        return _products[productId].approved;
    }
}