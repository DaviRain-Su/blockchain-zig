# blockchain-zig

## Overview
- Command-line utility inspired by `wc` that reports line, word, byte, character, and max-line-length statistics.
- Core counting logic is packaged as a reusable Zig module so other executables can embed it.
- Includes a running change log under `changes/` describing notable refactors.

## Features
- Flags: `-l` lines, `-w` words, `-c` bytes, `-m` UTF-8 characters, `-L` maximum line length; defaults to `-lwc` when no flag is provided.
- Reads from files or standard input (`-` to force stdin) and aggregates totals across multiple inputs.
- Adaptive benchmarking hook prints elapsed time per chunk size to help tune performance.
- UTF-8 aware counting that preserves state across read chunks.

## Project Layout
- `src/main.zig` – CLI entry point that parses flags, handles I/O, and prints results.
- `src/root.zig` – Library exports (`Stats`, `Counter`, helpers) plus comprehensive unit tests.
- `build.zig` / `build.zig.zon` – Build configuration and dependency manifest.
- `changes/` – Markdown summaries of significant iterations (e.g., `changes/2025-09-30-preserve-chunk-counting-state.md`).
- `solana/` – Companion Rust tooling:
  - `solana/docs/` – Notes on Solana accounts (both Chinese and English).
  - `solana/solana-cli/` – Experimental Rust CLI with its own `Cargo` project.
- `zig-out/` – Build artifacts (`zig-out/bin/blockchain_zig` after `zig build`).

## Build & Run
- Build and install locally: `zig build`
- Run the CLI via build runner: `zig build run -- <flags> <files>`
- Example: `zig build run -- -lc src/main.zig`
- Run directly from source during development: `zig run src/main.zig -- <flags> <files>`

## Testing
- Execute all declared tests: `zig build test`
- Focus on library tests: `zig test src/root.zig`
- Focus on CLI tests (if present): `zig test src/main.zig`

## Contributing Notes
- Stick to ASCII unless a file already uses UTF-8 literals.
- Prefer `std.testing` for new coverage; leverage the `Counter` helper for streaming scenarios.
- Document noteworthy changes by adding a dated Markdown file under `changes/`.
