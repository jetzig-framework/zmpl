const std = @import("std");
const Build = std.Build;
const Encoder = std.base64.standard.Encoder;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const builtin = @import("builtin");

//const zmd = @import("zmd");

// pub const zmpl = @import("src/zmpl.zig");
pub const Data = @import("src/zmpl.zig").Data;

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const use_llvm = b.option(bool, "use_llvm", "Use LLVM") orelse true;

    const test_filters = b.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match any filter",
    ) orelse &.{};

    const templates_path = b.option(
        []const u8,
        "zmpl_templates_path",
        "Directories to search for .zmpl templates. (Deprecated: Use `zmpl_templates_paths`)",
    );

    const zmpl_constants_option = b.option(
        []const u8,
        "zmpl_constants",
        "Template constants",
    );

    const zmpl_auto_build_option = b.option(
        bool,
        "zmpl_auto_build",
        "Automatically compile Zmpl templates (default: true)",
    );

    const templates_paths_option = b.option(
        []const []const u8,
        "zmpl_templates_paths",
        "Directories to search for .zmpl templates. Format: `prefix=...,path=...",
    );

    const zmpl_markdown_fragments_option = b.option(
        []const u8,
        "zmpl_markdown_fragments",
        "Custom markdown fragments",
    );

    const zmpl_options_header_option = b.option(
        []const u8,
        "zmpl_options_header",
        "Additional options header",
    );

    const zmpl_manifest_header_option = b.option(
        []const u8,
        "zmpl_manifest_header",
        "Additional manifest header",
    );

    const build_options = b.addOptions();

    build_options.addOption(bool, "sanitize", b.option(
        bool,
        "sanitize",
        "Disable default sanitization of data references.",
    ) orelse true);

    const options_files = b.addWriteFiles();

    const zmpl_constants_file = options_files.add(
        "zmpl_options.zig",
        try generateZmplOptions(
            b.allocator,
            zmpl_options_header_option,
            zmpl_markdown_fragments_option,
            zmpl_constants_option,
            zmpl_manifest_header_option,
        ),
    );

    const zmpl_options = b.addModule("zmpl_options", .{
        .root_source_file = zmpl_constants_file,
    });

    const jetcommon = b.dependency("jetcommon", .{
        .target = target,
        .optimize = optimize,
    }).module("jetcommon");

    const tests = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/tests.zig"),
    });

    const zmd = b.dependency("zmd", .{
        .target = target,
        .optimize = optimize,
    }).module("zmd");

    const zmpl = b.addModule("zmpl", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/zmpl.zig"),
    });

    const entry = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });

    const manifest_entry = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/manifest/main.zig"),
    });

    const manifest = b.addExecutable(.{
        .name = "manifest",
        .root_module = manifest_entry,
        .use_llvm = use_llvm,
    });

    const dummy_manifest = b.createModule(.{
        .root_source_file = b.path("src/dummy_manifest.zig"),
    });

    const dummy_zmpl_options = b.createModule(.{
        .root_source_file = b.path("src/manifest/dummy_zmpl_options.zig"),
    });

    const lib = b.addLibrary(.{
        .name = "zmpl",
        .root_module = zmpl,
        .linkage = .static,
        .use_llvm = use_llvm,
    });

    const exe = b.addExecutable(.{
        .name = "zmpl",
        .root_module = entry,
        .use_llvm = use_llvm,
    });

    const template_tests = b.addTest(.{
        .root_module = tests,
        .filters = test_filters,
    });

    const zmpl_tests = b.addTest(.{
        .root_module = zmpl,
        .filters = test_filters,
    });

    const manifest_tests = b.addTest(.{
        .root_module = manifest_entry,
        .filters = test_filters,
    });

    zmpl.addImport("zmd", zmd);
    zmpl.addImport("jetcommon", jetcommon);
    zmpl.addOptions("build_options", build_options);

    zmpl_options.addImport("zmd", zmd);

    lib.root_module.addImport("jetcommon", jetcommon);
    lib.root_module.addImport("zmpl", zmpl);
    lib.root_module.addImport("zmd", zmd);

    exe.root_module.addImport("zmpl", zmpl);

    manifest.root_module.addImport("zmpl_options", zmpl_options);
    manifest.root_module.addImport("zmd", zmd);
    manifest.root_module.addImport("jetcommon", jetcommon);

    const run_artifact = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run benchmarking");
    run_step.dependOn(&run_artifact.step);

    const auto_build = if (zmpl_auto_build_option) |opt| opt else true;

    const manifest_exe = b.addRunArtifact(manifest);
    b.getInstallStep().dependOn(&manifest_exe.step);
    const manifest_lazy_path = manifest_exe.addOutputFileArg("zmpl.manifest.zig");

    manifest_exe.setCwd(.{
        .cwd_relative = try std.fs.cwd().realpathAlloc(b.allocator, "."),
    });
    manifest_exe.expectExitCode(0);

    const templates_paths: []const []const u8 = if (templates_path) |path|
        try templatesPaths(b.allocator, &.{.{
            .prefix = "templates",
            .path = try splitPath(b.allocator, path),
        }})
    else
        templates_paths_option orelse
            try templatesPaths(b.allocator, &.{.{
                .prefix = "templates",
                .path = &.{ "src", "templates" },
            }});

    manifest_exe.addArg(
        try std.mem.join(b.allocator, ";", templates_paths),
    );

    lib.step.dependOn(&manifest_exe.step);
    for (try findTemplates(b, templates_paths)) |path|
        manifest_exe.addFileArg(.{ .cwd_relative = path });

    const compile_step = b.step("compile", "Compile Zmpl templates");
    compile_step.dependOn(&manifest_exe.step);

    const built_manifest = b.addModule(
        "zmpl.manifest",
        .{ .root_source_file = manifest_lazy_path },
    );

    built_manifest.addImport("zmpl", zmpl);
    built_manifest.addImport("zmd", zmd);

    zmpl.addImport("zmpl.manifest", built_manifest);

    if (auto_build) {
        template_tests.root_module.addImport("zmpl", zmpl);
        template_tests.root_module.addImport("jetcommon", jetcommon);
        template_tests.root_module.addImport("zmpl.manifest", built_manifest);

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

pub fn templatesPaths(
    allocator: Allocator,
    paths: []const TemplatesPath,
) ![]const []const u8 {
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
            try std.mem.concat(allocator, u8, &.{
                "prefix=",
                path.prefix,
                ",path=",
                absolute_path,
            }),
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
        array[index] = std.fmt.comptimePrint("{s}#{s}", .{
            field.name,
            @typeName(field.type),
        });
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
            try templates.append(
                b.allocator,
                try dir.realpathAlloc(b.allocator, entry.path),
            );
        }
    }
    return templates.toOwnedSlice(b.allocator);
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
    const encodedHeader: []u8 = try allocator.alloc(
        u8,
        Encoder.calcSize(manifest_header.len),
    );
    defer allocator.free(encodedHeader);
    const base64Header = Encoder.encode(encodedHeader, manifest_header);

    return std.fmt.allocPrint(allocator,
        \\{s}
        \\
        \\{s}
        \\
        \\{s}
        \\
        \\pub const manifest_header: []const u8 = "{s}";
        \\
    , .{
        options_header_option orelse "",
        constants_source,
        markdown_fragments orelse "",
        base64Header,
    });
}

fn parseZmplConstants(
    allocator: Allocator,
    constants_string: ?[]const u8,
) ![]const u8 {
    const string = constants_string orelse return "";
    var array: ArrayList(u8) = .empty;
    defer array.deinit(allocator);
    var pairs_it = std.mem.splitScalar(u8, string, '|');
    try array.appendSlice(allocator, "pub const template_constants = struct {\n");
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
            } else break;
        }
        if (index > 2) {
            std.log.err(
                "Incoherent Zmpl constants argument: {?s}",
                .{constants_string},
            );
            return error.ZmplConstantsOptionError;
        }
        try array.appendSlice(allocator, try std.fmt.allocPrint(
            allocator,
            "    {s}: {s},\n",
            .{ const_name, const_type },
        ));
    }
    try array.appendSlice(allocator, "};\n");
    return array.toOwnedSlice(allocator);
}

fn splitPath(allocator: Allocator, path: []const u8) ![]const []const u8 {
    var it = std.mem.tokenizeSequence(u8, path, std.fs.path.sep_str);
    var buf: ArrayList([]const u8) = .empty;
    defer buf.deinit(allocator);
    while (it.next()) |segment| try buf.append(allocator, segment);

    return buf.toOwnedSlice(allocator);
}
