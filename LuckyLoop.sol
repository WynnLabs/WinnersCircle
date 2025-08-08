// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LuckyLoop is ReentrancyGuard, Ownable {
    // ===== IMMUTABLE CONFIG =====
    address public immutable prizePoolWallet = 0x3F449799411d3a2Bc8E232d48282422B4344fe6D;
    address public immutable profitWallet = 0x31Bd345293BB862A913935551ce0a0101efE5194;

    // ===== TIER PARAMETERS =====
    uint256 public constant TIER1_ENTRY_FEE = 0.00125 ether;
    uint256 public constant TIER1_PRIZE_AMOUNT = 0.025 ether;
    uint256 public constant TIER1_PROFIT_AMOUNT = 0.0125 ether;
    uint256 public constant TIER1_MAX_PARTICIPANTS = 100;

    uint256 public constant TIER2_ENTRY_FEE = 0.0125 ether;
    uint256 public constant TIER2_PRIZE_AMOUNT = 0.25 ether;
    uint256 public constant TIER2_PROFIT_AMOUNT = 0.125 ether;
    uint256 public constant TIER2_MAX_PARTICIPANTS = 100;

    // ===== STATE =====
    mapping(uint256 => address[]) public tierParticipants;
    mapping(uint256 => mapping(address => bool)) public hasEntered;
    mapping(uint256 => bool) public isTierActive;

    // ===== EVENTS =====
    event Entered(uint256 indexed tier, address indexed participant);
    event WinnerSelected(uint256 indexed tier, address indexed winner, uint256 prizeAmount);
    event FundsDistributed(uint256 prizeAmount, uint256 profitAmount);
    event TierActivated(uint256 indexed tier, bool active);

    constructor() {
        // default owner is msg.sender (Ownable). If you want the owner to be the profitWallet,
        // transfer ownership immediately:
        _transferOwnership(profitWallet);

        isTierActive[1] = true;
        isTierActive[2] = true;
    }

    // ===== CORE FUNCTIONS =====
    function enterLottery(uint256 tier) external payable nonReentrant {
        require(tier == 1 || tier == 2, "Invalid tier");
        require(isTierActive[tier], "Tier inactive");
        require(!hasEntered[tier][msg.sender], "Already entered");

        if (tier == 1) {
            require(msg.value == TIER1_ENTRY_FEE, "Tier 1: incorrect fee");
            require(tierParticipants[1].length < TIER1_MAX_PARTICIPANTS, "Tier 1 full");
        } else {
            require(msg.value == TIER2_ENTRY_FEE, "Tier 2: incorrect fee");
            require(tierParticipants[2].length < TIER2_MAX_PARTICIPANTS, "Tier 2 full");
        }

        tierParticipants[tier].push(msg.sender);
        hasEntered[tier][msg.sender] = true;

        emit Entered(tier, msg.sender);

        // If the tier reached max participants, draw a winner
        if (tierParticipants[tier].length == (tier == 1 ? TIER1_MAX_PARTICIPANTS : TIER2_MAX_PARTICIPANTS)) {
            _drawWinner(tier);
        }
    }

    // ===== INTERNAL =====
    function _drawWinner(uint256 tier) internal {
        require(tier == 1 || tier == 2, "Invalid tier");
        uint256 participantCount = tierParticipants[tier].length;
        require(participantCount > 0, "No participants");

        uint256 prizeAmount = tier == 1 ? TIER1_PRIZE_AMOUNT : TIER2_PRIZE_AMOUNT;
        uint256 profitAmount = tier == 1 ? TIER1_PROFIT_AMOUNT : TIER2_PROFIT_AMOUNT;
        uint256 totalRequired = prizeAmount + profitAmount;

        // Safety: ensure contract has enough balance to pay out
        require(address(this).balance >= totalRequired, "Insufficient contract balance for payout");

        uint256 index = _randomIndex(tier) % participantCount;
        address winner = tierParticipants[tier][index];

        // Reset per-round entries before transfers to avoid reentrancy edgecases with state (we still use nonReentrant)
        // Clear hasEntered for all participants
        for (uint256 i = 0; i < participantCount; i++) {
            address participant = tierParticipants[tier][i];
            hasEntered[tier][participant] = false;
        }
        // Clear participants array
        delete tierParticipants[tier];

        // Pay prize to winner
        (bool sentPrize, ) = winner.call{value: prizeAmount}("");
        require(sentPrize, "Prize transfer failed");

        // Pay profit to profit wallet
        (bool sentProfit, ) = profitWallet.call{value: profitAmount}("");
        require(sentProfit, "Profit transfer failed");

        emit WinnerSelected(tier, winner, prizeAmount);
        emit FundsDistributed(prizeAmount, profitAmount);
    }

    /// @dev A simple pseudo-randomness function. NOT secure for high-value/attacked games.
    ///      For production use, integrate a VRF (Chainlink VRF or similar).
    function _randomIndex(uint256 tier) internal view returns (uint256) {
        // Use a combination of recent block data, contract address, tier and participant count to make the seed harder to predict.
        uint256 partLen = tierParticipants[tier].length;
        return uint256(keccak256(abi.encodePacked(
            blockhash(block.number - 1),
            block.timestamp,
            block.difficulty,
            address(this),
            tier,
            partLen
        )));
    }

    // ===== VIEW FUNCTIONS =====
    function getParticipantCount(uint256 tier) external view returns (uint256) {
        require(tier == 1 || tier == 2, "Invalid tier");
        return tierParticipants[tier].length;
    }

    function checkEntry(uint256 tier, address participant) external view returns (bool) {
        require(tier == 1 || tier == 2, "Invalid tier");
        return hasEntered[tier][participant];
    }

    // ===== ADMIN =====
    /// @notice Owner can withdraw any stuck funds (emergency).
    function emergencyWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /// @notice Activate or deactivate a tier
    function setTierActive(uint256 tier, bool active) external onlyOwner {
        require(tier == 1 || tier == 2, "Invalid tier");
        isTierActive[tier] = active;
        emit TierActivated(tier, active);
    }

    // Receive function to accept ETH (entry fees)
    receive() external payable {}
}
