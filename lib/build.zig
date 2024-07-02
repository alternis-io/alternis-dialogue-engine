const std = @import("std");
const CrossTarget = std.zig.CrossTarget;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const native_lib = b.addStaticLibrary(.{
        .name = "alternis",
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true,
    });
    // FIXME: avoid doing this except for the godot case,
    // otherwise roundq is undefined reference when linked into the gdextension
    native_lib.bundle_compiler_rt = true;
    b.installArtifact(native_lib);

    const shared_lib = b.addSharedLibrary(.{
        .name = "alternis",
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true,
    });
    b.installArtifact(shared_lib);
    //const install_shared_header = b.addInstallFile(shared_lib.getEmittedH(), "api.h");
    //b.getInstallStep().dependOn(&install_shared_header.step);

    const test_filter = b.option([]const u8, "test-filter", "filter for test subcommand");
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
        .filter = test_filter,
    });
    main_tests.linkLibC(); // c api tests use libc malloc as the user configured allocator
    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    var web_target = target;
    web_target.result.cpu.arch = .wasm32;
    web_target.result.os.tag = .freestanding;

    const web_step = b.step("web", "Build for web");
    const web_lib = b.addSharedLibrary(.{
        .name = "alternis",
        .root_source_file = .{ .cwd_relative = "src/wasm_main.zig" },
        .target = web_target,
        .optimize = optimize,
    });
    web_lib.rdynamic = true;
    // FIXME: zig 0.12
    // web_lib.export_symbol_names = &.{"ade_set_alloc"};
    b.installArtifact(web_lib);
    const web_lib_install = b.addInstallArtifact(web_lib, .{});
    web_step.dependOn(&web_lib_install.step);

    const all_step = b.step("all", "Build for all supported platforms");

    const supported_platforms = [_][]const u8{
        // MSVC is the most common ABI on windows, needed to link into an e.g. Unreal Engine plugin
        "x86_64-windows-msvc",
        "x86_64-macos",
        "aarch64-macos",
        "x86_64-linux",
    };

    inline for (supported_platforms) |platform| {
        const platform_target = CrossTarget.parse(.{ .arch_os_abi = platform }) catch unreachable;
        // NOTE: this temporary is ok because it returns a pointer that we don't own
        const name = std.fmt.comptimePrint("alternis-{s}", .{platform});
        const lib = b.addStaticLibrary(.{
            .name = name,
            .root_source_file = .{ .cwd_relative = "src/c_api.zig" },
            .target = b.resolveTargetQuery(platform_target),
            .optimize = optimize,
            .pic = true,
        });
        //const install_header = b.addInstallFile(lib.getEmittedH(), "api.h");
        // FIXME: avoid doing this except for the godot case,
        // otherwise roundq is undefined reference when linked into the gdextension
        lib.bundle_compiler_rt = true;
        const install_lib = b.addInstallArtifact(lib, .{});

        // FIXME: this doesn't work... the consumer must link with this
        // FIXME: try this https://stackoverflow.com/questions/75185166/how-to-bundle-a-static-library-with-an-import-library-or-two-static-libraries
        if (std.mem.endsWith(u8, platform, "-msvc")) {
            //std.log.
            lib.addLibraryPath(b.path("C:/Program Files (x86)/Windows Kits/10/Lib/10.0.18362.0/um/x64"));
            lib.linkSystemLibrary2("ntdll", .{ .needed = true });
        }

        //all_step.dependOn(&install_header.step);
        all_step.dependOn(&install_lib.step);
    }

    all_step.dependOn(&web_lib_install.step);
}
