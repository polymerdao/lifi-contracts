// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

struct PolymerCCTPData {
    uint256 tokenFee;
    address mintRecipient;
    uint32 destinationDomain;
    uint32 minFinalityThreshold;
}

interface IPolymerCCTP {
    function bridgeUSDC(uint256 amount, PolymerCCTPData calldata destinationDomain) external payable;

    function usdc() external view returns (address);
}