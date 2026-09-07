# Common tasks. Install `just`: https://github.com/casey/just
# Run `just` with no args to list recipes.

set dotenv-load := true

_default:
    @just --list

# Install / update git submodule dependencies.
install:
    git submodule update --init --recursive

# Compile contracts.
build:
    forge build --sizes

# Run the test suite.
test *args:
    forge test {{args}}

# Run tests with traces on failure.
test-v:
    forge test -vvv

# Format sources.
fmt:
    forge fmt

# Check formatting (CI parity).
fmt-check:
    forge fmt --check

# Full local gate — run before every commit.
check: fmt-check build test

# Gas snapshot (writes .gas-snapshot).
snapshot:
    forge snapshot

# Fail if gas changed vs the committed snapshot.
snapshot-check:
    forge snapshot --check

# Coverage summary.
coverage:
    forge coverage --report summary

# Static analysis (needs `slither`: pipx install slither-analyzer).
slither:
    slither .

# Rebuild the graphify code graph.
graph:
    graphify update .

# Remove build artifacts.
clean:
    forge clean
