const std = @import("std");
const Build = std.Build;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Decoder = std.base64.standard.Decoder;
const Encoder = std.base64.standard.Encoder;
const StringHashMap = std.StringHashMapUnmanaged;
const builtin = @import("builtin");
const Data = @import("src/zmpl.zig").Data;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options_files = b.addWriteFiles();

    const use_llvm = b.option(
        bool,
        "use_llvm",
        "Use LLVM",
    ) orelse true;

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

    const zmpl_markdown_formatters_option = b.option(
        []const u8,
        "zmpl_markdown_formatters",
        "Custom markdown formatters",
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

    const zmd = b.dependency("zmd", .{
        .target = target,
        .optimize = optimize,
    }).module("zmd");

    const zmpl_options = b.addModule("zmpl_options", .{
        .root_source_file = options_files.add(
            "zmpl_options.zig",
            try generateZmplOptions(
                b.allocator,
                zmpl_options_header_option,
                zmpl_markdown_formatters_option,
                zmpl_constants_option,
                zmpl_manifest_header_option,
            ),
        ),
        .imports = &.{
            .{ .name = "zmd", .module = zmd },
        },
    });

    const jetcommon = b.dependency("jetcommon", .{
        .target = target,
        .optimize = optimize,
    }).module("jetcommon");

    const zmpl = b.addModule("zmpl", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/zmpl.zig"),
        .imports = &.{
            .{ .name = "zmd", .module = zmd },
            .{ .name = "jetcommon", .module = jetcommon },
            .{ .name = "build_options", .module = build_options.createModule() },
        },
    });

    const manifest = b.addModule("zmpl.manifest", .{
        // adding root_source_file later
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zmd", .module = zmd },
            .{ .name = "zmpl", .module = zmpl },
        },
    });
    zmpl.addImport("zmpl.manifest", manifest);

    const dummy_manifest = b.createModule(.{
        .root_source_file = b.path("src/dummy_manifest.zig"),
    });

    const dummy_zmpl_options = b.createModule(.{
        .root_source_file = b.path("src/manifest/dummy_zmpl_options.zig"),
    });

    const template_tests = b.addTest(.{
        .name = "templates",
        .filters = test_filters,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zmpl", .module = zmpl },
                .{ .name = "jetcommon", .module = jetcommon },
                .{ .name = "zmpl.manifest", .module = manifest },
            },
        }),
    });

    const zmpl_tests = b.addTest(.{
        .name = "zmpl",
        .filters = test_filters,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zmpl.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zmd", .module = zmd },
                .{ .name = "jetcommon", .module = jetcommon },
                .{ .name = "zmpl.manifest", .module = dummy_manifest },
            },
        }),
    });

    const manifest_tests = b.addTest(.{
        .name = "manifest",
        .filters = test_filters,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/manifest/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zmpl_options", .module = dummy_zmpl_options },
                .{ .name = "zmd", .module = zmd },
            },
        }),
    });

    const lib = b.addLibrary(.{
        .name = "zmpl",
        .linkage = .static,
        .use_llvm = use_llvm,
        .root_module = zmpl,
        // .root_module = b.createModule(.{
        //     .target = target,
        //     .optimize = optimize,
        //     .root_source_file = b.path("src/zmpl.zig"),
        //     .imports = &.{
        //         .{ .name = "zmd", .module = zmd },
        //         .{ .name = "zmpl", .module = zmpl },
        //         .{ .name = "jetcommon", .module = jetcommon },
        //         .{ .name = "zmpl.manifest", .module = manifest },
        //     },
        // }),
    });

    const benchmark = b.addExecutable(.{
        .name = "zmpl",
        .use_llvm = use_llvm,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/main.zig"),
            .imports = &.{
                .{ .name = "zmpl", .module = zmpl },
                .{ .name = "zmd", .module = zmd },
            },
        }),
    });

    const run_artifact = b.addRunArtifact(benchmark);
    const run_step = b.step("run", "Run benchmarking");
    run_step.dependOn(&run_artifact.step);

    const auto_build = if (zmpl_auto_build_option) |opt| opt else true;

    const compiler_module = b.createModule(.{
        .root_source_file = b.path("src/compiler.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zmpl_options", .module = zmpl_options },
            .{ .name = "zmd", .module = zmd },
            .{ .name = "jetcommon", .module = jetcommon },
        },
    });

    const template_compiler = b.addExecutable(.{
        .name = "template-compiler",
        .use_llvm = use_llvm,
        .root_module = compiler_module,
    });
    b.installArtifact(template_compiler);

    var template_metadata: ArrayList(TemplateMetadata) = .empty;
    defer template_metadata.deinit(b.allocator);

    var prefix_to_root: StringHashMap([]const u8) = .empty;
    defer prefix_to_root.deinit(b.allocator);
    for (templates_paths) |syntax| {
        try prefix_to_root.put(b.allocator, extractPrefix(syntax), extractPath(syntax));
    }

    const compile_step = b.step("compile", "Compile Zmpl templates");

    for (try findTemplates(b, templates_paths)) |template_path| {
        // Find which prefix/root this template belongs to
        var found_prefix: ?[]const u8 = null;
        var found_root: ?[]const u8 = null;

        for (templates_paths) |syntax| {
            const root = extractPath(syntax);
            if (std.mem.startsWith(u8, template_path, root)) {
                found_prefix = extractPrefix(syntax);
                found_root = root;
                break;
            }
        }

        if (found_prefix == null or found_root == null) {
            std.log.warn("[zmpl] Could not determine prefix for template: {s}", .{template_path});
            continue;
        }

        const template_prefix = found_prefix.?;
        const root_path = found_root.?;

        const key = try templatePathStore(b.allocator, root_path, template_path);
        const name = try sanitizeKeyForZigIdentifier(b.allocator, key);

        const basename = std.fs.path.basename(template_path);
        const is_partial = std.mem.startsWith(u8, basename, "_");

        try template_metadata.append(b.allocator, .{
            .absolute_path = template_path,
            .key = key,
            .name = name,
            .prefix = template_prefix,
            .partial = is_partial,
        });
    }

    var template_map_by_prefix: StringHashMap(ArrayList(struct {
        key: []const u8,
        name: []const u8,
    })) = .empty;

    defer {
        var iter = template_map_by_prefix.iterator();
        while (iter.next()) |entry|
            entry.value_ptr.deinit(b.allocator);
        template_map_by_prefix.deinit(b.allocator);
    }

    for (template_metadata.items) |meta| {
        const result = try template_map_by_prefix.getOrPut(b.allocator, meta.prefix);
        if (!result.found_existing) result.value_ptr.* = .{};
        try result.value_ptr.append(b.allocator, .{ .key = meta.key, .name = meta.name });
    }

    var template_dependencies: StringHashMap(std.ArrayList([]const u8)) = .empty;
    defer {
        var iter = template_dependencies.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(b.allocator);
        }
        template_dependencies.deinit(b.allocator);
    }

    var pos: usize = 0;
    var name_start: usize = 0;
    var name_end: usize = 0;
    for (template_metadata.items) |meta| {
        const file = std.fs.cwd().openFile(
            meta.absolute_path,
            .{ .mode = .read_only },
        ) catch continue;
        defer file.close();
        const stats = try file.stat();
        const content = file.readToEndAlloc(
            b.allocator,
            stats.size,
        ) catch continue;
        defer b.allocator.free(content);

        pos = 0;
        var deps: ArrayList([]const u8) = .empty;
        while (std.mem.indexOfScalarPos(u8, content, pos, '@')) |index| {
            pos = index + 1;
            const tag_end = std.mem.indexOfNonePos(
                u8,
                content,
                pos,
                std.ascii.lowercase,
            ) orelse continue;
            const tag = content[pos..tag_end];
            if (!std.mem.eql(u8, tag, "partial") and
                !std.mem.eql(u8, tag, "extends")) continue;

            pos = tag_end;

            name_start = std.mem.indexOfNonePos(
                u8,
                content,
                pos,
                &std.ascii.whitespace,
            ) orelse continue;
            name_end = std.mem.indexOfAnyPos(
                u8,
                content,
                name_start,
                " ({\r\n",
            ) orelse continue;
            pos = name_end;
            const name = content[name_start..name_end];
            const full_name = if (std.mem.eql(u8, tag, "extends"))
                name
            else
                try std.fmt.allocPrint(b.allocator, "_{s}", .{name});
            try deps.append(b.allocator, full_name);
        }
        try template_dependencies.put(b.allocator, meta.absolute_path, deps);
    }

    const manifest_files = b.addWriteFiles();

    var template_map_files: StringHashMap(Build.LazyPath) = .empty;
    defer template_map_files.deinit(b.allocator);

    for (template_metadata.items) |meta| {
        if (!template_dependencies.contains(meta.absolute_path)) {
            const empty_deps: ArrayList([]const u8) = .empty;
            try template_dependencies.put(b.allocator, meta.absolute_path, empty_deps);
        }

        const prefix_templates = template_map_by_prefix.get(meta.prefix).?;
        const template_deps = template_dependencies.get(meta.absolute_path).?;

        var json_buf: Writer.Allocating = .init(b.allocator);
        defer json_buf.deinit();
        const json_writer = &json_buf.writer;
        try json_writer.writeAll("{\"");
        try json_writer.writeAll(meta.prefix);
        try json_writer.writeAll("\":{");

        var first = true;
        // Only include templates that this template depends on
        // so we don't invalidate cache if we don't need to
        for (prefix_templates.items) |tmpl| {
            // check if this template is in dependencies
            var is_dep = false;
            for (template_deps.items) |dep| {
                if (std.mem.eql(u8, dep, tmpl.key)) {
                    is_dep = true;
                    break;
                }
            }
            if (!is_dep) continue;

            if (!first) try json_writer.writeAll(",");
            first = false;
            try json_writer.print("\"{s}\":\"{s}\"", .{ tmpl.key, tmpl.name });
        }
        try json_writer.writeAll("}}");

        // Create a separate WriteFile step for this template's map
        // This ensures changes to one template's map don't invalidate other templates
        const map_filename = try std.fmt.allocPrint(b.allocator, "{s}_map.json", .{meta.name});
        const template_map_write = b.addWriteFiles();
        const map_file = template_map_write.add(map_filename, try json_buf.toOwnedSlice());
        try template_map_files.put(b.allocator, meta.absolute_path, map_file);
    }

    for (template_metadata.items) |meta| {
        const root_path = prefix_to_root.get(meta.prefix).?;
        const name = try std.fmt.allocPrint(
            b.allocator,
            "{s}.zig",
            .{meta.name},
        );

        const compile_template = b.addRunArtifact(template_compiler);
        compile_template.addFileArg(.{ .cwd_relative = meta.absolute_path });
        compile_template.addArg(meta.prefix);
        compile_template.addArg(root_path);

        const template_output = compile_template.addOutputFileArg(name);

        // Pass this template's specific dependency map file
        // This file only includes templates that this template uses for name resolution
        // The map only changes when templates are added/removed/renamed, not when content changes
        const map_file = template_map_files.get(meta.absolute_path).?;
        compile_template.addFileArg(map_file);

        const template_module = b.createModule(.{
            .root_source_file = template_output,
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zmpl.manifest", .module = manifest },
                .{ .name = "zmpl", .module = zmpl },
                .{ .name = "zmd", .module = zmd },
            },
        });
        manifest.addImport(meta.name, template_module);
    }

    const manifest_content = try generateManifestContent(
        b.allocator,
        template_metadata.items,
        zmpl_manifest_header_option,
    );

    manifest.root_source_file = manifest_files.add("zmpl.manifest.zig", manifest_content);

    compile_step.dependOn(&manifest_files.step);

    zmpl.addImport("zmpl.manifest", manifest);

    if (auto_build) {
        const test_step = b.step("test", "Run library tests");

        const run_template_tests = b.addRunArtifact(template_tests);
        const run_zmpl_tests = b.addRunArtifact(zmpl_tests);
        const run_manifest_tests = b.addRunArtifact(manifest_tests);

        template_tests.step.dependOn(&manifest_files.step);
        test_step.dependOn(&run_template_tests.step);
        test_step.dependOn(&run_zmpl_tests.step);
        test_step.dependOn(&run_manifest_tests.step);
    }

    lib.step.dependOn(&manifest_files.step);

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

const TemplateMetadata = struct {
    absolute_path: []const u8,
    key: []const u8,
    name: []const u8,
    prefix: []const u8,
    partial: bool,
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

fn templatePathStore(allocator: Allocator, root: []const u8, path: []const u8) ![]const u8 {
    const relative = try std.fs.path.relative(allocator, root, path);
    defer allocator.free(relative);

    const normalized = try std.mem.replaceOwned(u8, allocator, relative, "\\", "/");

    const extension = if (std.mem.endsWith(u8, normalized, ".md.zmpl"))
        ".md.zmpl"
    else if (std.mem.endsWith(u8, normalized, ".html.zmpl"))
        ".html.zmpl"
    else
        std.fs.path.extension(normalized);

    return normalized[0 .. normalized.len - extension.len];
}

fn sanitizeKeyForZigIdentifier(allocator: Allocator, key: []const u8) ![]const u8 {
    const result = try allocator.alloc(u8, key.len);
    for (key, 0..) |c, i| {
        result[i] = switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9' => c,
            else => '_',
        };
    }
    return result;
}

fn extractPrefix(syntax: []const u8) []const u8 {
    const prefix_start = "prefix=".len;
    const prefix_end = std.mem.indexOf(u8, syntax, ",path=").?;
    return syntax[prefix_start..prefix_end];
}

fn extractPath(syntax: []const u8) []const u8 {
    const path_start = std.mem.indexOf(u8, syntax, ",path=").? + ",path=".len;
    return syntax[path_start..];
}

fn generateManifestContent(
    allocator: Allocator,
    templates: []const TemplateMetadata,
    manifest_header_b64: []const u8,
) ![]const u8 {
    var buf: Writer.Allocating = .init(allocator);
    const writer = &buf.writer;

    try writer.writeAll(
        \\// Zmpl template manifest.
        \\// This file is automatically generated in build.zig and should not be manually modified.
        \\const std = @import("std");
        \\const __zmpl = @import("zmpl");
        \\
        \\
    );

    if (manifest_header_b64.len > 0) {
        const required_size = try Decoder.calcSizeForSlice(manifest_header_b64);
        const decoded = try allocator.alloc(u8, required_size);
        defer allocator.free(decoded);
        try Decoder.decode(decoded, manifest_header_b64);
        try writer.writeAll(decoded);
        try writer.writeAll("\n");
    }

    try writer.writeAll(
        \\pub const ZmplValue = __zmpl.Data.Value;
        \\pub const __Manifest = struct {
        \\    const TemplateType = enum { zmpl, markdown };
        \\    pub const Template = __zmpl.Template;
        \\
        \\
    );

    for (templates) |template| try writer.print(
        \\    pub const {[name]s} = @import("{[name]s}");
        \\
    , .{
        .name = template.name,
    });

    try writer.writeAll(
        \\
        \\    /// Find any template matching a given name. Uses all template paths in order.
        \\    pub fn find(name: []const u8) ?Template {
        \\        const type_info = @typeInfo(@This());
        \\        inline for (type_info.@"struct".decls) |decl| {
        \\            const field = @field(@This(), decl.name);
        \\            const field_type = @TypeOf(field);
        \\            if (@typeInfo(field_type) == .@"type") {
        \\                if (@hasDecl(field, "__metadata")) {
        \\                    const metadata: __zmpl.Template.Metadata = field.__metadata;
        \\                    if (std.mem.eql(u8, metadata.key, name)) {
        \\                        return .{
        \\                            .key = metadata.key,
        \\                            .name = metadata.name,
        \\                            .prefix = metadata.prefix,
        \\                            .blocks = metadata.blocks,
        \\                        };
        \\                    }
        \\                }
        \\            }
        \\        }
        \\        return null;
        \\    }
        \\
        \\    /// Find a template in a given prefix, i.e. a template located within a specific
        \\    /// template path.
        \\    pub fn findPrefixed(prefix: []const u8, name: []const u8) ?Template {
        \\        const type_info = @typeInfo(@This());
        \\        inline for (type_info.@"struct".decls) |decl| {
        \\            const field = @field(@This(), decl.name);
        \\            const field_type = @TypeOf(field);
        \\            if (@typeInfo(field_type) == .@"type") {
        \\                if (@hasDecl(field, "__metadata")) {
        \\                    const metadata: __zmpl.Template.Metadata = field.__metadata;
        \\                    if (std.mem.eql(u8, metadata.prefix, prefix) and
        \\                        std.mem.eql(u8, metadata.key, name)) {
        \\                        return .{
        \\                            .key = metadata.key,
        \\                            .name = metadata.name,
        \\                            .prefix = metadata.prefix,
        \\                            .blocks = metadata.blocks,
        \\                        };
        \\                    }
        \\                }
        \\            }
        \\        }
        \\        return null;
        \\    }
        \\};
        \\
    );

    return buf.toOwnedSlice();
}

fn generateZmplOptions(
    allocator: Allocator,
    options_header_option: []const u8,
    markdown_formatters: []const u8,
    constants: []const u8,
    manifest_header_option: []const u8,
) ![]const u8 {
    var aw: Writer.Allocating = .init(allocator);
    defer aw.deinit();

    try aw.writer.print(
        \\//Generated in build.zig
        \\{[options]s}
        \\
        \\
    , .{
        .options = options_header_option,
    });

    try parseZmplConstants(&aw.writer, constants);

    const encodedHeader: []u8 = try allocator.alloc(
        u8,
        Encoder.calcSize(manifest_header_option.len),
    );
    defer allocator.free(encodedHeader);
    const base64Header = Encoder.encode(encodedHeader, manifest_header_option);

    try aw.writer.print(
        \\{[formatters]s}
        \\
        \\pub const manifest_header: []const u8 = "{[header]s}";
    , .{
        .formatters = markdown_formatters,
        .header = base64Header,
    });

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
            std.log.err(
                "Incomplete Zmpl constants argument: {s}",
                .{constants_string},
            );
            return error.ZmplConstantsOptionError;
        };
        // this should be null
        if (arg_it.next()) |_| {
            std.log.err(
                "Incoherent Zmpl constants argument: {s}",
                .{constants_string},
            );
            return error.ZmplConstantsOptionError;
        }
        try writer.print("    {s}: {s},\n", .{ const_name, const_type });
    }
    try writer.writeAll("};\n");
}
