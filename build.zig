const std = @import("std");

pub fn build(b: *std.Build) void {
    @setEvalBranchQuota(10000);
    const target_query = comptime std.Target.Query.parse(.{
        .arch_os_abi = "thumb-freestanding-eabihf",
        .cpu_features = "cortex_m7+thumb2",
    }) catch unreachable;
    const target = b.resolveTargetQuery(target_query);

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addObject(.{
        .name = "numworks-app-zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.addObjectFile(b.path("icon.o"));
    exe.root_module.single_threaded = true;
    exe.root_module.strip = true;
    exe.stack_size = 32 * 1024; // about 8 KiB of stack sounds reasonable
    exe.bundle_compiler_rt = true;
    // exe.want_lto = true;
    // exe.link_emit_relocs = true;
    // exe.root_module.export_symbol_names = &.{ "rodata", ".rodata.eadk_app_name" };
    // exe.no_builtin = true;

    // const zalgebra_dep = b.dependency("zalgebra", .{ .target = target, .optimize = optimize });
    // exe.addModule("zalgebra", zalgebra_dep.module("zalgebra"));

    const generateIcon = b.addSystemCommand(&.{ "npx", "--yes", "--", "nwlink@0.0.19", "png-icon-o", "src/assets/icon.png", "icon.o" });
    exe.step.dependOn(&generateIcon.step);

    const install_exe = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .prefix } });
    install_exe.step.dependOn(&exe.step);

    const run_cmd = b.addSystemCommand(&.{ "npx", "--yes", "--", "nwlink@0.0.19", "install-nwa", "zig-out/numworks-app-zig.o" });
    run_cmd.step.dependOn(&install_exe.step);

    const run_step = b.step("run", "Upload and run the app (a NumWorks calculator must be connected)");
    run_step.dependOn(&run_cmd.step);
}
