// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

struct PolymerCCTPData{
    uint32 minFinalityThreshold; // minFinalityThreshold - currently used to decide whether or not to use fast path 
    uint32 maxFee; // max fee pased onto cctp's tokenMessenger
}

interface IPolymerCCTP {
    function bridgeUSDC(uint256 amount, PolymerCCTPData calldata destinationDomain) external payable;

    function usdc() external view returns (address);
}