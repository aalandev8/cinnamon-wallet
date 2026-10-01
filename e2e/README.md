# E2E: real bundler flow

Runs the MVP against a real ERC-4337 bundler ([Alto](https://github.com/pimlicolabs/alto)) on a local anvil chain,
using a [viem](https://viem.sh) `SmartAccount` adapter (`src/cinnamonAccount.ts`).

```bash
pnpm install
pnpm e2e
```

`run.sh` starts anvil, deploys the official EntryPoint 0.8 artifact at its canonical address
(`0x4337084D…Ff108`, via the deterministic deployer), deploys the MVP contracts with `script/Deploy.s.sol`,
starts Alto and runs `src/e2e.ts`:

1. The first UserOperation deploys the counterfactual account (ECDSA root validator + spending limit hook) and
   transfers ETH.
2. A batch UserOperation executes every call.
3. A UserOperation over the daily limit is rejected by the bundler during simulation.

Notes:

- Alto detects EntryPoint 0.8 by address prefix, so a non-canonical EntryPoint is simulated as v0.7.
- Alto runs with `--safe-mode false`, so ERC-7562 validation rules are not enforced in this local run.
