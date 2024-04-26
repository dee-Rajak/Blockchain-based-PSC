// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract StakeholderManager is AccessControl {
    using Strings for uint256;

    // bytes32 public constant DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");
    bytes32 public constant MANUFACTURER_ROLE = keccak256("MANUFACTURER_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant WHOLESALER_ROLE = keccak256("WHOLESALER_ROLE");
    bytes32 public constant PHARMACY_ROLE = keccak256("PHARMACY_ROLE");
    bytes32 public constant CONSUMER_ROLE = keccak256("CONSUMER_ROLE");

    struct Stakeholder {
        string name;
        string email;
        bytes32 hashedPassword;
        bytes32 role;
        bool approved;
        string location;
        string detailsIPFSHash;
        string license;
    }

    address[] private registrationQueue;

    mapping(address => Stakeholder) public stakeholders;
    mapping(bytes32 => address[]) private stakeholdersByRole;
    mapping(address => bool) private isInRegistrationQueue;
    mapping(address => uint256) private registrationQueueIndex;

    event StakeholderRegistered(address indexed stakeholder, bytes32 indexed role);
    event StakeholderApproved(address indexed stakeholder, bytes32 indexed role);
    event StakeholderRemoved(address indexed stakeholder, bytes32 indexed role);
    event StakeholderRegistrationRejected(address indexed stakeholder, bytes32 indexed role);
    event StakeholderRegistrationUpdated(address indexed stakeholder, bytes32 indexed role);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function registerStakeholder(
        string memory name,
        string memory email,
        string memory password,
        bytes32 role,
        string memory location,
        string memory detailsIPFSHash,
        string memory license
    ) public {
        require(!hasRole(role, msg.sender), "Stakeholder already registered");
        require(!hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || role == DEFAULT_ADMIN_ROLE, "Admin cannot register for additional roles");
        require(!isInRegistrationQueue[msg.sender], "Stakeholder already in registration queue");
        bytes32 hashedPassword = keccak256(abi.encodePacked(password));
        bool isApproved = role == CONSUMER_ROLE;
        stakeholders[msg.sender] = Stakeholder(
            name,
            email,
            hashedPassword,
            role,
            isApproved,
            location,
            detailsIPFSHash,
            license
        );
        if (role != DEFAULT_ADMIN_ROLE && role != CONSUMER_ROLE) {
            registrationQueue.push(msg.sender);
            registrationQueueIndex[msg.sender] = registrationQueue.length - 1;
            isInRegistrationQueue[msg.sender] = true;
        }
        if (isApproved) {
            _grantRole(role, msg.sender);
            stakeholdersByRole[role].push(msg.sender);
        }
        emit StakeholderRegistered(msg.sender, role);
    }

    function updateStakeholderRegistration(
        string memory name,
        string memory email,
        string memory password,
        bytes32 role,
        string memory location,
        string memory detailsIPFSHash,
        string memory license
    ) public {
        require(isInRegistrationQueue[msg.sender], "Stakeholder not in registration queue");
        require(!hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || role == DEFAULT_ADMIN_ROLE, "Admin cannot update registration");
        bytes32 hashedPassword = keccak256(abi.encodePacked(password));
        stakeholders[msg.sender] = Stakeholder(
            name,
            email,
            hashedPassword,
            role,
            stakeholders[msg.sender].approved,
            location,
            detailsIPFSHash,
            license
        );
        emit StakeholderRegistrationUpdated(msg.sender, role);
    }

    function approveStakeholder(address stakeholder) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!stakeholders[stakeholder].approved, "Stakeholder already approved");
        stakeholders[stakeholder].approved = true;
        _grantRole(stakeholders[stakeholder].role, stakeholder);
        stakeholdersByRole[stakeholders[stakeholder].role].push(stakeholder);
        uint256 index = registrationQueueIndex[stakeholder];
        registrationQueue[index] = registrationQueue[registrationQueue.length - 1];
        registrationQueueIndex[registrationQueue[index]] = index;
        registrationQueue.pop();
        isInRegistrationQueue[stakeholder] = false;
        emit StakeholderApproved(stakeholder, stakeholders[stakeholder].role);
    }

    function rejectStakeholder(address stakeholder) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isInRegistrationQueue[stakeholder], "Stakeholder not in registration queue");
        uint256 index = registrationQueueIndex[stakeholder];
        registrationQueue[index] = registrationQueue[registrationQueue.length - 1];
        registrationQueueIndex[registrationQueue[index]] = index;
        registrationQueue.pop();
        isInRegistrationQueue[stakeholder] = false;
        emit StakeholderRegistrationRejected(stakeholder, stakeholders[stakeholder].role);
    }

    function getStakeholderDetails(address stakeholderAddress)
        public
        view
        returns (
            string memory,
            string memory,
            bytes32,
            bool,
            string memory,
            string memory,
            string memory
        )
    {
        if (!stakeholders[stakeholderAddress].approved && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert("Provided address is not a stakeholder");
        }
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
            (stakeholders[msg.sender].approved && stakeholders[stakeholderAddress].approved),
            "Access denied"
        );
        Stakeholder memory stakeholder = stakeholders[stakeholderAddress];
        return (
            stakeholder.name,
            stakeholder.email,
            stakeholder.role,
            stakeholder.approved,
            stakeholder.location,
            stakeholder.detailsIPFSHash,
            stakeholder.license
        );
    }

    function removeStakeholder(address stakeholder) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole(stakeholders[stakeholder].role, stakeholder), "Stakeholder not registered");
        _revokeRole(stakeholders[stakeholder].role, stakeholder);
        emit StakeholderRemoved(stakeholder, stakeholders[stakeholder].role);
    }

    function loginStakeholder(string memory password) public view returns (bool) {
        bytes32 hashedPassword = keccak256(abi.encodePacked(password));
        return stakeholders[msg.sender].hashedPassword == hashedPassword;
    }

    function getStakeholdersByRole(bytes32 role) public view returns (address[] memory) {
        return stakeholdersByRole[role];
    }

    function getStakeholderRegistrationQueueCount() public view onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
        return registrationQueue.length;
    }

    function getRegistrationQueueAddresses() public view onlyRole(DEFAULT_ADMIN_ROLE) returns (address[] memory) {
        return registrationQueue;
    }

    function grantAdminRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(DEFAULT_ADMIN_ROLE, account);
    }

    function revokeAdminRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(DEFAULT_ADMIN_ROLE, account);
    }

    // RBAC Modifiers
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }

    modifier onlyManufacturer() {
        require(hasRole(MANUFACTURER_ROLE, msg.sender), "Caller is not a manufacturer");
        _;
    }

    modifier onlyDistributor() {
        require(hasRole(DISTRIBUTOR_ROLE, msg.sender), "Caller is not a distributor");
        _;
    }

    modifier onlyWholesaler() {
        require(hasRole(WHOLESALER_ROLE, msg.sender), "Caller is not a wholesaler");
        _;
    }

    modifier onlyPharmacy() {
        require(hasRole(PHARMACY_ROLE, msg.sender), "Caller is not a pharmacy");
        _;
    }

    modifier onlyConsumer() {
        require(hasRole(CONSUMER_ROLE, msg.sender), "Caller is not a consumer");
        _;
    }

    // RBAC Functions
    function isManufacturer(address account) public view returns (bool) {
        return hasRole(MANUFACTURER_ROLE, account);
    }

    function isDistributor(address account) public view returns (bool) {
        return hasRole(DISTRIBUTOR_ROLE, account);
    }

    function isWholesaler(address account) public view returns (bool) {
        return hasRole(WHOLESALER_ROLE, account);
    }

    function isPharmacy(address account) public view returns (bool) {
        return hasRole(PHARMACY_ROLE, account);
    }

    function isConsumer(address account) public view returns (bool) {
        return hasRole(CONSUMER_ROLE, account);
    }

}