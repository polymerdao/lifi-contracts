// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ILiFi } from "../Interfaces/ILiFi.sol";
import { IPolymerCCTP } from "../Interfaces/IPolymerCCTP.sol";
import { LibAsset, IERC20 } from "../Libraries/LibAsset.sol";
import { LibSwap } from "../Libraries/LibSwap.sol";
import { ReentrancyGuard } from "../Helpers/ReentrancyGuard.sol";
import { SwapperV2 } from "../Helpers/SwapperV2.sol";
import { Validatable } from "../Helpers/Validatable.sol";
import { InvalidConfig } from "../Errors/GenericErrors.sol";

/// @title PolymerCCTPFacet
/// @author LI.FI (https://li.fi)
/// @notice Provides functionality for bridging USDC through Polymer CCTP
/// @custom:version 1.0.0
contract PolymerCCTPFacet is ILiFi, ReentrancyGuard, SwapperV2, Validatable {
    /// Storage ///
    
    IPolymerCCTP public immutable polymerCCTP;
    address public immutable usdc;
    
    /// Types ///
    
    /// @param destinationDomain CCTP destination domain
    struct PolymerCCTPData {
        uint32 destinationDomain;
    }
    
    /// Events ///
    
    event PolymerCCTPBridgeStarted(
        bytes32 indexed transactionId,
        uint32 indexed destinationDomain,
        bytes32 indexed mintRecipient,
        uint256 amount,
        uint64 nonce
    );
    
    /// Constructor ///
    
    /// @notice Initialize the facet with PolymerCCTP contract address
    /// @param _polymerCCTP The address of the PolymerCCTP contract
    constructor(IPolymerCCTP _polymerCCTP) {
        if (address(_polymerCCTP) == address(0)) revert InvalidConfig();
        
        polymerCCTP = _polymerCCTP;
        usdc = _polymerCCTP.usdc();
        
        if (usdc == address(0)) revert InvalidConfig();
    }
    
    /// External Methods ///
    
    /// @notice Bridges USDC via PolymerCCTP
    /// @param _bridgeData The core bridge data
    /// @param _polymerData Data specific to PolymerCCTP
    function startBridgeTokensViaPolymerCCTP(
        ILiFi.BridgeData memory _bridgeData,
        PolymerCCTPData calldata _polymerData
    )
        external
        payable
        nonReentrant
        refundExcessNative(payable(msg.sender))
        validateBridgeData(_bridgeData)
        onlyAllowSourceToken(_bridgeData, usdc)
        doesNotContainSourceSwaps(_bridgeData)
        doesNotContainDestinationCalls(_bridgeData)
    {
        _startBridge(_bridgeData, _polymerData);
    }
    
    /// @notice Performs a swap before bridging via PolymerCCTP
    /// @param _bridgeData The core bridge data
    /// @param _swapData Array of swap instructions
    /// @param _polymerData Data specific to PolymerCCTP
    function swapAndStartBridgeTokensViaPolymerCCTP(
        ILiFi.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData,
        PolymerCCTPData calldata _polymerData
    )
        external
        payable
        nonReentrant
        refundExcessNative(payable(msg.sender))
        validateBridgeData(_bridgeData)
        onlyAllowSourceToken(_bridgeData, usdc)
        containsSourceSwaps(_bridgeData)
        doesNotContainDestinationCalls(_bridgeData)
    {
        _bridgeData.minAmount = _depositAndSwap(
            _bridgeData.transactionId,
            _bridgeData.minAmount,
            _swapData,
            payable(msg.sender)
        );
        
        _startBridge(_bridgeData, _polymerData);
    }
    
    /// Private Methods ///
    
    /// @dev Performs the actual bridging logic
    /// @param _bridgeData The core bridge data
    /// @param _polymerData Data specific to PolymerCCTP
    function _startBridge(
        ILiFi.BridgeData memory _bridgeData,
        PolymerCCTPData memory _polymerData
    ) private {
        // Convert receiver address to bytes32 format for CCTP
        bytes32 mintRecipient = bytes32(uint256(uint160(_bridgeData.receiver)));
        
        // Deposit tokens from user if not already deposited from swaps
        if (!LibAsset.isNativeAsset(_bridgeData.sendingAssetId)) {
            LibAsset.depositAsset(
                _bridgeData.sendingAssetId,
                _bridgeData.minAmount
            );
        }
        
        // Approve PolymerCCTP to spend USDC
        LibAsset.maxApproveERC20(
            IERC20(usdc),
            address(polymerCCTP),
            _bridgeData.minAmount
        );
        
        // Execute unrestricted bridge (anyone can complete on destination)
        // Forward any ETH sent as gas fees to the PolymerCCTP contract
        uint64 nonce = polymerCCTP.bridgeUSDC{value: msg.value}(
            _bridgeData.minAmount,
            _polymerData.destinationDomain,
            mintRecipient
        );
        
        // Emit Li.Fi standard event
        emit LiFiTransferStarted(
            BridgeData(
            _bridgeData.transactionId,
            _bridgeData.bridge,
            _bridgeData.integrator,
            _bridgeData.referrer,
            _bridgeData.sendingAssetId,
            _bridgeData.receiver,
            _bridgeData.minAmount,
            _bridgeData.destinationChainId,
            _bridgeData.hasSourceSwaps,
            _bridgeData.hasDestinationCall
            )
        );
        
        // Emit Polymer-specific event for tracking
        emit PolymerCCTPBridgeStarted(
            _bridgeData.transactionId,
            _polymerData.destinationDomain,
            mintRecipient,
            _bridgeData.minAmount,
            nonce
        );
    }
}
