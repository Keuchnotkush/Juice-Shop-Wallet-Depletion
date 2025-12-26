### CONTRIBUTOR 
- [0x11semprez](https://github.com/0x11semprez)

### 1) Methodology

1. **Recon / enumeration**
   - Figured out our point of entry would be the new web 3 wallet accessible from ![Wallet](/WD/WD-0.png) ![1](/WD/WD-1.png)
   - **Target :** Juice Shop Sepolia testnet smart contract (victim) at found in the source code : `0x413744D59d31AFDC2889aeE602636177805Bd7b0`.

---
### **Vulnerable Code Flow**
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

### 2. **Exploit design**
   ![Wrote and deployed a contract on the Sepolia ETH testnet to exploit a reetrancy           
   vulnerability within the juice shop contract.](https://github.com/Keuchnotkush/Juice-Shop-Wallet-Depletion/blob/main/attack.sol)
  # How It Works
  
  1. **Deposit ETH**
     - Calls the victim's `deposit` function to establish a balance for the attack.
  
  2. **Trigger Withdrawal**
     - Calls the victim's `withdraw` function to start the exploit.
  
  3. **Re-enter Withdrawal**
     - The `fallback` function is triggered during the victim's ETH transfer.
     - It recursively calls `withdraw` before the victim updates my balance, draining its funds.
  
  4. **Withdraw Stolen ETH**
     - Finally, sends the stolen ETH to my wallet.
  
  ## Victim's Flaw
  
  The victim contract violates the **Checks-Effects-Interactions** pattern by:
  - Sending ETH **before** updating the balance.
  - Using an ineffective reentrancy guard (`unknownac7ea680`) that resets too late.
  
  This makes it vulnerable to reentrancy attacks.
  
  ## Vulnerability Severity
  - **Critical**  : Possible drain of all funds of the target contract.
  ---

   **Exploit execution**
   - Deposited `0.1 ETH` into the victim (to initialize attacker balance in the victim’s mapping).
   - Triggered my `exploit(1000000000000000000 WEI)` and re‑entered 13 times to drain a total of `2.5 ETH`.
   
   **Validation**
   - Verified attacker contract balance and transaction outcomes on Sepolia block explorer.
   - Confirmed that on the platform instance the challenge endpoint responded `200 OK`

### Techniques used
- Smart‑contract recon & bytecode/decompiler review
- Reentrancy exploitation (recursive external calls via fallback/receive)
- Transaction verification & basic on‑chain forensics (balances, blocks, tx hash)

### Tools used
- **Remix IDE** (compile/deploy/call contracts)
- **Phantom** (Web3 wallet & signing)
- **Sepolia testnet faucet** (funding)
- **Etherscan (Sepolia)** (transaction & contract inspection)
- **Browser DevTools** (platform API observation)


---

## 4) Business impact

- **Permanent Financial loss:** immediate theft of wallet/treasury funds (can drain contract balance quickly).
- **Service disruption:** contract becomes insolvent; legitimate users can’t withdraw.
- **Reputation & trust damage:** public exploit harms long term credibility and user retention.
- **Compliance / legal exposure:** potential reporting obligations and disputes if real funds are affected.

---

## 5) Actions

### Remediation fixes
- Apply **Checks‑Effects‑Interactions**: update balances **before** any external call.
- Add a **reentrancy guard** (A trusted one is OpenZeppelin `ReentrancyGuard` pattern).
- Prefer **pull‑payments** pattern (users withdraw from their own balance; avoid complex external calls in the same function).

### Best practices
- Unit/integration tests covering reentrancy cases (including adversarial tests).
- Automated static analysis & security scanning in CI (e.g., Slither‑style checks).
- External code review / audit for contracts that hold value.
- Monitoring & incident response playbook (alerts on abnormal withdrawals).

---

## 6)  and aftermath :
![2](/WD/WD-2.png)
![3](/WD/WD-3.png)
![4](/WD/WD-4.png)
![5](/WD/WD-5.png)
![6](/WD/WD-6.png)
![7](/WD/WD-7.png)

- Everything can be found on-chain at : `0x1F0db224880Dcd7dAc8fedB0fb01Be9041bF7929`
  
### Outcome summary
- Initial deposit: `0.1 ETH`
- Total withdrawn: `2.6 ETH`
- Net gain: `2.5 ETH` (**2400%** over deposit)  

---
