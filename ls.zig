const builtin = @import("builtin");
const std = @import("std");
const fs = @import("fs.zig");

fn usage() !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll("Usage: ls [-lh] [FILE]...\n" ++
        "    -l Long listing format\n" ++
        "    -h Human readable sizes\n");
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

    var opt = Options{};
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
        break :blk &[_][:0]u8{};
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

pub fn list(
    writer: BufferedWriter.Writer,
    path: []const u8,
    opt: Options,
) !Success {
    const stderr = std.io.getStdErr().writer();
    const file = fs.open(std.fs.cwd(), path, .{}) catch |err| switch (err) {
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
            const dir = std.fs.Dir{ .fd = file.handle };
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

    std.log.info("--- name='{s}'", .{name});
    const stat = try file.stat();
    try writer.print("{c} ", .{getEntryChar(stat.kind)});
    if (opt.human) {
        try writer.print("{: >9.3}", .{std.fmt.fmtIntSizeBin(stat.size)});
    } else {
        try writer.print("{: >9}", .{stat.size});
    }
    {
        {
            //const windows = std.os.windows;
            var io_status_block: std.os.windows.IO_STATUS_BLOCK = undefined;
            var info: std.os.windows.FILE_ALL_INFORMATION = std.mem.zeroes(std.os.windows.FILE_ALL_INFORMATION);
            //info.mtime = 0;
            std.log.info("before: info={any}", .{info});
            const rc = std.os.windows.ntdll.NtQueryInformationFile(file.handle, &io_status_block, &info, @sizeOf(std.os.windows.FILE_ALL_INFORMATION), .FileAllInformation);
            switch (rc) {
                .SUCCESS => {},
                .BUFFER_OVERFLOW => {
                    const epoch_time = fromSysTime(info.BasicInformation.LastWriteTime);
                    std.log.info(
                        "OVERFLOW info LastWriteTime={} ({})",
                        .{
                            info.BasicInformation.LastWriteTime,
                            epoch_time,
                        },
                    );
                    // std.log.err("overflow, mtime={}", .{info.mtime});
                },
                else => |r| {
                    std.log.err("stat failed, rc={}", .{r});
                },
            }
            // var tag_info: windows.FILE_ATTRIBUTE_TAG_INFO = undefined;
            // const tag_rc = windows.ntdll.NtQueryInformationFile(file.handle, &io_status_block, &tag_info, @sizeOf(windows.FILE_ATTRIBUTE_TAG_INFO), .FileAttributeTagInformation);
            // switch (tag_rc) {
            //     .SUCCESS => {
            //         std.log.info("info success", .{});
            //     },
            //     else => |r| {
            //         std.log.err("info error {s}", .{@tagName(r)});
            //     },
            // }
        }
        std.log.info("seconds={}", .{@divTrunc(stat.mtime, std.time.ns_per_s)});
        std.log.info("maxu64 ={}", .{std.math.maxInt(u64)});
        const es = Seconds(i128){
            .secs = @intCast(@divTrunc(stat.mtime, std.time.ns_per_s)),
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
                @as(u6, md.day_index) + 1,
                hours,
                min,
                secs,
            },
        );
    }
    try writer.print(" {s}\n", .{name});
}

/// This function returns the number of nanoseconds since the canonical epoch,
/// which is the POSIX one (Jan 01, 1970 AD).
pub fn fromSysTime(hns: i64) i128 {
    const adjusted_epoch: i128 = @as(i128, hns) + @as(i128, std.time.epoch.windows) * @as(i128, (std.time.ns_per_s / 100));
    return adjusted_epoch * 100;
}

// days since epoch Oct 1, 1970
fn Day(comptime T: type) type {
    return struct {
        day: T,

        const Self = @This();

        pub fn calculateYearDay(self: Self) std.time.epoch.YearAndDay {
            if (self.day >= 0) {
                var year_day = self.day;
                var year: std.time.epoch.Year = std.time.epoch.epoch_year;
                while (true) {
                    const year_size = std.time.epoch.getDaysInYear(year);
                    if (year_day < year_size)
                        break;
                    year_day -= year_size;
                    year += 1;
                }
                return .{ .year = year, .day = @as(u9, @intCast(year_day)) };
            } else {
                var days_remaining = -self.day; // Make positive for calculation
                var year: std.time.epoch.Year = std.time.epoch.epoch_year - 1; // Start with year before epoch
                while (true) {
                    const year_size = std.time.epoch.getDaysInYear(year);
                    if (days_remaining <= year_size)
                        break;
                    days_remaining -= year_size;
                    year -= 1;
                }
                const day_in_year = std.time.epoch.getDaysInYear(year) - days_remaining;
                return .{ .year = year, .day = @as(u9, @intCast(day_in_year)) };
            }
        }
    };
}

const secs_per_day: comptime_int = 24 * 60 * 60;
fn DayFromSeconds(comptime SecondsInt: type) type {
    return Day(std.math.IntFittingRange(
        @divFloor(std.math.minInt(SecondsInt), secs_per_day),
        @divFloor(std.math.maxInt(SecondsInt), secs_per_day),
    ));
}
/// seconds since epoch Oct 1, 1970 at 12:00 AM
fn Seconds(comptime T: type) type {
    return struct {
        secs: T,

        const Self = @This();

        /// Returns the number of days since the epoch as an EpochDay.
        /// Use EpochDay to get information about the day of this time.
        pub fn getEpochDay(self: Self) DayFromSeconds(T) {
            return .{
                .day = @intCast(@divFloor(self.secs, std.time.epoch.secs_per_day)),
            };
        }

        /// Returns the number of seconds into the day as DaySeconds.
        /// Use DaySeconds to get information about the time.
        pub fn getDaySeconds(self: Self) std.time.epoch.DaySeconds {
            if (self.secs >= 0) return std.time.epoch.DaySeconds{ .secs = std.math.comptimeMod(self.secs, std.time.epoch.secs_per_day) };
            // For negative seconds, we need to find how many seconds into the day we are

            // Calculate how many seconds into the day, ensuring it's positive and within the valid range
            // First, get the absolute value of seconds and take modulo with secs_per_day
            const abs_secs = @abs(self.secs);
            const secs_into_prev_day = @mod(abs_secs, std.time.epoch.secs_per_day);

            // For negative timestamps, we need to calculate the offset from the start of the day
            // If secs_into_prev_day is 0, we're exactly at the start of a day
            const day_seconds = if (secs_into_prev_day == 0) 0 else std.time.epoch.secs_per_day - secs_into_prev_day;

            return std.time.epoch.DaySeconds{ .secs = @as(u17, @intCast(day_seconds)) };
        }
    };
}

fn listDir(
    writer: BufferedWriter.Writer,
    dir: std.fs.Dir,
    opt: Options,
) !Success {
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (opt.long) {
            var sub_file = try fs.open(dir, entry.name, .{});
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
