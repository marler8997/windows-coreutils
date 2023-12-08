const builtin = @import("builtin");
const std = @import("std");
const MappedFile = @import("MappedFile.zig");

fn oom(err: std.mem.Allocator.Error) noreturn {
    _ = err catch {};
    @panic("Out of memory");
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.io.getStdErr().writer().print("dos2unix: " ++ fmt ++ "\n", args) catch |err|
        std.debug.panic("failed to print error to stderr with {s}", .{@errorName(err)});
    std.os.exit(0xff);
}

fn usage() !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll(
        "Usage: dos2unix FILE...\n"
    );
}

pub fn main() !u8 {
    var args_arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // no need to deinit
    const args_allocator = args_arena_instance.allocator();
    const all_args = try std.process.argsAlloc(args_allocator);
    // no need to free

    if (all_args.len <= 1) {
        try usage();
        return 0xff;
    }

    var main_return_code: u8 = 0;
    for (all_args[1..]) |filename| {
        if (!normalize(filename)) {
            main_return_code = 0xff;
        }
    }

    return main_return_code;
}

fn report(filename: []const u8, comptime fmt: []const u8, args: anytype) void {
    const stderr = std.io.getStdErr().writer();
    stderr.print("dos2unix: {s}: ", .{filename}) catch |err| fatal(
        "failed to print to stderr, error={s}", .{@errorName(err)}
    );
    stderr.print(fmt ++ "\n", args) catch |err| fatal(
        "failed to print to stderr, error={s}", .{@errorName(err)}
    );
}

fn normalize(filename: []const u8) bool {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const tmp_filename = tmp_filename_blk: {
        var file_src = std.fs.cwd().openFile(filename, .{}) catch |err| {
            report(filename, "open failed, error={s}", .{@errorName(err)});
            return false;
        };
        var file_src_closed = false;
        defer if (!file_src_closed) file_src.close();
        const map_src = MappedFile.init(file_src, .{ .mode = .read_only }) catch |err| {
            report(filename, "mmap failed, error={s}", .{@errorName(err)});
            return false;
        };
        defer map_src.unmap();
        _ = std.mem.indexOf(u8, map_src.mem, "\r\n") orelse {
            report(filename, "already in Unix format", .{});
            return true;
        };
        
        const tmp_filename = std.fmt.allocPrint(
            arena,
            "{s}.dos2unix",
            .{filename},
        ) catch |e| oom(e);
        var tmp_file = std.fs.cwd().createFile(tmp_filename, .{ .read = true }) catch |err| {
            report(
                filename,
                "failed to create {s}, error={s}",
                .{tmp_filename, @errorName(err)},
            );
            return false;
        };
        defer tmp_file.close();
        truncateFile(tmp_file, map_src.mem.len) catch |err| {
            report(filename, "truncate {s} failed, error={s}", .{tmp_filename, @errorName(err)});
            return false;
        };
        const new_len = blk: {
            const map_dst = MappedFile.init(tmp_file, .{ .mode = .read_write }) catch |err| {
                report(filename, "mmap {s} failed, error={s}", .{tmp_filename, @errorName(err)});
                return false;
            };
            defer map_dst.unmap();
            var dst: usize = 0;
            var src: usize = 0;
            main_copy_loop:
                while (true) {
                    while (true) {
                        if (src == map_src.mem.len) break :main_copy_loop;
                        if (map_src.mem[src] != '\r') break;
                        src += 1;
                    }
                    map_dst.mem[dst] = map_src.mem[src];
                    dst += 1;
                    src += 1;
            }
            break :blk dst;
        };
        truncateFile(tmp_file, new_len) catch |err| {
            report(
                filename,
                "truncate {s} from {} to {} failed, error={s}",
                .{tmp_filename, map_src.mem.len, new_len, @errorName(err)},
            );
            return false;
        };
        break :tmp_filename_blk tmp_filename;
    };
    
    std.fs.cwd().rename(tmp_filename, filename) catch |err| {
        report(
            filename,
            "failed to overrwrite file with tmp '{s}', error={s}",
            .{tmp_filename, @errorName(err)},
        );
        return false;
    };

    report(filename, "converted to Unix format", .{});
    return true;
}

fn truncateFile(file: std.fs.File, len: u64) !void {
    if (builtin.os.tag == .windows) {
        try std.os.lseek_SET(file.handle, len);
        if (0 == std.os.windows.kernel32.SetEndOfFile(file.handle)) {
            switch (std.os.windows.kernel32.GetLastError()) {
                else => |e| return std.os.windows.unexpectedError(e),
            }
        }
        try std.os.lseek_SET(file.handle, 0);
    } else {
        std.debug.panic("todo: implement truncate file for non-windows", .{});
    }
}
