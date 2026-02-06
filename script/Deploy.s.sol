// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {Attacker} from "../src/Attacker.sol";

/// @notice Deploy the Attacker contract to Sepolia.
///         Usage:
///           forge script script/Deploy.s.sol --rpc-url sepolia --broadcast
contract DeployAttacker is Script {
    // Default victim: OWASP Juice Shop Sepolia contract
    address constant VICTIM = 0x413744D59d31AFDC2889aeE602636177805Bd7b0;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        Attacker attacker = new Attacker(VICTIM);

        vm.stopBroadcast();

        console.log("Attacker deployed at:", address(attacker));
        console.log("Victim target:", VICTIM);
    }
}
