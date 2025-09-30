const std = @import("std");

pub const Stats = struct {
    lines: usize, // 行数
    bytes: usize, // 字节数
    words: usize, // 单词数
    max_line_length: usize, // 最大行长度
    characters: usize, // 字符统计
};

pub const Counter = struct {
    stats: Stats = .{
        .lines = 0,
        .bytes = 0,
        .words = 0,
        .max_line_length = 0,
        .characters = 0,
    },
    current_line_length: usize = 0,
    in_word: bool = false,

    pub fn init() Counter {
        return Counter{};
    }

    pub fn process(self: *Counter, slice: []const u8) void {
        self.stats.bytes += slice.len;

        for (slice) |b| {
            if (!isUtf8Continuation(b)) {
                self.stats.characters += 1;
            }

            if (b == '\n') {
                self.stats.lines += 1;
                if (self.current_line_length > self.stats.max_line_length) {
                    self.stats.max_line_length = self.current_line_length;
                }
                self.current_line_length = 0;
            } else {
                self.current_line_length += 1;
            }

            if (std.ascii.isWhitespace(b)) {
                if (self.in_word) {
                    self.stats.words += 1;
                    self.in_word = false;
                }
            } else if (!self.in_word) {
                self.in_word = true;
            }
        }
    }

    pub fn finish(self: *Counter) void {
        if (self.current_line_length > self.stats.max_line_length) {
            self.stats.max_line_length = self.current_line_length;
        }
        if (self.in_word) {
            self.stats.words += 1;
            self.in_word = false;
        }
    }
};

pub fn countFromSlice(slice: []const u8) !Stats {
    var counter = Counter.init();
    counter.process(slice);
    counter.finish();
    return counter.stats;
}

//统计 UTF-8 的“起始字节”数量。UTF-8 的续字节满足 (b & 0b1100_0000) == 0b1000_0000，
// 所以每遇到一个“不是续字节”的字节就 +1，得到的就是字符数（假设输入是有效 UTF-8）。
// 这个方法天然支持跨块，无需状态机。
pub inline fn isUtf8Continuation(b: u8) bool {
    return (b & 0b1100_0000) == 0b1000_0000;
}

test "countAll basic" {
    const s = try countFromSlice("a\nb c\n");
    std.debug.print(
        "Lines: {}, Words: {}, Bytes: {}, Characters: {}, Max line: {}\n",
        .{ s.lines, s.words, s.bytes, s.characters, s.max_line_length },
    );
    try std.testing.expectEqual(@as(usize, 2), s.lines);
    try std.testing.expectEqual(@as(usize, 3), s.words);
    try std.testing.expectEqual(@as(usize, 6), s.bytes);
    try std.testing.expectEqual(@as(usize, 6), s.characters);
    try std.testing.expectEqual(@as(usize, 3), s.max_line_length);
}

test "countFromSlice: trailing EOF word" {
    const s = try countFromSlice("abc");
    std.debug.print(
        "Lines: {}, Words: {}, Bytes: {}, Characters: {}, Max line: {}\n",
        .{ s.lines, s.words, s.bytes, s.characters, s.max_line_length },
    );
    try std.testing.expectEqual(@as(usize, 0), s.lines);
    try std.testing.expectEqual(@as(usize, 1), s.words);
    try std.testing.expectEqual(@as(usize, 3), s.bytes);
    try std.testing.expectEqual(@as(usize, 3), s.characters);
    try std.testing.expectEqual(@as(usize, 3), s.max_line_length);
}

test "countFromSlice: ' a\n\nb' " {
    const s = try countFromSlice(" a\n\nb");
    std.debug.print(
        "Lines: {}, Words: {}, Bytes: {}, Characters: {}, Max line: {}\n",
        .{ s.lines, s.words, s.bytes, s.characters, s.max_line_length },
    );
    try std.testing.expectEqual(@as(usize, 2), s.lines);
    try std.testing.expectEqual(@as(usize, 2), s.words);
    try std.testing.expectEqual(@as(usize, 5), s.bytes);
    try std.testing.expectEqual(@as(usize, 5), s.characters);
    try std.testing.expectEqual(@as(usize, 2), s.max_line_length);
}

test "countFromSlice: empty " {
    const s = try countFromSlice("");
    std.debug.print(
        "Lines: {}, Words: {}, Bytes: {}, Characters: {}, Max line: {}\n",
        .{ s.lines, s.words, s.bytes, s.characters, s.max_line_length },
    );
    try std.testing.expectEqual(@as(usize, 0), s.lines);
    try std.testing.expectEqual(@as(usize, 0), s.words);
    try std.testing.expectEqual(@as(usize, 0), s.bytes);
    try std.testing.expectEqual(@as(usize, 0), s.characters);
    try std.testing.expectEqual(@as(usize, 0), s.max_line_length);
}

test "countFromSlice: `a \tb\n` " {
    const s = try countFromSlice("a \tb\n");
    std.debug.print(
        "Lines: {}, Words: {}, Bytes: {}, Characters: {}, Max line: {}\n",
        .{ s.lines, s.words, s.bytes, s.characters, s.max_line_length },
    );
    try std.testing.expectEqual(@as(usize, 1), s.lines);
    try std.testing.expectEqual(@as(usize, 2), s.words);
    try std.testing.expectEqual(@as(usize, 5), s.bytes);
    try std.testing.expectEqual(@as(usize, 5), s.characters);
    try std.testing.expectEqual(@as(usize, 4), s.max_line_length);
}

test "countFromSlice: `a\r\nb\r\n` " {
    const s = try countFromSlice("a\r\nb\r\n");
    std.debug.print(
        "Lines: {}, Words: {}, Bytes: {}, Characters: {}, Max line: {}\n",
        .{ s.lines, s.words, s.bytes, s.characters, s.max_line_length },
    );
    try std.testing.expectEqual(@as(usize, 2), s.lines);
    try std.testing.expectEqual(@as(usize, 2), s.words);
    try std.testing.expectEqual(@as(usize, 6), s.bytes);
    try std.testing.expectEqual(@as(usize, 6), s.characters);
    try std.testing.expectEqual(@as(usize, 2), s.max_line_length);
}

test "counter keeps state across chunks" {
    var counter = Counter.init();
    counter.process("foo");
    counter.process("bar baz");
    counter.finish();
    try std.testing.expectEqual(@as(usize, 0), counter.stats.lines);
    try std.testing.expectEqual(@as(usize, 2), counter.stats.words);
    try std.testing.expectEqual(@as(usize, 10), counter.stats.bytes);
    try std.testing.expectEqual(@as(usize, 10), counter.stats.characters);
    try std.testing.expectEqual(@as(usize, 10), counter.stats.max_line_length);
}

test "counter tracks long line across chunks" {
    var counter = Counter.init();
    counter.process("aaaaaaaa");
    counter.process("aaaaaaaa\n");
    counter.finish();
    try std.testing.expectEqual(@as(usize, 1), counter.stats.lines);
    try std.testing.expectEqual(@as(usize, 1), counter.stats.words);
    try std.testing.expectEqual(@as(usize, 17), counter.stats.bytes);
    try std.testing.expectEqual(@as(usize, 17), counter.stats.characters);
    try std.testing.expectEqual(@as(usize, 16), counter.stats.max_line_length);
}

test "countFromSlice counts utf8 characters" {
    const sample = "\xe4\xbd\xa0\xe5\xa5\xbd\n"; // "你好\n"
    const s = try countFromSlice(sample);
    try std.testing.expectEqual(@as(usize, 1), s.lines);
    try std.testing.expectEqual(@as(usize, 1), s.words);
    try std.testing.expectEqual(@as(usize, 7), s.bytes);
    try std.testing.expectEqual(@as(usize, 3), s.characters);
    try std.testing.expectEqual(@as(usize, 6), s.max_line_length);
}
