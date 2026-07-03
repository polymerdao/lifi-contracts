// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.17;

import { Script, console2 } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { LiFiDiamond } from "lifi/LiFiDiamond.sol";
import { DiamondCutFacet } from "lifi/Facets/DiamondCutFacet.sol";
import { PolymerCCTPFacet } from "lifi/Facets/PolymerCCTPFacet.sol";
import { LibDiamond } from "lifi/Libraries/LibDiamond.sol";

/// @notice Standalone testnet/shadownet deploy of a fresh diamond with PolymerCCTPFacet.
/// @dev Reads everything from config/polymercctp.testnet.json's `.testnets` block, keyed by chainId:
///      - constructor args for the current chain (via block.chainid)
///      - the full chainId -> CCTP domain mapping seeded at init (all testnet entries)
///      This is separate from the production path (DeployPolymerCCTPFacet + UpdatePolymerCCTPFacet),
///      which uses the network-name-keyed entries and the upstream `.mappings` array.
contract DeployDiamondWithPolymerCCTPFacet is Script {
    using stdJson for string;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        string memory json = vm.readFile(
            string.concat(vm.projectRoot(), "/config/polymercctp.testnet.json")
        );
        string memory chainKey = string.concat(
            ".testnets.",
            vm.toString(block.chainid)
        );

        // Constructor args for the chain we are deploying to
        address tokenMessenger = json.readAddress(
            string.concat(chainKey, ".tokenMessengerV2")
        );
        address usdc = json.readAddress(string.concat(chainKey, ".usdc"));
        address polymerFeeRecipient = json.readAddress(
            string.concat(chainKey, ".polymerFeeReceiver")
        );

        // chainId -> CCTP domain mappings seeded at init time (v2.1.0+)
        PolymerCCTPFacet.ChainIdConfig[] memory chainIdConfigs = _readMappings(
            json
        );

        vm.startBroadcast(deployerPrivateKey);

        // Deploy DiamondCutFacet
        console2.log("Using token messenger", tokenMessenger);
        console2.log("Deploying DiamondCutFacet...");
        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
        console2.log("DiamondCutFacet deployed at:", address(diamondCutFacet));

        // Deploy LiFiDiamond
        console2.log("Deploying LiFiDiamond...");
        LiFiDiamond diamond = new LiFiDiamond(
            vm.addr(deployerPrivateKey),
            address(diamondCutFacet)
        );
        console2.log("LiFiDiamond deployed at:", address(diamond));

        // Deploy PolymerCCTPFacet
        console2.log("Deploying PolymerCCTPFacet...");
        PolymerCCTPFacet polymerCCTPFacet = new PolymerCCTPFacet(
            tokenMessenger,
            usdc,
            polymerFeeRecipient
        );
        console2.log(
            "PolymerCCTPFacet deployed at:",
            address(polymerCCTPFacet)
        );

        // Add PolymerCCTPFacet to diamond
        console2.log("Adding PolymerCCTPFacet to diamond...");
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = PolymerCCTPFacet
            .startBridgeTokensViaPolymerCCTP
            .selector;
        selectors[1] = PolymerCCTPFacet
            .swapAndStartBridgeTokensViaPolymerCCTP
            .selector;
        selectors[2] = PolymerCCTPFacet.initPolymerCCTP.selector;
        selectors[3] = PolymerCCTPFacet.setChainIdToDomainId.selector;
        selectors[4] = PolymerCCTPFacet.unsetChainIdToDomainId.selector;
        selectors[5] = PolymerCCTPFacet.getChainIdToDomainId.selector;

        LibDiamond.FacetCut[] memory cuts = new LibDiamond.FacetCut[](1);
        cuts[0] = LibDiamond.FacetCut({
            facetAddress: address(polymerCCTPFacet),
            action: LibDiamond.FacetCutAction.Add,
            functionSelectors: selectors
        });

        DiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");
        console2.log("PolymerCCTPFacet successfully added to diamond");

        // init now also seeds the chainId -> CCTP domain mappings
        PolymerCCTPFacet(address(diamond)).initPolymerCCTP(chainIdConfigs);
        console2.log(
            "PolymerCCTPFacet initialized with",
            chainIdConfigs.length,
            "chain mappings"
        );

        vm.stopBroadcast();
    }

    /// @dev Builds the ChainIdConfig[] from every entry in the `.testnets` block.
    function _readMappings(
        string memory json
    ) internal pure returns (PolymerCCTPFacet.ChainIdConfig[] memory) {
        string[] memory chainIds = vm.parseJsonKeys(json, ".testnets");
        PolymerCCTPFacet.ChainIdConfig[]
            memory configs = new PolymerCCTPFacet.ChainIdConfig[](
                chainIds.length
            );

        for (uint256 i = 0; i < chainIds.length; ) {
            configs[i].chainId = vm.parseUint(chainIds[i]);
            configs[i].domainId = uint32(
                json.readUint(
                    string.concat(".testnets.", chainIds[i], ".domainId")
                )
            );
            unchecked {
                ++i;
            }
        }

        return configs;
    }
}
