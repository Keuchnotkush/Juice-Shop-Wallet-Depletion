// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title MockVictim
/// @notice Replicates the OWASP Juice Shop vulnerable contract for local testing.
/// @dev    Intentionally vulnerable — violates Checks-Effects-Interactions:
///           1. Checks balance
///           2. Increments a "guard" (useless — resets at end)
///           3. Sends ETH via external call (INTERACTION before EFFECT)
///           4. Updates balance (too late — reentrant call already drained)
///           5. Resets guard (never reached during reentry)
contract MockVictim {
    mapping(address => uint256) public balances;
    mapping(address => uint256) private guard;

    /// @notice Deposit ETH for a given beneficiary.
    function deposit(address _for) external payable {
        balances[_for] += msg.value;
    }

    /// @notice Withdraw ETH — VULNERABLE to reentrancy.
    /// @dev    Matches the real Juice Shop contract which uses the old
    ///         call.value() pattern WITHOUT checking the return value.
    ///         This is critical: if the deepest reentrant call runs out
    ///         of gas, it silently fails instead of cascading a revert.
    function withdraw(uint256 _amount) external {
        // 1. Check
        require(balances[msg.sender] >= _amount, "Insufficient balance");

        // 2. Fake guard (incremented but reset later — useless)
        guard[msg.sender]++;

        // 3. INTERACTION — external call BEFORE state update.
        //    Return value intentionally UNCHECKED (matches real victim).
        payable(msg.sender).call{value: _amount}("");

        // 4. EFFECT — balance updated AFTER the call (too late).
        //    unchecked: the real victim was compiled with Solidity <0.8
        //    (no overflow checks).  During reentry the balance has already
        //    been drained, so this would underflow in 0.8+.
        unchecked {
            balances[msg.sender] -= _amount;
        }

        // 5. Guard reset — never reached during reentry
        guard[msg.sender] = 0;
    }

    /// @notice Fund the contract (simulates other users' deposits).
    receive() external payable {}
}
