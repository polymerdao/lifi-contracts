// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console2} from "forge-std/Script.sol";
import {LiFiDiamond} from "lifi/LiFiDiamond.sol";
import {PolymerCCTPFacet} from "lifi/Facets/PolymerCCTPFacet.sol";
import {ILiFi} from "lifi/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi/Libraries/LibSwap.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PolymerCCTP} from "lifi/Facets/PolymerCCTP.sol";
import {PolymerCCTPData} from "lifi/Interfaces/IPolymerCCTP.sol";

contract CallPolymerCCTPFacet is Script {
    function run() external payable {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address diamondAddress = vm.envAddress("DIAMOND_ADDRESS");
        uint32 destinationDomain = uint32(vm.envUint("DESTINATION_DOMAIN"));
        address receiver = vm.addr(deployerPrivateKey);
        uint256 amount = uint256(1000);
        uint32 maxCCTPFee = uint32(vm.envOr("MAX_CCTP_FEE", uint256(100)));

        vm.startBroadcast(deployerPrivateKey);

        // Cast diamond to PolymerCCTPFacet to call its functions
        PolymerCCTPFacet polymerFacet = PolymerCCTPFacet(diamondAddress);

        // Get USDC address from the PolymerCCTPFacet
        address usdcAddress = vm.envAddress("USDC");
        console2.log("USDC address:", usdcAddress);

        // Approve USDC spending
        IERC20(usdcAddress).approve(diamondAddress, amount);

        // Prepare bridge data
        ILiFi.BridgeData memory bridgeData = ILiFi.BridgeData({
            transactionId: bytes32(uint256(1)), // Simple transaction ID
            bridge: "PolymerCCTP",
            integrator: "LiFi",
            referrer: address(0),
            sendingAssetId: usdcAddress,
            receiver: receiver,
            minAmount: amount,
            destinationChainId: uint256(destinationDomain), // Using domain as chain ID for simplicity
            hasSourceSwaps: false,
            hasDestinationCall: false
        });

        // Prepare Polymer-specific data
        PolymerCCTPData memory polymerData = PolymerCCTPData({
            destinationDomain: destinationDomain,
            mintRecipient: receiver,
            polymerTokenFee: 0,
            minFinalityThreshold: 0,
            maxCCTPFee: maxCCTPFee
        });

        console2.log("Calling startBridgeTokensViaPolymerCCTP...");
        console2.log("Amount:", amount);
        console2.log("Destination Domain:", destinationDomain);
        console2.log("Receiver:", receiver);

        // Call the bridge function
        polymerFacet.startBridgeTokensViaPolymerCCTP{value: msg.value}(bridgeData, polymerData);

        console2.log("Bridge transaction initiated successfully");

        vm.stopBroadcast();
    }

}
