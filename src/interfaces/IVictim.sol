// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IVictim
/// @notice Interface for the OWASP Juice Shop vulnerable contract.
///         Function selectors derived from on-chain bytecode analysis:
///           deposit(address) => 0x22c33cb3
///           withdraw(uint256) => 0x2e1a7d4d
interface IVictim {
    function deposit(address _for) external payable;
    function withdraw(uint256 _amount) external;
}
