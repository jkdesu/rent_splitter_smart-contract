# RentSplitter

Blockchain-based rent collection prototype for **APANPS5470**. Roommates pay their share into a Solidity escrow; the contract sends ETH to the landlord only when everyone has paid. If someone never pays, the landlord can refund the people who did.

This repo is the smart-contract prototype for a rent-splitting product concept (custodial vs. non-custodial wallets, KYC, and automated monthly payments).

## Features

- Split total rent across roommate wallets (shares must sum to `totalRent`)
- Hold payments in escrow until the cycle is complete
- Auto-release funds to the landlord when every roommate has paid
- 30-day due date, 3-day grace period, then a 5% late fee
- Landlord-triggered refunds after the grace period if the cycle fails
- Automatic reset into the next 30-day cycle

## How it works

```text
Deploy (landlord)
    │
Active / Pending  ── roommates call payRent()
    │
    ├─ all paid on time     → ETH to landlord → next cycle
    ├─ past due date        → GracePeriod (3 days, no extra fee)
    └─ after grace period
           ├─ pay now       → share + 5% late fee
           ├─ all paid      → ETH to landlord (including fees) → next cycle
           └─ someone missing → landlord triggerRefund() → payers reimbursed → next cycle
```

**Roles**

| Role | Who | Can call |
| --- | --- | --- |
| Landlord | Address that deploys the contract | `triggerRefund`, `emergencyPause` |
| Roommate | Addresses passed into the constructor | `payRent` |
| Anyone | — | View functions (`checkAllPaid`, `currentPhase`, balances, …) |

## Project file

- [`RENT_SPLITTER.sol`](./RENT_SPLITTER.sol) — `RentSplitter` contract (`pragma solidity ^0.8.19`)
- GitHub: [jkdesu/rent_splitter_smartcontract](https://github.com/jkdesu/rent_splitter_smartcontract)

## Run in Remix

You cannot run a `.sol` file like a script. Compile it, deploy it to Remix VM, then call functions.

1. Open [Remix](https://remix.ethereum.org).
2. Create a file named `RentSplitter.sol` and paste the contract.
3. **Solidity Compiler** → compiler **0.8.19** (or any 0.8.x) → **Compile**.
4. **Deploy & Run** → Environment **Remix VM**.
5. The selected account is the **landlord**. Do not put this address in the roommate list.
6. Fill the constructor, then **Deploy**.

### Constructor example

Use two Remix accounts other than the landlord. Paste full 42-character addresses.

`_totalRent` (3 ETH in wei)

```text
3000000000000000000
```

`_roommateAddresses`

```text
["0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2", "0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db"]
```

`_rentShares` (1 ETH + 2 ETH)

```text
[1000000000000000000, 2000000000000000000]
```

Rules Remix will enforce:

- Both arrays must be the same length
- Shares must add up to `_totalRent`
- Addresses must be wrapped in `[...]` (this is an `address[]`, not a single string)

Leave **Value** at `0` for deploy. A successful deploy only spends a small gas fee from the landlord.

### Collect rent

1. Switch the account dropdown to roommate 1.
2. Set **Value** to `1 ether` (not wei).
3. Click **Transact** on `payRent`.
4. Switch to roommate 2, set **Value** to `2 ether`, call `payRent` again.

When the last roommate pays, the contract sends the pot to the landlord. Check the landlord balance before and after.

`payRent` is payable. If Value is `0`, the call reverts with `Insufficient payment amount`.

## Main functions

| Function | Type | Description |
| --- | --- | --- |
| `payRent()` | Roommate, payable | Pay this cycle’s share (plus 5% if past grace period). Excess ETH is returned. |
| `triggerRefund()` | Landlord | After due date + 3 days, if someone has not paid, refund everyone who did. |
| `emergencyPause()` | Landlord | Sets phase to `Setup` (does not currently block `payRent`). |
| `checkAllPaid()` | View | `true` if every roommate has paid this cycle. |
| `getRoommateDetails(address)` | View | Share, paid flag, escrow, late flag. |
| `getContractBalance()` | View | ETH currently held by the contract. |
| `getTimeUntilDue()` | View | Seconds until due date (`0` if overdue). |
| `isInGracePeriod()` | View | Between due date and due date + 3 days. |
| `currentPhase` / `currentStatus` / `cycleNumber` | View | Cycle state machine. |

Orange Remix buttons send a transaction. Blue buttons only read state.

## Cycle parameters

| Parameter | Value |
| --- | --- |
| Due date | `block.timestamp + 30 days` at deploy / reset |
| Grace period | 3 days |
| Late fee | 5% of that roommate’s share, after grace period |
| Release rule | All registered roommates must have `hasPaid == true` |

## Product direction (beyond this prototype)

The contract is the on-chain core of a broader rent-splitting product:

- Custodial and non-custodial wallet support
- KYC for landlords and tenants
- Automated monthly rent collection on this escrow lifecycle

## Notes for testers

- Send **exact** shares when possible. Overpayment refunds extra ETH, but `totalCollected` accounting is incorrect if `msg.value` is above the required amount.
- Remix VM time does not advance 30 days on its own. To hit grace / late / refund paths, use Remix’s **vm.warp** / block-time tools, or treat those as code-path reviews rather than same-session demos.
- Duplicate roommate addresses are not rejected in the constructor.

## License

MIT (`SPDX-License-Identifier: MIT` in the contract).
