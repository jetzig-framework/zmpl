const std = @import("std");
const Build = std.Build;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const builtin = @import("builtin");
const Encoder = std.base64.standard.Encoder;
const Data = @import("src/zmpl.zig").Data;
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options_files = b.addWriteFiles();

    const use_llvm = b.option(
        bool,
        "use_llvm",
        "Use LLVM",
    );

    const test_filters = b.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match any filter",
    ) orelse &.{};

    const zmpl_auto_build_option = b.option(
        bool,
        "zmpl_auto_build",
        "Automatically compile Zmpl templates (default: true)",
    );

    const zmpl_markdown_fragments_option = b.option(
        []const u8,
        "zmpl_markdown_fragments",
        "Custom markdown fragments",
    ) orelse "";

    const zmpl_options_header_option = b.option(
        []const u8,
        "zmpl_options_header",
        "Additional options header",
    ) orelse "";

    const zmpl_manifest_header_option = b.option(
        []const u8,
        "zmpl_manifest_header",
        "Additional manifest header",
    ) orelse "";

    const zmpl_constants_option = b.option(
        []const u8,
        "zmpl_constants",
        "Template constants",
    ) orelse "";

    const templates_paths = b.option(
        []const []const u8,
        "zmpl_templates_paths",
        "Directories to search for .zmpl templates. Format: `prefix=...,path=...",
    ) orelse try templatesPaths(
        b.allocator,
        &.{.{
            .prefix = "templates",
            .path = &.{ "src", "templates" },
        }},
    );

    const build_options = b.addOptions();
    build_options.addOption(
        bool,
        "sanitize",
        b.option(
            bool,
            "sanitize",
            "Disable default sanitization of data references.",
        ) orelse true,
    );

    const zmpl_options = b.addModule("zmpl_options", .{
        .root_source_file = options_files.add(
            "zmpl_options.zig",
            try generateZmplOptions(
                b.allocator,
                zmpl_options_header_option,
                zmpl_markdown_fragments_option,
                zmpl_constants_option,
                zmpl_manifest_header_option,
            ),
        ),
    });

    const zmd = b.dependency("zmd", .{
        .target = target,
        .optimize = optimize,
    }).module("zmd");

    const jetcommon = b.dependency("jetcommon", .{
        .target = target,
        .optimize = optimize,
    }).module("jetcommon");

    const entry = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });

    const manifest_m = b.createModule(.{
        .root_source_file = b.path("src/manifest/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const manifest_exe = b.addExecutable(.{
        .name = "manifest",
        .use_llvm = use_llvm,
        .root_module = manifest_m,
    });

    const zmpl = b.addModule("zmpl", .{
        .root_source_file = b.path("src/zmpl.zig"),
    });

    const dummy_manifest = b.createModule(.{
        .root_source_file = b.path("src/dummy_manifest.zig"),
    });

    const dummy_zmpl_options = b.createModule(.{
        .root_source_file = b.path("src/manifest/dummy_zmpl_options.zig"),
    });

    const tests = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zmpl_m = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/zmpl.zig"),
    });

    const lib = b.addLibrary(.{
        .name = "zmpl",
        .linkage = .static,
        .use_llvm = use_llvm,
        .root_module = zmpl_m,
    });

    const exe = b.addExecutable(.{
        .name = "zmpl",
        .use_llvm = use_llvm,
        .root_module = entry,
    });

    const run_artifact = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run benchmarking");
    run_step.dependOn(&run_artifact.step);

    lib.root_module.addImport("zmpl", zmpl);
    exe.root_module.addImport("zmpl", zmpl);

    zmpl.addOptions("build_options", build_options);

    lib.root_module.addImport("zmd", zmd);
    zmpl.addImport("zmd", zmd);

    lib.root_module.addImport("jetcommon", jetcommon);
    zmpl.addImport("jetcommon", jetcommon);

    const auto_build = if (zmpl_auto_build_option) |opt| opt else true;

    zmpl_options.addImport("zmd", zmd);
    manifest_exe.root_module.addImport("zmpl_options", zmpl_options);
    manifest_exe.root_module.addImport("zmd", zmd);
    manifest_exe.root_module.addImport("jetcommon", jetcommon);

    const manifest_exe_run = b.addRunArtifact(manifest_exe);
    b.getInstallStep().dependOn(&manifest_exe_run.step);
    const manifest_lazy_path = manifest_exe_run.addOutputFileArg("zmpl.manifest.zig");

    manifest_exe_run.setCwd(.{
        .cwd_relative = try std.fs.cwd().realpathAlloc(b.allocator, "."),
    });
    manifest_exe_run.expectExitCode(0);
    manifest_exe_run.addArg(try std.mem.join(b.allocator, ";", templates_paths));

    lib.step.dependOn(&manifest_exe_run.step);

    for (try findTemplates(b, templates_paths)) |path|
        manifest_exe_run.addFileArg(.{ .cwd_relative = path });

    const compile_step = b.step("compile", "Compile Zmpl templates");
    compile_step.dependOn(&manifest_exe_run.step);

    const manifest = b.addModule("zmpl.manifest", .{
        .root_source_file = manifest_lazy_path,
    });

    manifest.addImport("zmpl", zmpl);
    manifest.addImport("zmd", zmd);
    zmpl.addImport("zmpl.manifest", manifest);

    if (auto_build) {
        const template_tests = b.addTest(.{
            .filters = test_filters,
            .root_module = tests,
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
            .filters = test_filters,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/manifest/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });

        template_tests.root_module.addImport("zmpl", zmpl);
        template_tests.root_module.addImport("zmpl.manifest", manifest);
        template_tests.root_module.addImport("jetcommon", jetcommon);

        zmpl_tests.root_module.addImport("jetcommon", jetcommon);
        zmpl_tests.root_module.addImport("zmpl.manifest", dummy_manifest);
        zmpl_tests.root_module.addImport("zmd", zmd);

        manifest_tests.root_module.addImport("zmpl_options", dummy_zmpl_options);
        manifest_tests.root_module.addImport("zmd", zmd);

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
    var buf: ArrayList([]const u8) = .empty;
    defer buf.deinit(allocator);
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
            allocator,
            try std.mem.concat(
                allocator,
                u8,
                &.{ "prefix=", path.prefix, ",path=", absolute_path },
            ),
        );
    }

    return buf.toOwnedSlice(allocator);
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
    var templates: ArrayList([]const u8) = .empty;
    defer templates.deinit(b.allocator);

    var templates_paths_buf: ArrayList([]const u8) = .empty;
    defer templates_paths_buf.deinit(b.allocator);
    for (templates_paths) |syntax| {
        const prefix_end = std.mem.indexOf(u8, syntax, ",path=").?;
        const path_start = prefix_end + ",path=".len;
        const path = syntax[path_start..];
        try templates_paths_buf.append(b.allocator, path);
    }

    for (templates_paths_buf.items) |templates_path| {
        if (std.mem.eql(u8, templates_path, "_")) continue;

        var dir = std.fs.cwd().openDir(
            templates_path,
            .{ .iterate = true },
        ) catch |err| {
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
            try templates.append(b.allocator, try dir.realpathAlloc(b.allocator, entry.path));
        }
    }
    return templates.toOwnedSlice(b.allocator);
}

fn generateZmplOptions(
    allocator: Allocator,
    options_header_option: []const u8,
    markdown_fragments: []const u8,
    constants: []const u8,
    manifest_header_option: []const u8,
) ![]const u8 {
    var aw: Writer.Allocating = .init(allocator);

    try aw.writer.print(
        "//Generated in build.zig\n{[options]s}\n\n",
        .{ .options = options_header_option },
    );

    try parseZmplConstants(
        &aw.writer,
        constants,
    );

    const encodedHeader: []u8 = try allocator.alloc(u8, Encoder.calcSize(manifest_header_option.len));
    defer allocator.free(encodedHeader);
    const base64Header = Encoder.encode(encodedHeader, manifest_header_option);

    try aw.writer.print(
        "{s}\n\npub const manifest_header: []const u8 = \"{s}\";\n",
        .{ markdown_fragments, base64Header },
    );

    return aw.toOwnedSlice();
}

fn parseZmplConstants(writer: *Writer, constants_string: []const u8) !void {
    if (constants_string.len == 0) return;
    try writer.writeAll("pub const template_constants = struct {\n");
    var pairs_it = std.mem.splitScalar(u8, constants_string, '|');
    while (pairs_it.next()) |pair| {
        var arg_it = std.mem.splitScalar(u8, pair, '#');
        const const_name = arg_it.first();
        const const_type = arg_it.next() orelse {
            std.log.err("Incomplete Zmpl constants argument: {s}", .{constants_string});
            return error.ZmplConstantsOptionError;
        };
        // this should be null
        if (arg_it.next()) |_| {
            std.log.err("Incoherent Zmpl constants argument: {s}", .{constants_string});
            return error.ZmplConstantsOptionError;
        }
        try writer.print("    {s}: {s},\n", .{ const_name, const_type });
    }
    try writer.writeAll("};\n");
}
