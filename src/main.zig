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

    if (args.len < 2) {
        const stdin_file = std.fs.File.stdin(); // 返回一个 File
        const s = try countAll(stdin_file);

        try stdout.print("lines: {d}\nbytes: {d}\nwords: {d}\n", .{ s.lines, s.bytes, s.words });
        try stdout.flush();
        try std.process.exit(0);
    } else {
        var f = try std.fs.cwd().openFile(args[1], .{ .mode = .read_only });
        defer f.close();
        const s = try countAll(f);

        try stdout.print("lines: {d}\nbytes: {d}\nwords: {d}\n", .{ s.lines, s.bytes, s.words });
        try stdout.flush();
        try std.process.exit(0);
    }
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
