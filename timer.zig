const std = @import("std");

fn oom(err: std.mem.Allocator.Error) noreturn {
    _ = err catch {};
    @panic("Out of memory");
}

fn usage() !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll("Usage: timer COMMAND...\n");
}

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const all_args = try std.process.argsAlloc(allocator);
    // no need to free

    if (all_args.len <= 1) {
        try usage();
        return 0x7f;
    }
    const args = blk: {
        for (all_args[1..], 1..) |arg, arg_index| {
            if (!std.mem.startsWith(u8, arg, "-")) {
                break :blk all_args[arg_index..];
            } else {
                std.log.err("unknown cmdline options '{s}'", .{arg});
                return 0x7f;
            }
        }
        try usage();
        return 0x7f;
    };

    const start = try std.time.Instant.now();

    blk: {
        var proc = std.process.Child.init(args, allocator);
        proc.spawn() catch |err| {
            std.log.err("failed to spawn child process with {s}", .{@errorName(err)});
            break :blk;
        };
        const result = proc.wait() catch |err| {
            std.log.err("failed to wait for child process with {s}", .{@errorName(err)});
            break :blk;
        };
        switch (result) {
            .Exited => |code| if (code != 0) {
                std.log.err("command exited with non-zero status {}", .{code});
            },
            .Signal => |signo| std.log.err("command exited with signal {}", .{signo}),
            .Stopped => |signo| std.log.err("command stopped with signal {}", .{signo}),
            .Unknown => |status| std.log.err("command terminated unexpectedly, status={}", .{status}),
        }
    }

    const elapsed = (try std.time.Instant.now()).since(start);
    const stderr = std.io.getStdErr().writer();
    try stderr.print("timer: {}\n", .{std.fmt.fmtDuration(elapsed)});

    return 0;
}
