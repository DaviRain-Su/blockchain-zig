const std = @import("std");

pub const Stats = struct {
    lines: usize,
    bytes: usize,
    words: usize,
    max_line_length: usize,
    characters: usize, // 字符统计
};

pub fn countFromSlice(slice: []const u8) !Stats {
    var lines: usize = 0;
    //var bytes: usize = 0;
    var words: usize = 0;
    var in_word: bool = false;

    for (slice) |b| {
        if (b == '\n') lines += 1;
        if (std.ascii.isWhitespace(b)) {
            if (in_word) {
                words += 1;
                in_word = false;
            }
        } else {
            if (!in_word) {
                in_word = true;
            }
        }
    }
    // 你现在是在遇到空白时给 words += 1。如果文件结尾处没有空白（例如内容是 "abc" 没有换行/空格），
    // 循环退出前 in_word 还在 true，但循环结束后没有再加 1，导致漏计最后一个词。
    if (in_word) words += 1;

    return Stats{
        .lines = lines,
        .bytes = slice.len,
        .words = words,
        .max_line_length = 0,
        .characters = 0,
    };
}

test "countAll basic" {
    const s = try countFromSlice("a\nb c\n");
    std.debug.print("Lines: {}, Words: {}, Bytes: {}\n", .{ s.lines, s.words, s.bytes });
    try std.testing.expectEqual(@as(usize, 2), s.lines);
    try std.testing.expectEqual(@as(usize, 3), s.words);
    try std.testing.expectEqual(@as(usize, 6), s.bytes);
}

test "countFromSlice: trailing EOF word" {
    const s = try countFromSlice("abc");
    std.debug.print("Lines: {}, Words: {}, Bytes: {}\n", .{ s.lines, s.words, s.bytes });
    try std.testing.expectEqual(@as(usize, 0), s.lines);
    try std.testing.expectEqual(@as(usize, 1), s.words);
    try std.testing.expectEqual(@as(usize, 3), s.bytes);
}

test "countFromSlice: ' a\n\nb' " {
    const s = try countFromSlice(" a\n\nb");
    std.debug.print("Lines: {}, Words: {}, Bytes: {}\n", .{ s.lines, s.words, s.bytes });
    try std.testing.expectEqual(@as(usize, 2), s.lines);
    try std.testing.expectEqual(@as(usize, 2), s.words);
    try std.testing.expectEqual(@as(usize, 5), s.bytes);
}

test "countFromSlice: empty " {
    const s = try countFromSlice("");
    std.debug.print("Lines: {}, Words: {}, Bytes: {}\n", .{ s.lines, s.words, s.bytes });
    try std.testing.expectEqual(@as(usize, 0), s.lines);
    try std.testing.expectEqual(@as(usize, 0), s.words);
    try std.testing.expectEqual(@as(usize, 0), s.bytes);
}

test "countFromSlice: `a \tb\n` " {
    const s = try countFromSlice("a \tb\n");
    std.debug.print("Lines: {}, Words: {}, Bytes: {}\n", .{ s.lines, s.words, s.bytes });
    try std.testing.expectEqual(@as(usize, 1), s.lines);
    try std.testing.expectEqual(@as(usize, 2), s.words);
    try std.testing.expectEqual(@as(usize, 5), s.bytes);
}

test "countFromSlice: `a\r\nb\r\n` " {
    const s = try countFromSlice("a\r\nb\r\n");
    std.debug.print("Lines: {}, Words: {}, Bytes: {}\n", .{ s.lines, s.words, s.bytes });
    try std.testing.expectEqual(@as(usize, 2), s.lines);
    try std.testing.expectEqual(@as(usize, 2), s.words);
    try std.testing.expectEqual(@as(usize, 6), s.bytes);
}
