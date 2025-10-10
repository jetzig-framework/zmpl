const std = @import("std");
const Build = std.Build;
const ArrayList = std.array_list.Managed;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

pub const Data = @import("src/zmpl.zig").Data;
const zmd = @import("zmd");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const use_llvm = b.option(bool, "use_llvm", "Use LLVM") orelse true;

    const zmpl = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/zmpl.zig"),
    });

    const lib = b.addLibrary(.{
        .name = "zmpl",
        .linkage = .static,
        .use_llvm = use_llvm,
        .root_module = zmpl,
    });

    const entry = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "zmpl",
        .use_llvm = use_llvm,
        .root_module = entry,
    });

    const run_artifact = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run benchmarking");
    run_step.dependOn(&run_artifact.step);

    const zmpl_module = b.addModule("zmpl", .{ .root_source_file = b.path("src/zmpl.zig") });
    lib.root_module.addImport("zmpl", zmpl_module);
    exe.root_module.addImport("zmpl", zmpl_module);

    const build_options = b.addOptions();
    build_options.addOption(
        bool,
        "sanitize",
        b.option(bool, "sanitize", "Disable default sanitization of data references.") orelse true,
    );
    zmpl_module.addOptions("build_options", build_options);

    const zmd_module = b.dependency("zmd", .{
        .target = target,
        .optimize = optimize,
    }).module("zmd");
    lib.root_module.addImport("zmd", zmd_module);
    zmpl_module.addImport("zmd", zmd_module);

    const jetcommon_dep = b.dependency("jetcommon", .{ .target = target, .optimize = optimize });
    const jetcommon_module = jetcommon_dep.module("jetcommon");
    lib.root_module.addImport("jetcommon", jetcommon_module);
    zmpl_module.addImport("jetcommon", jetcommon_module);

    const zmpl_constants_option = b.option([]const u8, "zmpl_constants", "Template constants");

    const templates_path = b.option(
        []const u8,
        "zmpl_templates_path",
        "Directories to search for .zmpl templates. (Deprecated: Use `zmpl_templates_paths`)",
    );

    const templates_paths_option = b.option(
        []const []const u8,
        "zmpl_templates_paths",
        "Directories to search for .zmpl templates. Format: `prefix=...,path=...",
    );

    const zmpl_markdown_fragments_option = b.option([]const u8, "zmpl_markdown_fragments", "Custom markdown fragments");
    const zmpl_options_header_option = b.option([]const u8, "zmpl_options_header", "Additional options header");
    const zmpl_manifest_header_option = b.option([]const u8, "zmpl_manifest_header", "Additional manifest header");

    const templates_paths: []const []const u8 = if (templates_path) |path|
        try templatesPaths(
            b.allocator,
            &.{.{ .prefix = "templates", .path = try splitPath(b.allocator, path) }},
        )
    else
        templates_paths_option orelse try templatesPaths(
            b.allocator,
            &.{.{
                .prefix = "templates",
                .path = &.{ "src", "templates" },
            }},
        );

    const zmpl_auto_build_option = b.option(
        bool,
        "zmpl_auto_build",
        "Automatically compile Zmpl templates (default: true)",
    );
    const auto_build = if (zmpl_auto_build_option) |opt| opt else true;

    const manifest = b.createModule(.{
        .root_source_file = b.path("src/manifest/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const manifest_exe = b.addExecutable(.{
        .name = "manifest",
        .use_llvm = use_llvm,
        .root_module = manifest,
    });

    const options_files = b.addWriteFiles();
    const zmpl_constants_file = options_files.add(
        "zmpl_options.zig",
        try generateZmplOptions(b.allocator, zmpl_options_header_option, zmpl_markdown_fragments_option, zmpl_constants_option, zmpl_manifest_header_option),
    );
    const zmpl_options_module = b.addModule("zmpl_options", .{ .root_source_file = zmpl_constants_file });
    zmpl_options_module.addImport("zmd", zmd_module);
    manifest_exe.root_module.addImport("zmpl_options", zmpl_options_module);
    manifest_exe.root_module.addImport("zmd", zmd_module);
    manifest_exe.root_module.addImport("jetcommon", jetcommon_module);
    const manifest_exe_run = b.addRunArtifact(manifest_exe);
    b.getInstallStep().dependOn(&manifest_exe_run.step);
    const manifest_lazy_path = manifest_exe_run.addOutputFileArg("zmpl.manifest.zig");

    manifest_exe_run.setCwd(.{ .cwd_relative = try std.fs.cwd().realpathAlloc(b.allocator, ".") });
    manifest_exe_run.expectExitCode(0);
    manifest_exe_run.addArg(try std.mem.join(b.allocator, ";", templates_paths));

    lib.step.dependOn(&manifest_exe_run.step);
    for (try findTemplates(b, templates_paths)) |path| manifest_exe_run.addFileArg(.{ .cwd_relative = path });
    const compile_step = b.step("compile", "Compile Zmpl templates");
    compile_step.dependOn(&manifest_exe_run.step);

    const manifest_module = b.addModule("zmpl.manifest", .{ .root_source_file = manifest_lazy_path });
    manifest_module.addImport("zmpl", zmpl_module);
    manifest_module.addImport("zmd", zmd_module);
    zmpl_module.addImport("zmpl.manifest", manifest_module);

    if (auto_build) {
        const tests_path = "src/tests.zig";

        const test_filters = b.option([]const []const u8, "test-filter", "Skip tests that do not match any filter") orelse &.{};
        const template_tests = b.addTest(.{
            .filters = test_filters,
            .root_module = b.createModule(.{
                .root_source_file = b.path(tests_path),
                .target = target,
                .optimize = optimize,
            }),
        });

        const zmpl_tests = b.addTest(.{
            .filters = test_filters,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/zmpl.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });

        const manifest_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/manifest/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
            .filters = test_filters,
        });

        template_tests.root_module.addImport("zmpl", zmpl_module);
        template_tests.root_module.addImport("zmpl.manifest", manifest_module);
        template_tests.root_module.addImport("jetcommon", jetcommon_module);

        const dummy_manifest_module = b.createModule(
            .{ .root_source_file = b.path("src/dummy_manifest.zig") },
        );
        zmpl_tests.root_module.addImport("jetcommon", jetcommon_module);
        zmpl_tests.root_module.addImport("zmpl.manifest", dummy_manifest_module);
        zmpl_tests.root_module.addImport("zmd", zmd_module);

        const dummy_zmpl_options_module = b.createModule(
            .{ .root_source_file = b.path("src/manifest/dummy_zmpl_options.zig") },
        );
        manifest_tests.root_module.addImport("zmpl_options", dummy_zmpl_options_module);
        manifest_tests.root_module.addImport("zmd", zmd_module);

        const run_template_tests = b.addRunArtifact(template_tests);
        const run_zmpl_tests = b.addRunArtifact(zmpl_tests);
        const run_manifest_tests = b.addRunArtifact(manifest_tests);

        const test_step = b.step("test", "Run library tests");
        test_step.dependOn(&run_template_tests.step);
        test_step.dependOn(&run_zmpl_tests.step);
        test_step.dependOn(&run_manifest_tests.step);
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

const TemplatesPath = struct {
    prefix: []const u8,
    path: []const []const u8,
};

pub fn templatesPaths(allocator: Allocator, paths: []const TemplatesPath) ![]const []const u8 {
    var buf = ArrayList([]const u8).init(allocator);
    for (paths) |path| {
        const joined = try std.fs.path.join(allocator, path.path);
        defer allocator.free(joined);

        const absolute_path = if (std.fs.path.isAbsolute(joined))
            try allocator.dupe(u8, joined)
        else
            std.fs.cwd().realpathAlloc(allocator, joined) catch |err|
                switch (err) {
                    error.FileNotFound => "_",
                    else => return err,
                };

        try buf.append(
            try std.mem.concat(allocator, u8, &.{ "prefix=", path.prefix, ",path=", absolute_path }),
        );
    }

    return buf.toOwnedSlice();
}

pub fn addTemplateConstants(b: *Build, comptime constants: type) ![]const u8 {
    const fields = switch (@typeInfo(constants)) {
        .@"struct" => |info| info.fields,
        else => @panic("Expected struct, found: " ++ @typeName(constants)),
    };
    var array: [fields.len][]const u8 = undefined;

    inline for (fields, 0..) |field, index| {
        array[index] = std.fmt.comptimePrint(
            "{s}#{s}",
            .{ field.name, @typeName(field.type) },
        );
    }

    return std.mem.join(b.allocator, "|", &array);
}

fn findTemplates(b: *Build, templates_paths: []const []const u8) ![][]const u8 {
    var templates = ArrayList([]const u8).init(b.allocator);

    var templates_paths_buf = ArrayList([]const u8).init(b.allocator);
    defer templates_paths_buf.deinit();
    for (templates_paths) |syntax| {
        const prefix_end = std.mem.indexOf(u8, syntax, ",path=").?;
        const path_start = prefix_end + ",path=".len;
        const path = syntax[path_start..];
        try templates_paths_buf.append(path);
    }

    for (templates_paths_buf.items) |templates_path| {
        if (std.mem.eql(u8, templates_path, "_")) continue;

        var dir = std.fs.cwd().openDir(templates_path, .{ .iterate = true }) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    std.log.warn(
                        "[zmpl] Template directory `{s}` not found, skipping.",
                        .{templates_path},
                    );
                    continue;
                },
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
    }
    return templates.toOwnedSlice();
}

fn generateZmplOptions(
    allocator: Allocator,
    options_header_option: ?[]const u8,
    markdown_fragments: ?[]const u8,
    constants: ?[]const u8,
    manifest_header_option: ?[]const u8,
) ![]const u8 {
    const constants_source = try parseZmplConstants(allocator, constants);

    const manifest_header = manifest_header_option orelse "";
    const encodedHeader: []u8 = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(manifest_header.len));
    defer allocator.free(encodedHeader);
    const base64Header = std.base64.standard.Encoder.encode(encodedHeader, manifest_header);

    return try std.fmt.allocPrint(allocator,
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\pub const manifest_header: []const u8 = "{s}";
        \\
    , .{ options_header_option orelse "", constants_source, markdown_fragments orelse "", base64Header });
}

fn parseZmplConstants(allocator: Allocator, constants_string: ?[]const u8) ![]const u8 {
    if (constants_string) |string| {
        var array = ArrayList(u8).init(allocator);
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
                std.log.err("Incoherent Zmpl constants argument: {?s}", .{constants_string});
                return error.ZmplConstantsOptionError;
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

fn splitPath(allocator: Allocator, path: []const u8) ![]const []const u8 {
    var it = std.mem.tokenizeSequence(u8, path, std.fs.path.sep_str);
    var buf = ArrayList([]const u8).init(allocator);
    while (it.next()) |segment| try buf.append(segment);

    return buf.toOwnedSlice();
}
