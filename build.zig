const std = @import("std");
const builtin = @import("builtin");

const zmpl = @import("src/zmpl.zig");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "zmpl",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/zmpl.zig" },
        .target = target,
        .optimize = optimize,
    });

    const zmpl_module = b.addModule("zmpl", .{ .root_source_file = .{ .path = "src/zmpl.zig" } });
    lib.root_module.addImport("zmpl", zmpl_module);

    const templates_path = b.option(
        []const u8,
        "zmpl_templates_path",
        "Directory to search for .zmpl templates.",
    ) orelse try std.fs.path.join(b.allocator, &[_][]const u8{ "src", "templates" });
    const manifest_path = b.option(
        []const u8,
        "zmpl_manifest_path",
        "Zmpl auto-generated manifest path.",
    ) orelse try std.fs.path.join(b.allocator, &[_][]const u8{ templates_path, "zmpl.manifest.zig" });

    try zmpl.init(b, lib, .{
        .manifest_path = manifest_path,
        .templates_path = templates_path,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });

    main_tests.root_module.addImport("zmpl", zmpl_module);
    const run_main_tests = b.addRunArtifact(main_tests);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
