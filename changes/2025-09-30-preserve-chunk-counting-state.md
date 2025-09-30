# 2025-09-30 – Preserve chunk counting state

## Summary
- Added a reusable `Counter` that persists line and word state across chunks, eliminating double-counts when words or lines span buffer boundaries.
- Updated `countFromSlice` to reuse the streaming counter and expanded the test suite to cover UTF-8 input and cross-chunk boundary cases.
- Switched the CLI flow to iterate file chunks through the shared counter so long lines and words spanning buffers are counted accurately.

## Details
- `src/root.zig`: Introduced `Counter` with `process`/`finish` methods, ensured `countFromSlice` uses it, and added targeted unit tests (state carry-over, long lines, UTF-8 characters).
- `src/main.zig`: Replaced manual per-chunk accumulation with the `Counter` to reuse library logic and ensure consistent metrics.
- Tests: `zig test src/root.zig` and `zig test src/main.zig` both pass after the refactor.

## 原理解析
- 之前的实现每读取一个 `chunk` 就独立统计一次，导致同一个单词被拆在两个块时各自计数一次；`Counter.process` 在内部保存 `in_word` 标志，使得只有在真正遇到下一个空白字符时 `words += 1`，跨块的非空白序列也会被视为同一个单词。
- 行长度问题由 `current_line_length` 解决：每次遇到 `\n` 之前都把累计的长度与 `max_line_length` 比较；如果一行跨越多个块，该长度会累加直到遇到换行或文件结束，调用方在 `finish` 中做最后一次比较。
- 字符数依靠 `isUtf8Continuation` 判断当前字节是否为 UTF-8 续字节。只有起始字节会增加 `characters`，因此多字节字符跨块时也能保持正确计数。
- `Counter.finish` 统一处理文件末尾没有换行或尾部没有空白的情况，确保最后一个单词和行长度都会被纳入。

## Follow-up Ideas
- Explore exposing configuration for default chunk sizes to the CLI.
- Consider documenting the CLI flags and usage in a dedicated README section.
