const std = @import("std");

fn usage() !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll(
        "Usage: ls [-lh] [FILE]...\n" ++
        "    -l Long listing format\n" ++
        "    -h Human readable sizes\n"
    );
}

const Options = struct {
    human: bool = false,
    long: bool = false,
};

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const all_args = try std.process.argsAlloc(allocator);
    // no need to free

    var opt = Options{ };
    const args: []const [:0]const u8 = blk: {
        const start: usize = if (all_args.len == 0) 0 else 1;
        for (all_args[start..], start..) |arg, arg_index| {
            if (!std.mem.startsWith(u8, arg, "-")) {
                break :blk all_args[arg_index..];
            } else if (std.mem.eql(u8, arg, "--help")) {
                try usage();
                return 0x7f;
            } else {
                for (arg[1..]) |c| {
                    if (c == 'l') {
                        opt.long = true;
                    } else if (c == 'h') {
                        opt.human = true;
                    } else {
                        std.log.err("unknown cmdline option '-{c}'", .{c});
                        return 0x7f;
                    }
                }
            }
        }
        break :blk &[_][:0]u8 { };
    };

    const stdout = std.io.getStdOut().writer();
    var bw = BufferedWriter{ .unbuffered_writer = stdout };
    const writer = bw.writer();

    var result = Success.success;
    if (args.len == 0) {
        switch (try list(writer, ".", opt)) {
            .success => {},
            .failure => result = .failure,
        }
    } else {
        for (args) |arg| {
            switch (try list(writer, arg, opt)) {
                .success => {},
                .failure => result = .failure,
            }
        }
    }
    try bw.flush();
    return switch (result) {
        .success => 0,
        .failure => 0x7f,
    };
}

const Success = enum { success, failure };

fn open(dir: std.fs.Dir, path: []const u8) !std.fs.File {
    const path_w = try std.os.windows.sliceToPrefixedFileW(path);
    return std.fs.File{
        .handle = try std.os.windows.OpenFile(path_w.span(), .{
            .dir = dir.fd,
            .access_mask = std.os.windows.SYNCHRONIZE | std.os.windows.GENERIC_READ,
            .creation = std.os.windows.FILE_OPEN,
            .io_mode = .blocking,
            .filter = .any,
        }),
        .capable_io_mode = std.io.default_mode,
        .intended_io_mode = .blocking,
    };
}

pub fn list(
    writer: BufferedWriter.Writer,
    path: []const u8,
    opt: Options,
) !Success {
    const stderr = std.io.getStdErr().writer();
    const file = open(std.fs.cwd(), path) catch |err| switch (err) {
        error.FileNotFound => {
            try stderr.print("ls: '{s}' does not exist", .{path});
            return .failure;
        },
        else => |e| return e,
    };
    defer file.close();

    const stat = try file.stat();
    switch (stat.kind) {
        .file => {
            if (opt.long) {
                try listFileLong(opt, writer, file, path);
            } else {
                try writer.print("{s}", .{path});
            }
            return .success;
        },
        .directory => {
            var dir = std.fs.IterableDir{ .dir = .{ .fd = file.handle } };
            // don't close the directory, it's still owned by file
            //defer dir.close();
            return try listDir(writer, dir, opt);
        },
        .sym_link => @panic("todo: implement sym_link on Windows"),
        .unknown => @panic("todo: unknown file type"),
        .block_device => @panic("block device on Windows?!?"),
        .character_device => @panic("character device on Windows?!?"),
        .named_pipe => @panic("named pipe on Windows?!?"),
        .event_port => @panic("event port on Windows?!?"),
        .whiteout => @panic("what is a whiteout?!?"),
        .door => @panic("what is a door?!?"),
        .unix_domain_socket => unreachable,
    }
}

const BufferedWriter = std.io.BufferedWriter(4096, std.fs.File.Writer);

fn listFileLong(
    opt: Options,
    writer: BufferedWriter.Writer,
    file: std.fs.File,
    name: []const u8,
) !void {
    std.debug.assert(opt.long);

    const stat = try file.stat();
    try writer.print("{c} ", .{getEntryChar(stat.kind)});
    if (opt.human) {
        try writer.print("{: >9.1}", .{std.fmt.fmtIntSizeBin(stat.size)});
    } else {
        try writer.print("{: >9}", .{stat.size});
    }
    {
        const es = std.time.epoch.EpochSeconds{
            .secs = @intCast(u64, @divTrunc(stat.mtime, std.time.ns_per_s)),
        };
        const md = es.getEpochDay().calculateYearDay().calculateMonthDay();
        const ds = es.getDaySeconds();
        const hours = ds.getHoursIntoDay();
        const min = ds.getMinutesIntoHour();
        const secs = ds.getSecondsIntoMinute();
        try writer.print(
            " {s} {} {:0>2}:{:0>2}:{:0>2}",
            .{
                @tagName(md.month),
                @intCast(u6, md.day_index) + 1,
                hours,
                min,
                secs,
            },
        );
    }
    try writer.print(" {s}\n", .{name});
}

fn listDir(
    writer: BufferedWriter.Writer,
    dir: std.fs.IterableDir,
    opt: Options,
) !Success {
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (opt.long) {
            var sub_file = try open(dir.dir, entry.name);
            defer sub_file.close();
            try listFileLong(opt, writer, sub_file, entry.name);
        } else {
            try writer.print("{s}\n", .{entry.name});
        }
    }
    return .success;
}

fn getEntryChar(kind: std.fs.File.Kind) u8 {
    return switch (kind) {
        .file => '-',
        .directory => 'd',
        .sym_link => 'l',
        .unknown => @panic("todo: unknown file type"),
        .block_device => @panic("block device on Windows?!?"),
        .character_device => @panic("character device on Windows?!?"),
        .named_pipe => @panic("named pipe on Windows?!?"),
        .event_port => @panic("event port on Windows?!?"),
        .whiteout => @panic("what is a whiteout?!?"),
        .door => @panic("what is a door?!?"),
        .unix_domain_socket => unreachable,
    };
}
