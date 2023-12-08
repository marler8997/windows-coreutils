const builtin = @import("builtin");
const std = @import("std");

pub const OpenOptions = struct {
    mode: enum { read_only, read_write } = .read_only,
};

pub fn open(dir: std.fs.Dir, path: []const u8, opt: OpenOptions) !std.fs.File {
    if (builtin.os.tag == .windows) {
        const path_w = try std.os.windows.sliceToPrefixedFileW(path);
        return std.fs.File{
            .handle = try std.os.windows.OpenFile(path_w.span(), .{
                .dir = dir.fd,
                .access_mask = switch (opt.mode) {
                    .read_only => std.os.windows.SYNCHRONIZE | std.os.windows.GENERIC_READ,
                    .read_write =>
                        std.os.windows.SYNCHRONIZE |
                        std.os.windows.GENERIC_READ |
                        std.os.windows.GENERIC_WRITE,
                },
                .creation = std.os.windows.FILE_OPEN,
                .io_mode = .blocking,
                .filter = .any,
            }),
            .capable_io_mode = std.io.default_mode,
            .intended_io_mode = .blocking,
        };
    }
    return std.fs.File{
        .handle = try std.os.openat(
            dir.fd,
            path,
            switch (opt.mode) {
                .read_only => std.os.O.RDONLY,
                .read_write => std.os.O.RDWR,
            },
            0,
        ),
        .capable_io_mode = std.io.default_mode,
        .intended_io_mode = .blocking,
    };
}
