// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {PolymerCCTPData} from "../Interfaces/IPolymerCCTP.sol";
import "../Interfaces/ITokenMessenger.sol";
import "../Interfaces/IMessageTransmitter.sol";

contract PolymerCCTP is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable tokenMessenger;
    address public immutable messageTransmitter;
    address public immutable usdc;

    address public guardian;
    address public pendingGuardian;
    address public feeCollector;

    mapping(uint32 => uint256) public feePerDomain;
    mapping(address => bool) public authorizedCallers;

    // Native gas fee settings per destination domain (in wei)
    mapping(uint32 => uint256) public nativeGasFeesPerDomain;

    uint256 public constant MAX_FEE_BPS = 100; // 1%
    uint256 public constant BPS_DENOMINATOR = 10000;

    event PolymerCCTPBridgeStarted(
        uint32 indexed destinationDomain, address indexed mintRecipient, uint256 amount, uint32 minFinalityThreshold, uint256 tokenFee 
    );
    event GasFeePayment(address indexed payer, uint32 indexed destinationDomain, uint256 gasFeePaid);

    event FeeUpdated(uint32 domain, uint256 fee);
    event FeeCollectorUpdated(address newFeeCollector);
    event AuthorizedCallerUpdated(address caller, bool authorized);
    event GuardianTransferStarted(address newGuardian);
    event GuardianTransferred(address oldGuardian, address newGuardian);

    modifier onlyGuardian() {
        require(msg.sender == guardian, "Only guardian");
        _;
    }

    constructor(address _tokenMessenger, address _usdc, address _guardian) {
        require(_tokenMessenger != address(0), "Invalid token messenger");
        require(_usdc != address(0), "Invalid USDC address");
        require(_guardian != address(0), "Invalid guardian");

        tokenMessenger = _tokenMessenger;
        usdc = _usdc;
        guardian = _guardian;
        feeCollector = _guardian;
    }

    function bridgeUSDC(uint256 amount, PolymerCCTPData memory data)
        external
        payable
        nonReentrant
    {
        require(amount > 0, "Invalid amount");
        require(data.mintRecipient != address(0), "Invalid recipient");

        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount + data.tokenFee);

        if (data.tokenFee > 0 && feeCollector != address(0)) {
            IERC20(usdc).safeTransfer(feeCollector, data.tokenFee);
        }

        IERC20(usdc).safeApprove(tokenMessenger, amount);
        bytes32 mintRecipient = bytes32(uint256(uint160(data.mintRecipient)));

        ITokenMessenger(tokenMessenger).depositForBurn(
            amount,
            data.destinationDomain,
            mintRecipient,
            usdc,
            bytes32(0), // Unrestricted caller
            0, // maxFee - 0 means no fee limit
            data.minFinalityThreshold // minFinalityThreshold - use default
        );
       
        // Emit Polymer-specific event for tracking
        emit PolymerCCTPBridgeStarted(
             data.destinationDomain, data.mintRecipient, amount,  data.minFinalityThreshold, data.tokenFee 
        );


        // Emit gas fee payment event if ETH was sent
        if (msg.value > 0) {
            emit GasFeePayment(msg.sender, data.destinationDomain, msg.value);
        }
    }

    function setFeeForDomain(uint32 domain, uint256 feeBps) external onlyGuardian {
        require(feeBps <= MAX_FEE_BPS, "Fee too high");
        feePerDomain[domain] = feeBps;
        emit FeeUpdated(domain, feeBps);
    }

    function setFeeCollector(address newFeeCollector) external onlyGuardian {
        require(newFeeCollector != address(0), "Invalid fee collector");
        feeCollector = newFeeCollector;
        emit FeeCollectorUpdated(newFeeCollector);
    }

    function setAuthorizedCaller(address caller, bool authorized) external onlyGuardian {
        authorizedCallers[caller] = authorized;
        emit AuthorizedCallerUpdated(caller, authorized);
    }

    function transferGuardianship(address newGuardian) external onlyGuardian {
        require(newGuardian != address(0), "Invalid guardian");
        pendingGuardian = newGuardian;
        emit GuardianTransferStarted(newGuardian);
    }

    function acceptGuardianship() external {
        require(msg.sender == pendingGuardian, "Not pending guardian");
        address oldGuardian = guardian;
        guardian = pendingGuardian;
        pendingGuardian = address(0);
        emit GuardianTransferred(oldGuardian, guardian);
    }

    function rescueTokens(address token, uint256 amount) external onlyGuardian {
        IERC20(token).safeTransfer(guardian, amount);
    }

    function rescueETH() external onlyGuardian {
        payable(guardian).transfer(address(this).balance);
    }

    receive() external payable {}
}
