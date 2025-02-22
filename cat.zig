const std = @import("std");

pub fn main() !void {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // no need to deinit
    const arena = arena_instance.allocator();

    const args = try std.process.argsAlloc(arena);
    if (args.len <= 1) {
        try catFile(std.io.getStdIn());
    } else {
        for (args[1..]) |arg| {
            const file = std.fs.cwd().openFile(arg, .{}) catch |err| {
                std.log.err("open '{s}' failed with {s}", .{ arg, @errorName(err) });
                std.process.exit(0xff);
            };
            defer file.close();
            try catFile(file);
        }
    }
}

fn catFile(file: std.fs.File) !void {
    const stdout = std.io.getStdOut().writer();
    while (true) {
        var buffer: [4096]u8 = undefined;
        const bytes_read = try file.read(&buffer);
        if (bytes_read == 0) break;
        try stdout.writeAll(buffer[0..bytes_read]);
    }
}
