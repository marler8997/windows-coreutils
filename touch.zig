const std = @import("std");

fn oom(err: std.mem.Allocator.Error) noreturn {
    _ = err catch {};
    @panic("Out of memory");
}

fn usage() !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll("Usage: touch FILE...\n");
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
        var new_args = all_args[1..];
        var new_arg_count: usize = 0;
        for (new_args) |arg| {
            if (!std.mem.startsWith(u8, arg, "-")) {
                new_args[new_arg_count] = arg;
                new_arg_count += 1;
            } else {
                std.log.err("unknown cmdline options '{s}'", .{arg});
                return 0x7f;
            }
        }
        break :blk new_args[0..new_arg_count];
    };
    if (args.len == 0) {
        try usage();
        return 0x7f;
    }
    for (args) |arg| {
        var file = try std.fs.cwd().createFile(arg, .{});
        file.close();
    }

    return 0;
}
