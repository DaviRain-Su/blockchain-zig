const std = @import("std");
const blockchain_zig = @import("blockchain_zig");

var stdout_buffer: [1024]u8 = undefined;
var stderr_buffer: [1024]u8 = undefined;
// stdout
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;
// stderr
var errw = std.fs.File.stderr().writer(&stderr_buffer);
const stderr = &errw.interface;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // 解析 -l / -w / -c
    var want_l = false;
    var want_w = false;
    var want_c = false;
    // -L
    var want_L = false;
    var want_m = false;

    var i: usize = 1;
    while (i < args.len and args[i].len >= 2 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "--")) { // 终止选项
            i += 1;
            break;
        }
        if (std.mem.eql(u8, args[i], "-h") or std.mem.eql(u8, args[i], "--help")) {
            try stderr.print("usage: {s} [-lwc] [FILE...]\n", .{args[0]});
            try stderr.print("  -l  lines\n", .{});
            try stderr.print("  -w  words\n", .{});
            try stderr.print("  -c  bytes\n", .{});
            try stderr.print("  -h  help\n", .{});
            try stderr.print("  - read from stdin\n", .{});
            try stderr.print("  -- end of options\n", .{});
            try stderr.flush();
            std.process.exit(0);
        }

        const opt = args[i];
        // 多个标志可合并，如 -lc
        for (opt[1..]) |ch| switch (ch) {
            'l' => want_l = true,
            'w' => want_w = true,
            'c' => want_c = true,
            'm' => want_m = true,
            'L' => want_L = true,
            else => {
                try stderr.print("unknown flag: -{c}\nusage: {s} [-lwc] [FILE...] \n", .{ ch, args[0] });
                try stderr.flush();
                std.process.exit(1);
            },
        };
        i += 1;
    }
    // 如果没给任何标志，默认全开
    if (!want_l and !want_w and !want_c and !want_m and !want_L) {
        want_l = true;
        want_w = true;
        want_c = true;
    }

    const is_tty = std.posix.isatty(std.posix.STDIN_FILENO);

    if (i >= args.len) {
        if (is_tty) {
            try stderr.print("reading from stdin... (Ctrl-D to finish)\n", .{});
            try stderr.flush();
        }

        const stdin_file = std.fs.File.stdin(); // 返回一个 File
        const s = try countAll(stdin_file);

        if (want_l) try stdout.print("lines: {d}\n", .{s.lines});
        if (want_w) try stdout.print("words: {d}\n", .{s.words});
        if (want_c) try stdout.print("bytes: {d}\n", .{s.bytes});
        if (want_L) try stdout.print("max line length: {d}\n", .{s.max_line_length});
        if (want_m) try stdout.print("characters: {d}\n", .{s.characters});

        try stdout.flush();
        try std.process.exit(0);
    } else {
        var had_error = false;
        var files_ok: usize = 0;
        var total = Stats{ .lines = 0, .bytes = 0, .words = 0, .max_line_length = 0, .characters = 0 };
        for (args[i..]) |path| {
            if (std.mem.eql(u8, path, "-")) {
                const stdin_file = std.fs.File.stdin(); // 返回一个 File
                const s = try countAll(stdin_file); // 读一次标准输入
                try printLine(stdout, s, path, want_l, want_w, want_c, want_L, want_m);
                total.lines += s.lines;
                total.bytes += s.bytes;
                total.words += s.words;
                files_ok += 1;
                continue;
            }

            var f = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |e| {
                try stderr.print("{s}: {s}\n", .{ path, @errorName(e) });
                try stderr.flush();
                had_error = true;
                continue;
            };
            defer f.close();
            const s = try countAll(f);
            files_ok += 1;

            try printLine(stdout, s, path, want_l, want_w, want_c, want_L, want_m);
            total.lines += s.lines;
            total.bytes += s.bytes;
            total.words += s.words;
            total.characters += s.characters;
            try stdout.print("************************************\n", .{});
        }

        if (files_ok > 1) {
            if (want_l) try stdout.print("lines: {d} ", .{total.lines});
            if (want_w) try stdout.print("words: {d} ", .{total.words});
            if (want_c) try stdout.print("bytes: {d} ", .{total.bytes});
            if (want_m) try stdout.print("characters: {d} ", .{total.characters});
            try stdout.print("total\n", .{});
        }
        try stdout.flush();
        std.process.exit(if (had_error) 1 else 0);
    }
}

fn printLine(w: anytype, s: Stats, name: ?[]const u8, want_l: bool, want_w: bool, want_c: bool, want_L: bool, want_m: bool) !void {
    if (want_l) try w.print("lines: {d} ", .{s.lines});
    if (want_w) try w.print("words: {d} ", .{s.words});
    if (want_c) try w.print("bytes: {d} ", .{s.bytes});
    if (want_L) try w.print("max line length: {d} ", .{s.max_line_length});
    if (want_m) try w.print("characters: {d} ", .{s.characters});
    if (name) |n| try w.print("{s}", .{n});
    try w.print("\n", .{});
}

const Stats = struct {
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

    return Stats{ .lines = lines, .bytes = slice.len, .words = words };
}

pub fn countAll(file: std.fs.File) !Stats {
    var lines: usize = 0;
    var bytes: usize = 0;
    var words: usize = 0;
    var max_line_length: usize = 0;
    var current_line_length: usize = 0;
    var characters: usize = 0;
    var in_word: bool = false;
    var chunk: [4096]u8 = undefined;

    while (true) {
        const n = try file.read(chunk[0..]);
        bytes += n;

        if (n == 0) break;

        for (chunk[0..n]) |b| {
            if (!isUtf8Continuation(b)) {
                characters += 1;
            }
            if (b == '\n') {
                lines += 1;
                // 更新最大行长度
                if (current_line_length > max_line_length) {
                    max_line_length = current_line_length;
                }
                current_line_length = 0;
            }
            current_line_length += 1;

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
    }

    // 结尾行处理（文件没有换行符时）
    if (current_line_length > max_line_length) {
        max_line_length = current_line_length;
    }
    // 你现在是在遇到空白时给 words += 1。如果文件结尾处没有空白（例如内容是 "abc" 没有换行/空格），
    // 循环退出前 in_word 还在 true，但循环结束后没有再加 1，导致漏计最后一个词。
    if (in_word) words += 1;

    return Stats{
        .lines = lines,
        .bytes = bytes,
        .words = words,
        .max_line_length = max_line_length,
        .characters = characters,
    };
}

//统计 UTF-8 的“起始字节”数量。UTF-8 的续字节满足 (b & 0b1100_0000) == 0b1000_0000，
// 所以每遇到一个“不是续字节”的字节就 +1，得到的就是字符数（假设输入是有效 UTF-8）。
// 这个方法天然支持跨块，无需状态机。
inline fn isUtf8Continuation(b: u8) bool {
    return (b & 0b1100_0000) == 0b1000_0000;
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
