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

    var i: usize = 1;
    while (i < args.len and args[i].len >= 2 and args[i][0] == '-') {
        if (std.mem.eql(u8, args[i], "-h") or std.mem.eql(u8, args[i], "--help")) {
            try stderr.print("usage: {s} [-lwc] [FILE...]\n", .{args[0]});
            try stderr.print("  -l  lines    -w  words    -c  bytes\n", .{});
            try stderr.flush();
            std.process.exit(0);
        }

        const opt = args[i];
        // 多个标志可合并，如 -lc
        for (opt[1..]) |ch| switch (ch) {
            'l' => want_l = true,
            'w' => want_w = true,
            'c' => want_c = true,
            else => {
                try stderr.print("unknown flag: -{c}\nusage: {s} [-lwc] [FILE]\n", .{ ch, args[0] });
                try stderr.flush();
                std.process.exit(1);
            },
        };
        i += 1;
    }
    // 如果没给任何标志，默认全开
    if (!want_l and !want_w and !want_c) {
        want_l = true;
        want_w = true;
        want_c = true;
    }

    // For debug
    //std.debug.print("Args Length: {}, i: {}\n", .{ args.len, i });
    //for (args) |arg| {
    // std.debug.print("Arg: {s}\n", .{arg});
    // }

    if (i >= args.len) {
        const stdin_file = std.fs.File.stdin(); // 返回一个 File
        const s = try countAll(stdin_file);

        if (want_l) try stdout.print("lines: {d}\n", .{s.lines});
        if (want_w) try stdout.print("words: {d}\n", .{s.words});
        if (want_c) try stdout.print("bytes: {d}\n", .{s.bytes});

        try stdout.flush();
        try std.process.exit(0);
    } else {
        var had_error = false;
        var files_ok: usize = 0;
        var total = Stats{ .lines = 0, .bytes = 0, .words = 0 };
        for (args[i..]) |path| {
            var f = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |e| {
                try stderr.print("{s}: {s}\n", .{ path, @errorName(e) });
                try stderr.flush();
                had_error = true;
                continue;
            };
            defer f.close();
            const s = try countAll(f);
            files_ok += 1;

            try printLine(stdout, s, path, want_l, want_w, want_c);
            total.lines += s.lines;
            total.bytes += s.bytes;
            total.words += s.words;
            try stdout.print("************************************\n", .{});
        }

        if (files_ok > 1) {
            if (want_l) try stdout.print("lines: {d} ", .{total.lines});
            if (want_w) try stdout.print("words: {d} ", .{total.words});
            if (want_c) try stdout.print("bytes: {d} ", .{total.bytes});
            try stdout.print("total\n", .{});
        }
        try stdout.flush();
        std.process.exit(if (had_error) 1 else 0);
    }
}

fn printLine(w: anytype, s: Stats, name: ?[]const u8, want_l: bool, want_w: bool, want_c: bool) !void {
    if (want_l) try w.print("lines:{d} ", .{s.lines});
    if (want_w) try w.print("words:{d} ", .{s.words});
    if (want_c) try w.print("bytes:{d} ", .{s.bytes});
    if (name) |n| try w.print("{s}", .{n});
    try w.print("\n", .{});
}

const Stats = struct {
    lines: usize,
    bytes: usize,
    words: usize,
};

pub fn countAll(file: std.fs.File) !Stats {
    var lines: usize = 0;
    var bytes: usize = 0;
    var words: usize = 0;
    var in_word: bool = false;
    var chunk: [4096]u8 = undefined;

    while (true) {
        const n = try file.read(chunk[0..]);
        bytes += n;
        if (n == 0) break;
        for (chunk[0..n]) |b| {
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
    }
    // 你现在是在遇到空白时给 words += 1。如果文件结尾处没有空白（例如内容是 "abc" 没有换行/空格），
    // 循环退出前 in_word 还在 true，但循环结束后没有再加 1，导致漏计最后一个词。
    if (in_word) words += 1;

    return Stats{ .lines = lines, .bytes = bytes, .words = words };
}
