const std = @import("std");
const builtin = @import("builtin");

pub const zmpl = @import("src/zmpl.zig");
pub const Data = zmpl.Data;
pub const Template = zmpl.Template;
pub const ZmplBuild = @import("src/zmpl/Build.zig");

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

    const zmpl_auto_build_option = b.option(
        bool,
        "zmpl_auto_build",
        "Automatically compile Zmpl templates (default: true)",
    );
    const auto_build = if (zmpl_auto_build_option) |opt| opt else true;

    if (auto_build) {
        var zmpl_build = ZmplBuild.init(b, lib, templates_path);
        const manifest_module = try zmpl_build.compile(Template, struct {});
        zmpl_module.addImport("zmpl.manifest", manifest_module);

        const main_tests = b.addTest(.{
            .root_source_file = .{ .path = "src/tests.zig" },
            .target = target,
            .optimize = optimize,
        });

        main_tests.root_module.addImport("zmpl", zmpl_module);
        main_tests.root_module.addImport("zmpl.manifest", manifest_module);
        const run_main_tests = b.addRunArtifact(main_tests);
        const test_step = b.step("test", "Run library tests");
        test_step.dependOn(&run_main_tests.step);
    }

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    const docs_step = b.step("docs", "Generate documentation");
    const docs_install = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    docs_step.dependOn(&docs_install.step);
}
