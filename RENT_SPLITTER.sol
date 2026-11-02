// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title RentSplitter - Blockchain-Based Rent Collection System
/// @author Ji-in Kang - APANPS5470
/// @notice Automates rent collection among roommates using smart contracts
/// @dev Implements escrow pattern with automatic enforcement and refunds

contract RentSplitter {
    // State machine for rent cycle phases (inspired by BallotV4 pattern)
    enum Phase { Setup, Active, GracePeriod, Completed }
    Phase public currentPhase;
    
    // Payment cycle status
    enum CycleStatus { Pending, Late, Paid, Refunded }
    
    // Core state variables
    address public landlord;
    uint256 public totalRent;
    uint256 public dueDate;
    uint256 public constant GRACE_PERIOD = 3 days;
    uint256 public constant LATE_FEE_PERCENTAGE = 5; // 5% late fee
    uint256 public cycleNumber;
    
    // Roommate details structure (similar to Airlines.sol pattern)
    struct RoommateDetails {
        uint256 escrow;        // Amount held in escrow
        uint256 rentShare;     // Monthly rent obligation
        bool hasPaid;          // Payment status for current cycle
        uint256 paymentTimestamp;
        uint8 status;          // 0: inactive, 1: active
        bool isLate;
    }
    
    // Membership and balance tracking (inspired by Airlines.sol)
    mapping(address => RoommateDetails) public roommateDetails;
    mapping(address => uint8) public membership;  // 0: not member, 1: member
    address[] public roommateAddresses;
    
    // Cycle tracking
    CycleStatus public currentStatus;
    uint256 public totalCollected;
    uint256 public totalLateFees;
    
    // Events (expanded based on SimpleBank.sol patterns)
    event LogContractCreated(address indexed landlord, uint256 totalRent, uint256 roommateCount);
    event LogPaymentMade(address indexed roommate, uint256 amount, uint256 timestamp);
    event LogLateFeeApplied(address indexed roommate, uint256 lateFee);
    event LogRentReleased(address indexed landlord, uint256 amount, uint256 cycleNumber);
    event LogRefundProcessed(address indexed roommate, uint256 amount);
    event LogCycleReset(uint256 cycleNumber, uint256 newDueDate);
    event LogPhaseChanged(Phase from, Phase to);
    
    // Modifiers (following Airlines.sol pattern)
    modifier onlyLandlord() {
        require(msg.sender == landlord, "Only landlord can call this function");
        _;
    }
    
    modifier onlyMember() {
        require(membership[msg.sender] == 1, "Only registered roommates can call");
        _;
    }
    
    modifier validPhase(Phase reqPhase) {
        require(currentPhase == reqPhase, "Invalid phase for this operation");
        _;
    }
    
    modifier inPaymentPhase() {
        require(
            currentStatus == CycleStatus.Pending || currentStatus == CycleStatus.Late,
            "Payments not accepted in current status"
        );
        _;
    }
    
    /// @notice Constructor to initialize the rent splitter contract
    /// @param _totalRent Total monthly rent amount in wei
    /// @param _roommateAddresses Array of roommate wallet addresses
    /// @param _rentShares Array of individual rent shares in wei
    constructor(
        uint256 _totalRent,
        address[] memory _roommateAddresses,
        uint256[] memory _rentShares
    ) {
        require(_roommateAddresses.length == _rentShares.length, "Arrays length mismatch");
        require(_roommateAddresses.length > 0, "At least one roommate required");
        
        landlord = msg.sender;
        totalRent = _totalRent;
        cycleNumber = 1;
        
        // Verify total shares equal total rent
        uint256 totalShares = 0;
        for (uint256 i = 0; i < _rentShares.length; i++) {
            totalShares += _rentShares[i];
        }
        require(totalShares == _totalRent, "Total shares must equal total rent");
        
        // Register roommates (similar to Airlines registration)
        for (uint256 i = 0; i < _roommateAddresses.length; i++) {
            address roommate = _roommateAddresses[i];
            require(roommate != address(0), "Invalid roommate address");
            require(_rentShares[i] > 0, "Rent share must be greater than 0");
            
            membership[roommate] = 1;
            roommateDetails[roommate] = RoommateDetails({
                escrow: 0,
                rentShare: _rentShares[i],
                hasPaid: false,
                paymentTimestamp: 0,
                status: 1,
                isLate: false
            });
            roommateAddresses.push(roommate);
        }
        
        // Set initial state
        dueDate = block.timestamp + 30 days;
        currentStatus = CycleStatus.Pending;
        currentPhase = Phase.Active;
        
        emit LogContractCreated(landlord, totalRent, _roommateAddresses.length);
    }
    
    /// @notice Pay rent for the current cycle
    /// @dev Implements checks-effects-interactions pattern from SimpleBank
    function payRent() external payable onlyMember inPaymentPhase {
        RoommateDetails storage details = roommateDetails[msg.sender];
        require(!details.hasPaid, "Already paid for this cycle");
        require(details.status == 1, "Roommate not active");
        
        uint256 requiredAmount = details.rentShare;
        
        // Check if in grace period and apply late fee if necessary
        if (block.timestamp > dueDate) {
            if (currentPhase != Phase.GracePeriod) {
                currentPhase = Phase.GracePeriod;
                emit LogPhaseChanged(Phase.Active, Phase.GracePeriod);
            }
            
            if (block.timestamp > dueDate + GRACE_PERIOD) {
                uint256 lateFee = (requiredAmount * LATE_FEE_PERCENTAGE) / 100;
                requiredAmount += lateFee;
                totalLateFees += lateFee;
                details.isLate = true;
                
                if (currentStatus == CycleStatus.Pending) {
                    currentStatus = CycleStatus.Late;
                }
                
                emit LogLateFeeApplied(msg.sender, lateFee);
            }
        }
        
        require(msg.value >= requiredAmount, "Insufficient payment amount");
        
        // Update state before external calls (checks-effects-interactions)
        details.hasPaid = true;
        details.escrow += requiredAmount;
        details.paymentTimestamp = block.timestamp;
        totalCollected += requiredAmount;
        
        // Return excess payment if any
        if (msg.value > requiredAmount) {
            uint256 excess = msg.value - requiredAmount;
            (bool success, ) = msg.sender.call{value: excess}("");
            require(success, "Excess refund failed");
            totalCollected -= excess;
        }
        
        emit LogPaymentMade(msg.sender, requiredAmount, block.timestamp);
        
        // Check if all roommates have paid
        if (_checkAllPaid()) {
            _releaseFundsToLandlord();
        }
    }
    
    /// @notice Check if all roommates have paid
    /// @return allPaid True if all roommates have paid, false otherwise
    function checkAllPaid() external view returns (bool allPaid) {
        return _checkAllPaid();
    }
    
    /// @notice Internal function to check if all roommates have paid
    function _checkAllPaid() internal view returns (bool) {
        for (uint256 i = 0; i < roommateAddresses.length; i++) {
            if (!roommateDetails[roommateAddresses[i]].hasPaid) {
                return false;
            }
        }
        return true;
    }
    
    /// @notice Release funds to landlord when all roommates have paid
    function _releaseFundsToLandlord() internal {
        require(_checkAllPaid(), "Not all roommates have paid");
        
        currentStatus = CycleStatus.Paid;
        currentPhase = Phase.Completed;
        uint256 totalToRelease = totalCollected;
        
        // Clear escrow before transfer (checks-effects-interactions)
        totalCollected = 0;
        for (uint256 i = 0; i < roommateAddresses.length; i++) {
            roommateDetails[roommateAddresses[i]].escrow = 0;
        }
        
        // Transfer funds to landlord
        (bool success, ) = landlord.call{value: totalToRelease}("");
        require(success, "Transfer to landlord failed");
        
        emit LogRentReleased(landlord, totalToRelease, cycleNumber);
        emit LogPhaseChanged(currentPhase, Phase.Completed);
        
        // Reset for next cycle
        _resetCycle();
    }
    
    /// @notice Trigger refund for unpaid rent (landlord only)
    /// @dev Can only be called after grace period expires
    function triggerRefund() external onlyLandlord {
        require(
            currentStatus == CycleStatus.Pending || currentStatus == CycleStatus.Late,
            "Can only refund in Pending or Late status"
        );
        require(block.timestamp > dueDate + GRACE_PERIOD, "Can only refund after grace period");
        require(!_checkAllPaid(), "Cannot refund - all roommates have paid");
        
        currentStatus = CycleStatus.Refunded;
        currentPhase = Phase.Completed;
        
        // Process refunds
        for (uint256 i = 0; i < roommateAddresses.length; i++) {
            address roommate = roommateAddresses[i];
            RoommateDetails storage details = roommateDetails[roommate];
            
            if (details.hasPaid && details.escrow > 0) {
                uint256 refundAmount = details.escrow;
                details.escrow = 0; // Prevent re-entrancy
                
                (bool success, ) = roommate.call{value: refundAmount}("");
                require(success, "Refund transfer failed");
                
                emit LogRefundProcessed(roommate, refundAmount);
            }
        }
        
        totalCollected = 0;
        emit LogPhaseChanged(currentPhase, Phase.Completed);
        
        // Reset for next cycle
        _resetCycle();
    }
    
    /// @notice Reset contract for next payment cycle
    function _resetCycle() internal {
        cycleNumber++;
        totalCollected = 0;
        totalLateFees = 0;
        currentStatus = CycleStatus.Pending;
        currentPhase = Phase.Active;
        dueDate = block.timestamp + 30 days;
        
        // Reset all roommate payment statuses
        for (uint256 i = 0; i < roommateAddresses.length; i++) {
            RoommateDetails storage details = roommateDetails[roommateAddresses[i]];
            details.hasPaid = false;
            details.paymentTimestamp = 0;
            details.isLate = false;
        }
        
        emit LogCycleReset(cycleNumber, dueDate);
        emit LogPhaseChanged(Phase.Completed, Phase.Active);
    }
    
    // View functions
    
    /// @notice Get details for a specific roommate
    /// @param _roommate Address of the roommate
    /// @return rentShare Monthly rent share
    /// @return hasPaid Payment status for current cycle
    /// @return escrow Amount in escrow
    /// @return isLate Late payment flag
    function getRoommateDetails(address _roommate) 
        external 
        view 
        returns (
            uint256 rentShare,
            bool hasPaid,
            uint256 escrow,
            bool isLate
        ) 
    {
        require(membership[_roommate] == 1, "Roommate not found");
        RoommateDetails memory details = roommateDetails[_roommate];
        return (
            details.rentShare,
            details.hasPaid,
            details.escrow,
            details.isLate
        );
    }
    
    /// @notice Get current contract balance
    /// @return Contract balance in wei
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    /// @notice Get time remaining until due date
    /// @return Seconds until due date (0 if past due)
    function getTimeUntilDue() external view returns (uint256) {
        if (block.timestamp >= dueDate) {
            return 0;
        }
        return dueDate - block.timestamp;
    }
    
    /// @notice Check if currently in grace period
    /// @return True if in grace period, false otherwise
    function isInGracePeriod() external view returns (bool) {
        return block.timestamp > dueDate && block.timestamp <= dueDate + GRACE_PERIOD;
    }
    
    /// @notice Get number of roommates
    /// @return Total number of registered roommates
    function getRoommateCount() external view returns (uint256) {
        return roommateAddresses.length;
    }
    
    /// @notice Emergency pause function (landlord only)
    /// @dev Added for safety, allows landlord to pause in emergencies
    function emergencyPause() external onlyLandlord {
        currentPhase = Phase.Setup;
        emit LogPhaseChanged(currentPhase, Phase.Setup);
    }
}
