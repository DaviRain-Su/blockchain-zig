const std = @import("std");
const blockchain_zig = @import("blockchain_zig");
const Stats = blockchain_zig.Stats;
const Counter = blockchain_zig.Counter;
const builtin = @import("builtin");
const enable_benchmarking = builtin.mode == .Debug;

const CliError = error{
    OpenFailed,
    BenchmarkFailed,
};

const chunk_size_candidates = [_]usize{ 512, 1024, 4_096, 8_192, 16_384 };
const default_chunk_size = chunk_size_candidates[chunk_size_candidates.len - 1];

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
        const s = try countAll(allocator, stdin_file, default_chunk_size);

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
                // set default chunk size
                const s = try countAll(allocator, stdin_file, default_chunk_size); // 读一次标准输入
                try printLine(stdout, s, path, want_l, want_w, want_c, want_L, want_m);
                total.lines += s.lines;
                total.bytes += s.bytes;
                total.words += s.words;
                total.characters += s.characters;
                if (s.max_line_length > total.max_line_length) {
                    total.max_line_length = s.max_line_length;
                }
                files_ok += 1;
                continue;
            }

            const s = processPath(allocator, path) catch |err| {
                had_error = true;
                try reportPathError(path, err);
                continue;
            };

            files_ok += 1;

            try printLine(stdout, s, path, want_l, want_w, want_c, want_L, want_m);
            total.lines += s.lines;
            total.bytes += s.bytes;
            total.words += s.words;
            total.characters += s.characters;
            if (s.max_line_length > total.max_line_length) {
                total.max_line_length = s.max_line_length;
            }
            try stdout.print("************************************\n", .{});
        }

        if (files_ok > 1) {
            if (want_l) try stdout.print("lines: {d} ", .{total.lines});
            if (want_w) try stdout.print("words: {d} ", .{total.words});
            if (want_c) try stdout.print("bytes: {d} ", .{total.bytes});
            if (want_m) try stdout.print("characters: {d} ", .{total.characters});
            if (want_L) try stdout.print("max line length: {d} ", .{total.max_line_length});
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

pub fn countAll(allocator: std.mem.Allocator, file: std.fs.File, chunk_size: usize) !Stats {
    if (chunk_size == 0) return error.InvalidChunkSize;
    var counter = Counter.init();
    var chunk: []u8 = try allocator.alloc(u8, chunk_size);
    defer allocator.free(chunk);

    while (true) {
        const n = try file.read(chunk[0..chunk_size]);
        if (n == 0) break;
        counter.process(chunk[0..n]);
    }

    counter.finish();
    return counter.stats;
}

const BenchmarkOutcome = struct {
    best_size: usize,
    stats: Stats,
    best_time_ns_timer: u64,
    best_time_ns_timestamp: u64,
};

fn benchmarkChunkSizes(allocator: std.mem.Allocator, file: *std.fs.File, chunk_sizes: []const usize) !BenchmarkOutcome {
    if (chunk_sizes.len == 0) return error.NoChunkSizes;

    var timer = try std.time.Timer.start();
    var outcome = BenchmarkOutcome{
        .best_size = chunk_sizes[0],
        .stats = undefined,
        .best_time_ns_timer = std.math.maxInt(u64),
        .best_time_ns_timestamp = std.math.maxInt(u64),
    };

    for (chunk_sizes) |size| {
        try file.seekTo(0);
        _ = timer.reset();
        const start_timestamp = std.time.nanoTimestamp();
        const stats = try countAll(allocator, file.*, size);
        const elapsed_timer_ns = timer.read();
        const end_timestamp = std.time.nanoTimestamp();
        const elapsed_timestamp_ns = @as(u64, @intCast(end_timestamp - start_timestamp));

        try logBenchmarkSample(size, elapsed_timer_ns, elapsed_timestamp_ns);

        const effective_ns = @min(elapsed_timer_ns, elapsed_timestamp_ns);
        const best_effective_ns = @min(outcome.best_time_ns_timer, outcome.best_time_ns_timestamp);
        if (effective_ns < best_effective_ns or (effective_ns == best_effective_ns and size < outcome.best_size)) {
            outcome.best_size = size;
            outcome.stats = stats;
            outcome.best_time_ns_timer = elapsed_timer_ns;
            outcome.best_time_ns_timestamp = elapsed_timestamp_ns;
        }
    }

    return outcome;
}

fn logBenchmarkSample(size: usize, timer_ns: u64, timestamp_ns: u64) CliError!void {
    stderr.print(
        "Chunk size: {} took {} ms (timer) / {} ms (timestamp)\n",
        .{ size, @divTrunc(timer_ns, 1_000_000), @divTrunc(timestamp_ns, 1_000_000) },
    ) catch {
        return error.BenchmarkFailed;
    };
}

fn logBenchmarkSummary(outcome: BenchmarkOutcome) CliError!void {
    stderr.print(
        "Best chunk size: {} with {} ms (timer) / {} ms (timestamp)\n",
        .{
            outcome.best_size,
            @divTrunc(outcome.best_time_ns_timer, 1_000_000),
            @divTrunc(outcome.best_time_ns_timestamp, 1_000_000),
        },
    ) catch {
        return error.BenchmarkFailed;
    };
}

fn processPath(allocator: std.mem.Allocator, path: []const u8) !Stats {
    var file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch {
        return error.OpenFailed;
    };
    defer file.close();

    if (enable_benchmarking) {
        const outcome = try benchmarkChunkSizes(allocator, &file, &chunk_size_candidates);
        try logBenchmarkSummary(outcome);
        return outcome.stats;
    }

    return try countAll(allocator, file, default_chunk_size);
}

fn reportPathError(path: []const u8, err: anyerror) !void {
    const message = switch (err) {
        error.OpenFailed => "failed to open input",
        error.BenchmarkFailed => "failed to log benchmark output",
        error.NoChunkSizes => "no chunk sizes configured",
        else => @errorName(err),
    };
    try stderr.print("{s}: {s}\n", .{ path, message });
    try stderr.flush();
}

test "printLine includes max line and characters" {
    var buffer: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const stats = Stats{
        .lines = 1,
        .bytes = 10,
        .words = 2,
        .max_line_length = 42,
        .characters = 11,
    };
    try printLine(stream.writer(), stats, "sample.txt", true, true, true, true, true);
    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "max line length: 42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "characters: 11") != null);
}

test "countAll rejects zero chunk size" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var file = try tmp.dir.createFile("sample.txt", .{ .read = true, .truncate = true });
    defer file.close();
    try file.writeAll("hello world");
    try file.seekTo(0);
    try std.testing.expectError(error.InvalidChunkSize, countAll(std.testing.allocator, file, 0));
}

test "benchmarkChunkSizes handles empty candidates" {
    if (!enable_benchmarking) return;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var file = try tmp.dir.createFile("sample.txt", .{ .read = true, .truncate = true });
    defer file.close();
    try file.writeAll("sample data\n");
    try file.seekTo(0);
    try std.testing.expectError(error.NoChunkSizes, benchmarkChunkSizes(std.testing.allocator, &file, &[_]usize{}));
}

test "benchmarkChunkSizes returns stats" {
    if (!enable_benchmarking) return;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var file = try tmp.dir.createFile("sample.txt", .{ .read = true, .truncate = true });
    defer file.close();
    try file.writeAll("hello\nworld\n");
    try file.seekTo(0);
    const bench = try benchmarkChunkSizes(std.testing.allocator, &file, &[_]usize{ 4, 8 });
    try std.testing.expectEqual(@as(usize, 2), bench.stats.lines);
    try std.testing.expectEqual(@as(usize, 2), bench.stats.words);
    try std.testing.expectEqual(@as(usize, 12), bench.stats.bytes);
}
