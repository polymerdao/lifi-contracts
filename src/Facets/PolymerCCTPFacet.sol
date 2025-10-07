// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {PolymerCCTPData} from "../Interfaces/IPolymerCCTP.sol";
import {ILiFi} from "../Interfaces/ILiFi.sol";
import {ITokenMessenger} from "../Interfaces/ITokenMessenger.sol";
import {IPolymerCCTP, PolymerCCTPData} from "../Interfaces/IPolymerCCTP.sol";

import {LibAsset, IERC20} from "../Libraries/LibAsset.sol";
import {LibSwap} from "../Libraries/LibSwap.sol";
import {SwapperV2} from "../Helpers/SwapperV2.sol";
import {Validatable} from "../Helpers/Validatable.sol";

/// @title PolymerCCTPFacet
/// @author LI.FI (https://li.fi)
/// @notice Provides functionality for bridging USDC through Polymer CCTP
/// @custom:version 1.0.0
contract PolymerCCTPFacet is ILiFi, ReentrancyGuard, SwapperV2, Validatable {
    ITokenMessenger public immutable tokenMessenger;
    address public immutable usdc;

    constructor(address _tokenMessenger, address _usdc) {
        // TODO: Do we want to have fee collector here?

        require(_tokenMessenger != address(0), "Invalid token messenger");
        require(_usdc != address(0), "Invalid USDC address");

        tokenMessenger = ITokenMessenger(_tokenMessenger);
        usdc = _usdc;
    }

    /// @notice Bridges USDC via PolymerCCTP
    /// @param _bridgeData The core bridge data
    /// @param _polymerData Data specific to PolymerCCTP
    function startBridgeTokensViaPolymerCCTP(ILiFi.BridgeData memory _bridgeData, PolymerCCTPData calldata _polymerData)
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
        _bridgeData.minAmount =
            _depositAndSwap(_bridgeData.transactionId, _bridgeData.minAmount, _swapData, payable(msg.sender));

        _startBridge(_bridgeData, _polymerData);
    }

    /// Private Methods ///

    /// @dev Performs the actual bridging logic
    /// @param _bridgeData The core bridge data
    /// @param _polymerData Data specific to PolymerCCTP
    function _startBridge(ILiFi.BridgeData memory _bridgeData, PolymerCCTPData memory _polymerData) private {

        // TODO: Do we need this check if it's always going to be usdc? 
        if (!LibAsset.isNativeAsset(_bridgeData.sendingAssetId)) {
            LibAsset.depositAsset(_bridgeData.sendingAssetId, _bridgeData.minAmount);
        }

        // TODO - is it worth validating the integrator and bridge from the bridgeData here?
        require(_bridgeData.minAmount > 0, "Invalid amount");
        require(_bridgeData.receiver != address(0), "Invalid recipient");

        // IERC20(usdc).transferFrom(msg.sender, address(this), _bridgeData.minAmount);


        // TODO we don't need to use safe approve here?  
        IERC20(usdc).approve(address(tokenMessenger), _bridgeData.minAmount);

        // Need tocheck: can we just use destinationChainID as the normal chain id? and can we just mpass in min Amount as the amountT?
        tokenMessenger.depositForBurn(
            _bridgeData.minAmount,
            uint32(_bridgeData.destinationChainId),
            bytes32(uint256(uint160(_bridgeData.receiver))),
            usdc,
            bytes32(0), // Unrestricted caller
            _polymerData.maxFee, // maxFee - 0 means no fee limit
            _polymerData.minFinalityThreshold // minFinalityThreshold - use default
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
    }
}
