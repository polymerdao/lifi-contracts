// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console2} from "forge-std/Script.sol";
import {LiFiDiamond} from "lifi/LiFiDiamond.sol";
import {DiamondCutFacet} from "lifi/Facets/DiamondCutFacet.sol";
import {PolymerCCTPFacet} from "lifi/Facets/PolymerCCTPFacet.sol";
import {IPolymerCCTP} from "lifi/Interfaces/IPolymerCCTP.sol";
import {DeployScriptBase} from "./utils/DeployScriptBase.sol";
import {LibDiamond} from "lifi/Libraries/LibDiamond.sol";

contract DeployDiamondWithPolymerCCTPFacet is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Read PolymerCCTP constructor arguments from environment
        address tokenMessenger = vm.envAddress("TOKEN_MESSENGER");
        address usdc = vm.envAddress("USDC");
        address guardian = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy DiamondCutFacet
        console2.log("Deploying DiamondCutFacet...");
        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
        console2.log("DiamondCutFacet deployed at:", address(diamondCutFacet));

        // Deploy LiFiDiamond
        console2.log("Deploying LiFiDiamond...");
        LiFiDiamond diamond = new LiFiDiamond(vm.addr(deployerPrivateKey), address(diamondCutFacet));
        console2.log("LiFiDiamond deployed at:", address(diamond));

        console2.log("Deploying PolymerCCTPFacet...");
        PolymerCCTPFacet polymerFacet = new PolymerCCTPFacet(tokenMessenger, usdc);
        console2.log("PolymerCCTPFacet deployed at:", address(polymerFacet));

        // Add PolymerCCTPFacet to diamond
        console2.log("Adding PolymerCCTPFacet to diamond...");
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = PolymerCCTPFacet.startBridgeTokensViaPolymerCCTP.selector;
        selectors[1] = PolymerCCTPFacet.swapAndStartBridgeTokensViaPolymerCCTP.selector;
        // selectors[2] = bytes4(keccak256("usdc()"));

        LibDiamond.FacetCut[] memory cuts = new LibDiamond.FacetCut[](1);
        cuts[0] = LibDiamond.FacetCut({
            facetAddress: address(polymerFacet),
            action: LibDiamond.FacetCutAction.Add,
            functionSelectors: selectors
        });

        DiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");
        console2.log("PolymerCCTPFacet successfully added to diamond");

        vm.stopBroadcast();
    }
}
