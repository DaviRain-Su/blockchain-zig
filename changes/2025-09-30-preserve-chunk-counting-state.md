# 2025-09-30 – Preserve chunk counting state

## Summary
- Added a reusable `Counter` type that keeps track of in-flight word and line state while aggregating statistics.
- Updated `countFromSlice` to reuse the streaming counter and expanded the test suite to cover UTF-8 text and cross-chunk boundary cases.
- Switched the CLI flow to iterate file chunks through the shared counter so long lines and words spanning buffers are counted accurately.

## Details
- `src/root.zig`: Introduced `Counter` with `process`/`finish` methods, ensured `countFromSlice` uses it, and added targeted unit tests (state carry-over, long lines, UTF-8 characters).
- `src/main.zig`: Replaced manual per-chunk accumulation with the `Counter` to reuse library logic and ensure consistent metrics.
- Tests: `zig test src/root.zig` and `zig test src/main.zig` both pass after the refactor.

## Follow-up Ideas
- Explore exposing configuration for default chunk sizes to the CLI.
- Consider documenting the CLI flags and usage in a dedicated README section.
