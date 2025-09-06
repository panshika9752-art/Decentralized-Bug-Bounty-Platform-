// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Bug Bounty Platform
 * @dev A smart contract platform for managing bug bounty programs
 * @author AI Engineer
 */
contract Project {
    
    // Enums
    enum BountyStatus { Active, Submitted, UnderReview, Approved, Rejected, Paid }
    enum Severity { Low, Medium, High, Critical }
    
    // Structs
    struct Bounty {
        uint256 id;
        address creator;
        string title;
        string description;
        uint256 reward;
        Severity minSeverity;
        BountyStatus status;
        uint256 deadline;
        address hunter;
        string submissionDetails;
        uint256 createdAt;
    }
    
    struct Hunter {
        address hunterAddress;
        uint256 reputation;
        uint256 totalBugsFound;
        uint256 totalEarned;
        bool isVerified;
    }
    
    // State Variables
    mapping(uint256 => Bounty) public bounties;
    mapping(address => Hunter) public hunters;
    mapping(address => uint256[]) public creatorBounties;
    mapping(address => uint256[]) public hunterSubmissions;
    
    uint256 public nextBountyId = 1;
    uint256 public totalBounties = 0;
    uint256 public platformFeePercent = 5; // 5% platform fee
    address public owner;
    
    // Events
    event BountyCreated(uint256 indexed bountyId, address indexed creator, uint256 reward);
    event BountySubmitted(uint256 indexed bountyId, address indexed hunter);
    event BountyApproved(uint256 indexed bountyId, address indexed hunter, uint256 reward);
    event BountyRejected(uint256 indexed bountyId, address indexed hunter);
    event HunterRegistered(address indexed hunter);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyBountyCreator(uint256 _bountyId) {
        require(bounties[_bountyId].creator == msg.sender, "Only bounty creator can call this");
        _;
    }
    
    modifier bountyExists(uint256 _bountyId) {
        require(_bountyId < nextBountyId && _bountyId > 0, "Bounty does not exist");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Core Function 1: Create a new bug bounty
     * @param _title Title of the bounty
     * @param _description Detailed description of what to find
     * @param _minSeverity Minimum severity level required
     * @param _deadline Unix timestamp for bounty deadline
     */
    function createBounty(
        string memory _title,
        string memory _description,
        Severity _minSeverity,
        uint256 _deadline
    ) external payable {
        require(msg.value > 0, "Bounty reward must be greater than 0");
        require(_deadline > block.timestamp, "Deadline must be in the future");
        require(bytes(_title).length > 0, "Title cannot be empty");
        
        bounties[nextBountyId] = Bounty({
            id: nextBountyId,
            creator: msg.sender,
            title: _title,
            description: _description,
            reward: msg.value,
            minSeverity: _minSeverity,
            status: BountyStatus.Active,
            deadline: _deadline,
            hunter: address(0),
            submissionDetails: "",
            createdAt: block.timestamp
        });
        
        creatorBounties[msg.sender].push(nextBountyId);
        totalBounties++;
        
        emit BountyCreated(nextBountyId, msg.sender, msg.value);
        nextBountyId++;
    }
    
    /**
     * @dev Core Function 2: Submit a bug report for a bounty
     * @param _bountyId ID of the bounty to submit for
     * @param _submissionDetails Detailed bug report and proof
     */
    function submitBug(uint256 _bountyId, string memory _submissionDetails) external bountyExists(_bountyId) {
        Bounty storage bounty = bounties[_bountyId];
        
        require(bounty.status == BountyStatus.Active, "Bounty is not active");
        require(block.timestamp <= bounty.deadline, "Bounty deadline has passed");
        require(bytes(_submissionDetails).length > 0, "Submission details cannot be empty");
        require(bounty.hunter == address(0), "Bounty already has a submission");
        
        // Register hunter if not already registered
        if (hunters[msg.sender].hunterAddress == address(0)) {
            _registerHunter(msg.sender);
        }
        
        bounty.status = BountyStatus.Submitted;
        bounty.hunter = msg.sender;
        bounty.submissionDetails = _submissionDetails;
        
        hunterSubmissions[msg.sender].push(_bountyId);
        
        emit BountySubmitted(_bountyId, msg.sender);
    }
    
    /**
     * @dev Core Function 3: Approve or reject a bug submission
     * @param _bountyId ID of the bounty to review
     * @param _approve Whether to approve (true) or reject (false) the submission
     * @param _severityLevel Severity level of the found bug (if approved)
     */
    function reviewSubmission(
        uint256 _bountyId, 
        bool _approve, 
        Severity _severityLevel
    ) external bountyExists(_bountyId) onlyBountyCreator(_bountyId) {
        Bounty storage bounty = bounties[_bountyId];
        
        require(bounty.status == BountyStatus.Submitted, "No submission to review");
        require(bounty.hunter != address(0), "No hunter assigned");
        
        if (_approve) {
            require(_severityLevel >= bounty.minSeverity, "Severity level too low for this bounty");
            
            bounty.status = BountyStatus.Approved;
            
            // Calculate platform fee and hunter reward
            uint256 platformFee = (bounty.reward * platformFeePercent) / 100;
            uint256 hunterReward = bounty.reward - platformFee;
            
            // Update hunter stats
            Hunter storage hunter = hunters[bounty.hunter];
            hunter.totalBugsFound++;
            hunter.totalEarned += hunterReward;
            
            // Calculate reputation boost based on severity
            uint256 reputationBoost = _calculateReputationBoost(_severityLevel);
            hunter.reputation += reputationBoost;
            
            // Transfer payments
            payable(bounty.hunter).transfer(hunterReward);
            payable(owner).transfer(platformFee);
            
            bounty.status = BountyStatus.Paid;
            
            emit BountyApproved(_bountyId, bounty.hunter, hunterReward);
        } else {
            bounty.status = BountyStatus.Rejected;
            
            // Refund the bounty creator (minus gas costs)
            payable(bounty.creator).transfer(bounty.reward);
            
            emit BountyRejected(_bountyId, bounty.hunter);
        }
    }
    
    // Internal function to register a new hunter
    function _registerHunter(address _hunter) internal {
        hunters[_hunter] = Hunter({
            hunterAddress: _hunter,
            reputation: 10, // Starting reputation
            totalBugsFound: 0,
            totalEarned: 0,
            isVerified: false
        });
        
        emit HunterRegistered(_hunter);
    }
    
    // Internal function to calculate reputation boost based on severity
    function _calculateReputationBoost(Severity _severity) internal pure returns (uint256) {
        if (_severity == Severity.Critical) return 50;
        if (_severity == Severity.High) return 30;
        if (_severity == Severity.Medium) return 20;
        return 10; // Low severity
    }
    
    // View Functions
    function getBounty(uint256 _bountyId) external view bountyExists(_bountyId) returns (Bounty memory) {
        return bounties[_bountyId];
    }
    
    function getHunterStats(address _hunter) external view returns (Hunter memory) {
        return hunters[_hunter];
    }
    
    function getCreatorBounties(address _creator) external view returns (uint256[] memory) {
        return creatorBounties[_creator];
    }
    
    function getHunterSubmissions(address _hunter) external view returns (uint256[] memory) {
        return hunterSubmissions[_hunter];
    }
    
    // Owner functions
    function updatePlatformFee(uint256 _newFeePercent) external onlyOwner {
        require(_newFeePercent <= 10, "Platform fee cannot exceed 10%");
        platformFeePercent = _newFeePercent;
    }
    
    function verifyHunter(address _hunter) external onlyOwner {
        require(hunters[_hunter].hunterAddress != address(0), "Hunter not registered");
        hunters[_hunter].isVerified = true;
    }
}
