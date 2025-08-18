// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IPolymerCCTP {
    function bridgeUSDC(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient
    ) external payable returns (uint64 nonce);
    
    function calculateFee(uint256 amount, uint32 domain) external view returns (uint256);
    
    function usdc() external view returns (address);
}