# Juice Shop Wallet Depletion

Reentrancy exploit against the [OWASP Juice Shop](https://owasp.org/www-project-juice-shop/) Web3 wallet challenge on the Ethereum Sepolia testnet.

### Contributor
- [0x11semprez](https://github.com/0x11semprez)

---

## Table of Contents
1. [Methodology](#1-methodology)
2. [Exploit Design](#2-exploit-design)
3. [V2 — Improved Contract & Extended Exploits](#3-v2--improved-contract--extended-exploits)
4. [Business Impact](#4-business-impact)
5. [Remediation](#5-remediation)
6. [Evidence & Aftermath](#6-evidence--aftermath)
7. [Project Structure & Usage](#7-project-structure--usage)

---

## 1) Methodology

1. **Recon / enumeration**
   - Figured out our point of entry would be the new web 3 wallet accessible from ![Wallet](/WD/WD-0.png) ![1](/WD/WD-1.png)
   - **Target :** Juice Shop Sepolia testnet smart contract (victim) found in the source code : `0x413744D59d31AFDC2889aeE602636177805Bd7b0`.

---

### Vulnerable Code Flow
```solidity
function withdraw(uint256 _amount) {
    // 1. Check (balance sufficient)
    require(balances[caller] >= _amount);

    // 2. Fake "guard" (incremented but reset later)
    unknownac7ea680[caller]++;

    // 3. INTERACTION (external call BEFORE state update)
    call.value(_amount)(caller);

    // 4. EFFECT (state update happens LAST)
    balances[caller] -= _amount;

    // 5. Guard reset (too late)
    unknownac7ea680[caller] = 0;
}
```

---

## 2) Exploit Design

### Original Attack (v1)

[Wrote and deployed a contract on the Sepolia ETH testnet to exploit a reentrancy vulnerability within the juice shop contract.](https://github.com/Keuchnotkush/Juice-Shop-Wallet-Depletion/blob/main/attack.sol)

#### How It Works

1. **Deposit ETH**
   - Calls the victim's `deposit` function to establish a balance for the attack.

2. **Trigger Withdrawal**
   - Calls the victim's `withdraw` function to start the exploit.

3. **Re-enter Withdrawal**
   - The `fallback` function is triggered during the victim's ETH transfer.
   - It recursively calls `withdraw` before the victim updates my balance, draining its funds.

4. **Withdraw Stolen ETH**
   - Finally, sends the stolen ETH to my wallet.

#### Victim's Flaw

The victim contract violates the **Checks-Effects-Interactions** pattern by:
- Sending ETH **before** updating the balance.
- Using an ineffective reentrancy guard (`unknownac7ea680`) that resets too late.

This makes it vulnerable to reentrancy attacks.

#### Vulnerability Severity
- **Critical** : Possible drain of all funds of the target contract.

---

#### Exploit Execution
- Deposited `0.1 ETH` into the victim (to initialize attacker balance in the victim's mapping).
- Triggered `exploit(1000000000000000000 WEI)` and re-entered 13 times to drain a total of `2.5 ETH`.

#### Validation
- Verified attacker contract balance and transaction outcomes on Sepolia block explorer.
- Confirmed that on the platform instance the challenge endpoint responded `200 OK`.

### Techniques Used
- Smart-contract recon & bytecode/decompiler review
- Reentrancy exploitation (recursive external calls via fallback/receive)
- Transaction verification & basic on-chain forensics (balances, blocks, tx hash)

### Tools Used
- **Remix IDE** (compile/deploy/call contracts)
- **Phantom** (Web3 wallet & signing)
- **Sepolia testnet faucet** (funding)
- **Etherscan (Sepolia)** (transaction & contract inspection)
- **Browser DevTools** (platform API observation)

---

## 3) V2 — Improved Contract & Extended Exploits

The original `attack.sol` was rewritten with bug fixes, a proper Foundry framework, full test coverage, and an extended multi-contract attack vector.

### Bugs Fixed

| # | Issue | Before | After |
|---|-------|--------|-------|
| 1 | Reentry depth | `attackCount < 2` — only 1 reentry | Balance-based + gas-guarded termination — drains until victim is empty |
| 2 | Amount mismatch | `fallback()` hardcoded `0.1 ether`, `exploit(amount)` used a different value | `withdrawAmount` stored in state, used by both `exploit()` and `_reenter()` |
| 3 | ETH forwarding | `transfer()` with 2300 gas stipend | `.call{value:}("")` — no gas limit |
| 4 | Raw selectors | Magic numbers `0x2e1a7d4d`, `0x22c33cb3` | `IVictim` interface with typed calls |
| 5 | No observability | Silent execution | Events: `Deposited`, `ExploitStarted`, `Reentry`, `ExploitCompleted`, `Withdrawn` |
| 6 | Hardcoded victim | No reconfiguration | `setVictim()` with owner guard |
| 7 | `receive()` vs `fallback()` | Only `fallback()` — missed empty-calldata ETH transfers | Both `receive()` and `fallback()` route to `_reenter()` |

### Improved Attack Flow

```
depositToVictim()          exploit(amount)                     withdraw()
      │                         │                                  │
      ▼                         ▼                                  ▼
 ┌─────────┐             ┌─────────────┐                    ┌───────────┐
 │ Deposit  │             │  withdraw() │◄──┐               │ Send ETH  │
 │ into     │             │  on victim  │   │               │ to owner  │
 │ victim   │             └──────┬──────┘   │               │ EOA       │
 └─────────┘                     │          │               └───────────┘
                          victim sends ETH  │
                                 │          │
                          ┌──────▼──────┐   │
                          │ _reenter()  │   │  balance-based
                          │ checks:     │   │  recursion
                          │ balance >= ? ├───┘
                          │ gas > 50k?  │
                          └─────────────┘
```

### Extended Exploit: Multi-Contract Relay (`AttackerFactory`)

The `AttackerFactory` defeats **per-address reentrancy guards** by deploying multiple `Attacker` clones. Each clone is a unique `msg.sender` from the victim's perspective, so the guard mapping (`unknownac7ea680[caller]`) tracks them separately.

```
AttackerFactory
      │
      ├── deployClones(5)
      │     ├── Attacker #0  (unique msg.sender)
      │     ├── Attacker #1
      │     ├── Attacker #2
      │     ├── Attacker #3
      │     └── Attacker #4
      │
      ├── fundAndExploit(0.1 ether)  ──▶  each clone deposits + drains
      │
      ├── collectAll()               ──▶  pull ETH from all clones
      │
      └── withdraw()                 ──▶  send to owner EOA
```

### Test Results

```
forge test -vv

Ran 14 tests for test/Attacker.t.sol
├── AttackerTest
│   ├── [PASS] test_fullDrain          — 0.1 ETH deposit drains 2.6 ETH (26 reentries)
│   ├── [PASS] test_partialDrain       — partial drain with remainder
│   ├── [PASS] test_depositAndExploit  — single-tx convenience function
│   ├── [PASS] test_withdrawToOwner    — stolen ETH reaches owner
│   ├── [PASS] test_exploitEmptyVictim — edge case: no extra funds to drain
│   ├── [PASS] test_onlyOwner_exploit  — access control
│   ├── [PASS] test_onlyOwner_withdraw — access control
│   ├── [PASS] test_onlyOwner_deposit  — access control
│   ├── [PASS] test_setVictim          — reconfiguration
│   ├── [PASS] test_setVictim_rejectsZero
│   └── [PASS] test_eventEmission      — forensic events
│
└── AttackerFactoryTest
    ├── [PASS] test_deployClones       — factory deploys n clones
    ├── [PASS] test_multiCloneDrain    — 5 clones drain 5.5 ETH total
    └── [PASS] test_onlyOwner_factory  — access control

14 tests passed, 0 failed
```

---

## 4) Business Impact

- **Permanent financial loss:** immediate theft of wallet/treasury funds (can drain contract balance quickly).
- **Service disruption:** contract becomes insolvent; legitimate users can't withdraw.
- **Reputation & trust damage:** public exploit harms long-term credibility and user retention.
- **Compliance / legal exposure:** potential reporting obligations and disputes if real funds are affected.

---

## 5) Remediation

### Fixes
- Apply **Checks-Effects-Interactions**: update balances **before** any external call.
- Add a **reentrancy guard** (OpenZeppelin `ReentrancyGuard` pattern).
- Prefer **pull-payments** pattern (users withdraw from their own balance; avoid complex external calls in the same function).

### Best Practices
- Unit/integration tests covering reentrancy cases (including adversarial tests).
- Automated static analysis & security scanning in CI (e.g., Slither-style checks).
- External code review / audit for contracts that hold value.
- Monitoring & incident response playbook (alerts on abnormal withdrawals).

---

## 6) Evidence & Aftermath
![2](/WD/WD-2.png)
![3](/WD/WD-3.png)
![4](/WD/WD-4.png)
![5](/WD/WD-5.png)
![6](/WD/WD-6.png)
![7](/WD/WD-7.png)

- Everything can be found on-chain at : `0x1F0db224880Dcd7dAc8fedB0fb01Be9041bF7929`

### Outcome Summary
- Initial deposit: `0.1 ETH`
- Total withdrawn: `2.6 ETH`
- Net gain: `2.5 ETH` (**2400%** over deposit)

---

## 7) Project Structure & Usage

```
├── src/
│   ├── Attacker.sol              # Improved reentrancy exploit contract
│   ├── AttackerFactory.sol       # Multi-clone attack (defeats per-address guards)
│   └── interfaces/
│       └── IVictim.sol           # Typed interface for the victim contract
│
├── test/
│   ├── Attacker.t.sol            # 14 Foundry tests (drain, access control, events, factory)
│   └── mocks/
│       └── MockVictim.sol        # Local replica of the vulnerable contract
│
├── script/
│   ├── Deploy.s.sol              # Deploy Attacker to Sepolia
│   └── Exploit.s.sol             # Full attack sequence: deposit → exploit → withdraw
│
├── WD/                           # Evidence screenshots (WD-0 through WD-7)
├── attack.sol                    # Original v1 exploit (preserved for reference)
├── foundry.toml                  # Foundry configuration
└── .env.example                  # RPC & key template
```

### Quick Start

```bash
# Install Foundry (if needed)
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Build
forge build

# Run tests locally (no network needed)
forge test -vvvv

# Deploy to Sepolia
cp .env.example .env  # fill in your keys
source .env
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast

# Execute the exploit
forge script script/Exploit.s.sol --rpc-url sepolia --broadcast \
  --sig "run(address)" <ATTACKER_ADDRESS>
```

---

**License:** MIT
