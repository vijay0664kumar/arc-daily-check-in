# Arc Daily Check-In

> Built with Arc Studio - money-powered apps in minutes

This is the **project memory** - what Arc Studio remembers about building this app. It helps future agents (or humans) understand and extend the project.

---

## What This App Does

A fully onchain daily check-in dApp on Arc Testnet. Users connect their wallet and check in once per 24 hours. The contract tracks each wallet's total check-ins, current consecutive streak (resets if >48 h gap), and a public feed of the 100 most recent check-ins.

## Deployed Contract

- **Name**: ArcDailyCheckIn
- **Network**: Arc Testnet (Chain ID 5042002)
- **Address**: `0x6863584402f61ec2b00ce0d4ea36a2af8effa826`
- **Explorer**: https://explorer.testnet.arc.io/address/0x6863584402f61ec2b00ce0d4ea36a2af8effa826
- **Artifact**: `contracts/out/ArcDailyCheckIn.sol/ArcDailyCheckIn.json`

## Tech Stack

- Frontend: React 18, Vite, TypeScript, Tailwind CSS
- Web3: wagmi v2, viem v2, ConnectKit
- Contracts: Solidity 0.8.28 + Foundry. Sources in `contracts/`, unit tests in `contracts/test/*.t.sol`. Build with `bun run contracts:build` (`forge build`), test with `bun run contracts:test` (`forge test`).
- Wallet: injected (MetaMask, etc.)
- Chain: Arc Testnet (Chain ID: 5042002, imported from `viem/chains`)
- Token: USDC (6 decimals) (Address: 0x3600000000000000000000000000000000000000, Chain: Arc Testnet)
- Toasts: Sonner

## Key Files

- `src/App.tsx` - Main application logic
- `src/components/` - UI components
- `src/config.ts` - wagmi config (chains, connectors, transports)

## To Run

```bash
bun install
bun run dev
```
