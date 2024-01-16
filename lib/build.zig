const std = @import("std");
const CrossTarget = std.zig.CrossTarget;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const native_lib = b.addStaticLibrary(.{
        .name = "alternis",
        .root_source_file = .{ .path = "src/c_api.zig" },
        .target = target,
        .optimize = optimize,
    });
    native_lib.force_pic = true;
    // FIXME: avoid doing this except for the godot case,
    // otherwise roundq is undefined reference when linked into the gdextension
    native_lib.bundle_compiler_rt = true;
    b.installArtifact(native_lib);

    const shared_lib = b.addSharedLibrary(.{
        .name = "alternis",
        .root_source_file = .{ .path = "src/c_api.zig" },
        .target = target,
        .optimize = optimize,
    });
    shared_lib.force_pic = true;
    b.installArtifact(shared_lib);

    const test_filter = b.option([]const u8, "test-filter", "filter for test subcommand");
    const main_tests = b.addTest(.{ .root_source_file = .{ .path = "src/c_api.zig" }, .target = target, .optimize = optimize, .filter = test_filter });
    main_tests.linkLibC(); // c api tests use libc malloc as the user configured allocator
    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    var web_target = target;
    web_target.cpu_arch = .wasm32;
    web_target.os_tag = .freestanding;

    const web_step = b.step("web", "Build for web");
    const web_lib = b.addSharedLibrary(.{
        .name = "alternis",
        .root_source_file = std.build.FileSource.relative("src/wasm_main.zig"),
        .target = web_target,
        .optimize = optimize,
    });
    web_lib.rdynamic = true;
    web_lib.export_symbol_names = &.{"ade_set_alloc"};
    b.installArtifact(web_lib);
    const web_lib_install = b.addInstallArtifact(web_lib, .{});
    web_step.dependOn(&web_lib_install.step);

    const all_step = b.step("all", "Build for all supported platforms");

    const supported_platforms = [_][]const u8{ "x86_64-windows", "x86_64-macos", "aarch64-macos", "x86_64-linux" };

    for (supported_platforms) |platform| {
        const platform_target = CrossTarget.parse(.{ .arch_os_abi = platform }) catch unreachable;
        // NOTE: this temporary is ok because it returns a pointer that we don't own
        const lib = b.addStaticLibrary(.{
            .name = "alternis",
            .root_source_file = std.build.FileSource.relative("src/c_api.zig"),
            .target = platform_target,
            .optimize = optimize,
        });
        lib.force_pic = true;
        // FIXME: avoid doing this except for the godot case,
        // otherwise roundq is undefined reference when linked into the gdextension
        lib.bundle_compiler_rt = true;
        const install_lib = b.addInstallArtifact(lib, .{});
        all_step.dependOn(&install_lib.step);
    }

    all_step.dependOn(&web_lib_install.step);
}
