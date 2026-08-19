const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const current_version = builtin.zig_version;


    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/lib/root.zig"),
    });

    const frontend_mod = b.createModule(.{
        .root_source_file = b.path("src/frontend/root.zig"),
        .imports = &.{
            .{ .name = "lib", .module = lib_mod },
        },
    });

    const ir_mod = b.createModule(.{
        .root_source_file = b.path("src/ir/root.zig"),
        .imports = &.{
            .{ .name = "frontend", .module = frontend_mod },
        },
    });

    const cli_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/cli.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "richeh",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "frontend", .module = frontend_mod },
                .{ .name = "cli", .module = cli_mod },
                .{ .name = "ir", .module = ir_mod },
            },
        }),
    });

    b.installArtifact(exe);
    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (current_version.major == 0 and current_version.minor == 17) {
        run_cmd.addPassthruArgs(); 
    } else {
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
    }
}
