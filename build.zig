// tested with zig version 0.11.0
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // NOTE: timer is supposed to be "time" but can't use that on windows
    //       because time is a builtin cmd-prompt function.
    const tools: []const []const u8 = &.{ "touch", "rm", "timer", "ls" };
    inline for (tools) |tool| {
        const exe = b.addExecutable(.{
            .name = tool,
            .root_source_file = .{ .path = tool ++ ".zig" },
            .target = target,
            .optimize = optimize,
        });
        const install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .prefix },
        });
        b.getInstallStep().dependOn(&install.step);
    }
}
