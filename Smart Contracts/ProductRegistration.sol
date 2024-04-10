// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./StakeholderManager.sol";

contract ProductRegistration is StakeholderManager {
    struct Product {
        uint256 id;
        string name;
        string description;
        string manufacturer;
        string[] ingredients;
        string ipfsHash;
        bool approved;
    }

    mapping(uint256 => Product) public products;
    mapping(address => uint256[]) public manufacturerProducts;
    uint256 public productCount;
    uint256[] private registrationQueue;

    event ProductRegistrationSubmitted(uint256 indexed productId, string name, string manufacturer);
    event ProductApproved(uint256 indexed productId, string name, string manufacturer);

    function submitProductRegistration(
        string memory _name,
        string memory _description,
        string[] memory _ingredients,
        string memory _ipfsHash
    ) public onlyManufacturer {
        productCount++;
        products[productCount] = Product(
            productCount,
            _name,
            _description,
            stakeholders[msg.sender].name,
            _ingredients,
            _ipfsHash,
            false
        );
        registrationQueue.push(productCount);
        emit ProductRegistrationSubmitted(productCount, _name, stakeholders[msg.sender].name);
    }

    function approveProduct(uint256 _productId) public onlyAdmin {
        require(!products[_productId].approved, "Product is already approved");
        products[_productId].approved = true;
        manufacturerProducts[msg.sender].push(_productId);  // to be corrected
        emit ProductApproved(_productId, products[_productId].name, products[_productId].manufacturer);
    }

    function getProductDetails(uint256 _productId)
        public
        view
        returns (
            string memory,
            string memory,
            string memory,
            string[] memory,
            string memory,
            bool
        )
    {
        require(products[_productId].approved, "Product is not approved");
        Product memory product = products[_productId];
        return (
            product.name,
            product.description,
            product.manufacturer,
            product.ingredients,
            product.ipfsHash,
            product.approved
        );
    }

    function getManufacturerProducts(address _manufacturer)
        public
        view
        returns (uint256[] memory)
    {
        return manufacturerProducts[_manufacturer];
    }

    function getProductRegistrationQueueCount() public view returns (uint256) {
        return registrationQueue.length;
    }

    function getRegistrationQueueProductId(uint256 _index) public view returns (uint256) {
        require(_index < registrationQueue.length, "Invalid index");
        return registrationQueue[_index];
    }
}