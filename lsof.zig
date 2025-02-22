const builtin = @import("builtin");
const std = @import("std");
const win32 = @import("win32").everything;

fn errExit(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    std.process.exit(0xff);
}

pub fn main() !u8 {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_instance.allocator();

    const all_args = try std.process.argsAlloc(arena);
    if (all_args.len <= 1) {
        try std.io.getStdErr().writer().writeAll("Usage: lsof PATH\n");
        std.process.exit(0xff);
    }

    const path_a = all_args[1];
    const path_w = try std.unicode.wtf8ToWtf16LeAllocZ(arena, path_a);

    var session: u32 = undefined;
    var session_key: [win32.CCH_RM_SESSION_KEY:0]u16 = undefined;
    switch (win32.RmStartSession(&session, 0, &session_key)) {
        0 => {},
        else => |e| errExit("RmStartSession failed, error={}", .{e}),
    }
    defer switch (win32.RmEndSession(session)) {
        0 => {},
        else => |e| errExit("RmEndSession failed, error={}", .{e}),
    };

    //std.log.info("session '{}'", .{std.unicode.fmtUtf16le(&session_key)});
    const filenames = [_]?[*:0]u16{
        path_w.ptr,
    };
    switch (win32.RmRegisterResources(session, 1, @constCast(@ptrCast(&filenames)), 0, null, 0, null)) {
        0 => {},
        else => |e| errExit("RmRegisterResources failed, error={}", .{e}),
    }

    var proc_info_count_needed: u32 = undefined;
    const max_proc_info = 100;
    var proc_info_count: u32 = max_proc_info;
    var proc_infos: [max_proc_info]win32.RM_PROCESS_INFO = undefined;
    var reason: u32 = undefined;
    switch (win32.RmGetList(session, &proc_info_count_needed, &proc_info_count, &proc_infos, &reason)) {
        0 => {},
        else => |e| errExit("RmGetList failed, error={}", .{e}),
    }

    //std.log.info("needed={} count={} reason={}", .{ proc_info_count_needed, proc_info_count, reason });
    var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
    const w = bw.writer();
    try w.print("{} process(es):\n", .{proc_info_count});
    for (0..proc_info_count) |i| {
        try w.print(
            "{} {}\n",
            .{
                proc_infos[i].Process.dwProcessId,
                //@tagName(proc_infos[i].ApplicationType),
                std.unicode.fmtUtf16le(span(u16, &proc_infos[i].strAppName)),
                //std.unicode.fmtUtf16le(span(u16, &proc_infos[i].strServiceShortName)),
            },
        );
    }
    try bw.flush();

    return 0;
}

fn span(comptime T: type, slice: []const T) []const T {
    for (slice, 0..) |c, i| {
        if (c == 0) return slice[0..i];
    }
    return slice;
}
