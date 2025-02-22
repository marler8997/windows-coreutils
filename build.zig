const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // NOTE: timer is supposed to be "time" but can't use that on windows
    //       because time is a builtin cmd-prompt function.
    const tools: []const []const u8 = &.{ "touch", "rm", "timer", "ls", "dos2unix" };
    inline for (tools) |tool| {
        const exe = b.addExecutable(.{
            .name = tool,
            .root_source_file = b.path(tool ++ ".zig"),
            .target = target,
            .optimize = optimize,
        });
        b.installArtifact(exe);
    }
}
