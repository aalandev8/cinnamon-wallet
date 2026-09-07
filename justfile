# Task runner — https://github.com/casey/just

set dotenv-load := true

_default:
    @just --list

install:
    git submodule update --init --recursive

build:
    forge build --sizes

test *args:
    forge test {{args}}

test-v:
    forge test -vvv

fmt:
    forge fmt

fmt-check:
    forge fmt --check

# pre-commit gate
check: fmt-check build test

snapshot:
    forge snapshot

snapshot-check:
    forge snapshot --check

coverage:
    forge coverage --report summary

# needs slither-analyzer
slither:
    slither .

graph:
    graphify update .

clean:
    forge clean
