const std = @import("std");
const builtin = @import("builtin");

pub const zmpl = @import("src/zmpl.zig");
pub const Data = zmpl.Data;
pub const Template = zmpl.Template;
pub const ModalTemplate = zmpl.ModalTemplate;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "zmpl",
        .root_source_file = .{ .path = "src/zmpl.zig" },
        .target = target,
        .optimize = optimize,
    });

    const zmpl_module = b.addModule("zmpl", .{ .root_source_file = .{ .path = "src/zmpl.zig" } });
    lib.root_module.addImport("zmpl", zmpl_module);

    const zmd_dep = b.dependency("zmd", .{ .target = target, .optimize = optimize });
    const zmd_module = zmd_dep.module("zmd");
    lib.root_module.addImport("zmd", zmd_module);

    const zmpl_constants_option = b.option([]const u8, "zmpl_constants", "Template constants");

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
    const zmpl_version_option = b.option(enum { v1, v2 }, "zmpl_version", "Zmpl version");
    const zmpl_version = zmpl_version_option orelse .v2;

    const manifest_exe = b.addExecutable(.{
        .name = "manifest",
        .root_source_file = .{ .path = "src/manifest/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const options_files = b.addWriteFiles();
    const zmpl_constants_file = options_files.add(
        "zmpl_options.zig",
        try parseZmplConstants(b.allocator, zmpl_constants_option),
    );
    manifest_exe.root_module.addImport(
        "zmpl_options",
        b.createModule(.{ .root_source_file = zmpl_constants_file }),
    );
    manifest_exe.root_module.addImport("zmd", zmd_module);
    const manifest_exe_run = b.addRunArtifact(manifest_exe);
    const manifest_lazy_path = manifest_exe_run.addOutputFileArg("zmpl.manifest.zig");

    manifest_exe_run.expectExitCode(0);
    manifest_exe_run.addArg(templates_path);
    manifest_exe_run.setEnvironmentVariable("ZMPL_VERSION", @tagName(zmpl_version));

    const templates: [][]const u8 = if (std.mem.eql(u8, templates_path, ""))
        &.{}
    else
        findTemplates(b, templates_path) catch |err| blk: {
            switch (err) {
                error.ZmplTemplateDirectoryNotFound => {
                    std.debug.print(
                        "[zmpl] Template directory `{s}` not found, skipping compilation.\n",
                        .{templates_path},
                    );
                    break :blk &.{};
                },
                else => return err,
            }
        };

    for (templates) |path| manifest_exe_run.addFileArg(.{ .path = path });

    const manifest_module = b.addModule("zmpl.manifest", .{ .root_source_file = manifest_lazy_path });
    manifest_module.addImport("zmpl", zmpl_module);
    zmpl_module.addImport("zmpl.manifest", manifest_module);

    if (auto_build) {
        const tests_path = switch (zmpl_version) {
            .v1 => "src/tests_v1.zig",
            .v2 => "src/tests.zig",
        };

        const main_tests = b.addTest(.{
            .root_source_file = .{ .path = tests_path },
            .target = target,
            .optimize = optimize,
        });

        main_tests.root_module.addImport("zmpl", zmpl_module);
        main_tests.root_module.addImport("zmpl.manifest", manifest_module);
        const run_main_tests = b.addRunArtifact(main_tests);
        const test_step = b.step("test", "Run library tests");
        test_step.dependOn(&run_main_tests.step);
    }

    b.installArtifact(lib);

    const docs_step = b.step("docs", "Generate documentation");
    const docs_install = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    docs_step.dependOn(&docs_install.step);
}

pub fn addTemplateConstants(b: *std.Build, comptime constants: type) ![]const u8 {
    const fields = switch (@typeInfo(constants)) {
        .Struct => |info| info.fields,
        else => @panic("Expected struct, found: " ++ @typeName(constants)),
    };
    var array: [fields.len][]const u8 = undefined;

    inline for (fields, 0..) |field, index| {
        array[index] = std.fmt.comptimePrint(
            "{s}#{s}",
            .{ field.name, @typeName(field.type) },
        );
    }

    return try std.mem.join(b.allocator, "|", &array);
}

fn findTemplates(b: *std.Build, templates_path: []const u8) ![][]const u8 {
    var templates = std.ArrayList([]const u8).init(b.allocator);

    var dir = std.fs.cwd().openDir(templates_path, .{ .iterate = true }) catch |err| {
        switch (err) {
            error.FileNotFound => return error.ZmplTemplateDirectoryNotFound,
            else => return err,
        }
    };

    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        const extension = std.fs.path.extension(entry.path);
        if (!std.mem.eql(u8, extension, ".zmpl")) continue;
        try templates.append(try dir.realpathAlloc(b.allocator, entry.path));
    }
    return try templates.toOwnedSlice();
}

fn parseZmplConstants(allocator: std.mem.Allocator, constants_string: ?[]const u8) ![]const u8 {
    if (constants_string) |string| {
        var array = std.ArrayList(u8).init(allocator);
        var pairs_it = std.mem.splitScalar(u8, string, '|');
        try array.appendSlice("pub const template_constants = struct {\n");
        while (pairs_it.next()) |pair| {
            var arg_it = std.mem.splitScalar(u8, pair, '#');
            var index: u2 = 0;
            var const_name: []const u8 = undefined;
            var const_type: []const u8 = undefined;
            while (arg_it.next()) |arg| : (index += 1) {
                if (index == 0) {
                    const_name = arg;
                } else if (index == 1) {
                    const_type = arg;
                } else {
                    break;
                }
            }
            if (index > 2) {
                std.debug.print("Incoherent Zmpl constants argument: {?s}\n", .{constants_string});
                return error.ZmplConstantsOptionErrro;
            }
            try array.appendSlice(try std.fmt.allocPrint(
                allocator,
                "    {s}: {s},\n",
                .{ const_name, const_type },
            ));
        }
        try array.appendSlice("};\n");
        return try array.toOwnedSlice();
    } else return "";
}
