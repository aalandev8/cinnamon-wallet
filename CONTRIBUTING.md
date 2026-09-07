# Contributing to cinnamon-wallet

This is a learning and portfolio project: a modular ERC-4337 / ERC-7579 smart
account built from first principles. Contributions are welcome, but the priority
is a **clear, minimal, well-tested Core** over feature count. Read
[`CLAUDE.md`](CLAUDE.md) and [`docs/architecture.md`](docs/architecture.md) before
opening a non-trivial change.

## Ground rules

- **Architecture decisions are explicit.** Anything that changes a frozen
  decision in `docs/architecture.md` or an ADR in `docs/decisions/` must be
  discussed in an issue first (use the *ADR proposal* template) and land as a new
  or superseding ADR in the same PR.
- **Strict TDD.** No production Solidity lands without a failing test written
  first. PRs that add contract code with no accompanying tests will be asked to
  add them before review.
- **Core vs modules.** Authorization and spend/target policy live in modules, not
  in the Core. If it is a *policy*, it is a module.
- **Reuse audited primitives.** Prefer OpenZeppelin and
  `eth-infinitism/account-abstraction` over re-implementing primitives.

## Development setup

```shell
# Foundry: https://book.getfoundry.sh/getting-started/installation
git clone https://github.com/aalandev8/cinnamon-wallet
cd cinnamon-wallet
git submodule update --init --recursive
forge build
forge test -vvv
```

All Solidity targets `0.8.28` / `evm_version = cancun`.

## Workflow

1. Open (or claim) an issue describing the change. For architecture-affecting
   work, get the direction agreed before writing code.
2. Branch off `main`. Never commit straight to `main` — it is protected.
   - Branch naming: `type/short-description`, e.g. `feat/ecdsa-validator`,
     `fix/nonce-key-routing`, `docs/hook-loop`, `chore/ci-slither`.
3. Write the failing test, make it pass, refactor.
4. Before pushing, make sure all three pass locally:
   ```shell
   forge fmt --check
   forge build
   forge test
   ```
5. Open a PR against `main`. Fill in the PR template. CI
   (`forge fmt --check` / `forge build` / `forge test`) must be green and the
   branch up to date with `main` before merge.
6. Keep history linear: merge is by **squash** or **rebase**, no merge commits.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/). Types in use:
`feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `ci`, `build`, `perf`.

```
feat(validator): add ECDSA root validator

Implements IValidator for the mandatory root slot (nonce key 0).
Signature recovery via OpenZeppelin ECDSA. Rejects zero owner.

Refs #12
```

Do not add `Co-Authored-By` or other AI-attribution trailers.

## Pull request expectations

- One logical change per PR. Split large work into reviewable slices.
- Tests included and passing; new behavior is covered.
- `docs/` and ADRs updated when the change touches architecture.
- The PR description explains **why**, not just what.
- Link the issue it closes (`Closes #NN`).

## Reporting bugs and security issues

- Functional bugs: open an issue with the *Bug report* template.
- Security vulnerabilities: **do not open a public issue.** See
  [`SECURITY.md`](SECURITY.md).

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By
participating you agree to uphold it.
