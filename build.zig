const std = @import("std");
const Io = std.Io;
const Writer = Io.Writer;
const Build = std.Build;
const Module = Build.Module;
const Import = Module.Import;
const LazyPath = Build.LazyPath;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ResolvedTarget = Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const hex = b.dependency("hex", .{});
    const blush = hex.module("blush");

    const zmd = b.dependency("zmd", .{
        .target = target,
        .optimize = optimize,
    }).module("zmd");

    const datetime = b.dependency("jetzig_datetime", .{
        .target = target,
    }).module("jetzig_datetime");

    const zmpl = b.addModule("zmpl", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/root.zig"),
        .imports = &.{
            import("zmd", zmd),
            import("datetime", datetime),
            import("blush", blush),
        },
    });

    const dummy_options = b.createModule(.{
        .root_source_file = b.path("src/compiler/dummy_zmpl_options.zig"),
        .target = target,
    });
    const test_compiler = templateCompiler(
        b,
        target,
        optimize,
        b.path("src/compiler/main.zig"),
        zmpl,
        zmd,
        dummy_options,
    );

    const zmpl_deps: ZmplDeps = .{ .core = zmpl, .zmd = zmd, .datetime = datetime };

    const test_templates_step = b.step("test-templates", "Compile zmpl test templates");
    const test_template_modules = addZmplTemplates(
        b,
        target,
        optimize,
        test_compiler,
        zmpl_deps,
        &.{.{ .path = "src/tests", .prefix = "tests" }},
        test_templates_step,
    ) catch |err| std.debug.panic("[zmpl] test template setup failed: {s}", .{@errorName(err)});

    const tests_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{import("core", zmpl)},
    });

    var it = test_template_modules.iterator();
    while (it.next()) |entry| tests_mod.addImport(entry.key_ptr.*, entry.value_ptr.*);

    const tests = b.addTest(.{
        .name = "zmpl",
        .root_module = tests_mod,
        .filters = testFilters(b),
    });
    const run_tests = b.addRunArtifact(tests);
    run_tests.step.dependOn(test_templates_step);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    const lib = b.addLibrary(.{
        .name = "zmpl",
        .linkage = .static,
        .root_module = zmpl,
    });
    b.installArtifact(lib);

    const docs_step = b.step("docs", "Generate documentation");
    const docs_install = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&docs_install.step);
}

pub fn import(name: []const u8, module: *Module) Import {
    return .{ .name = name, .module = module };
}

pub const SetupOptions = struct {
    /// The downstream project's config module — e.g. `app/main.zig`. Must export:
    ///   * `zmpl_config` — read by the template compiler at build time, and
    ///   * `template_directories: []const []const u8` — names of the template
    ///     dirs, which are resolved relative to the config module's own directory
    ///     (so `"views"` next to `app/main.zig` means `app/views`).
    /// `zmpl` is added to this module's import table as "zmpl", closing the
    /// config <-> zmpl cycle.
    config: *Module,
    /// The main application module (the executable's root). `zmpl` and every
    /// compiled template module are imported directly into it, so app code can
    /// `@import("zmpl")` and `@import("views/home/index")` with no extra wiring.
    /// May be the same module as `config`.
    main: *Module,
    /// Default to the zmpl module's own target/optimize when null.
    target: ?ResolvedTarget = null,
    optimize: ?OptimizeMode = null,
};

pub const Setup = struct {
    /// The zmpl module. Already imported into your `config` module as "zmpl";
    /// add it to any other module that needs it (e.g. your app's root module).
    module: *Module,
    /// Compiled template modules keyed by name (e.g. "views/home/index").
    /// Add each to the module that renders them via `addImport`.
    templates: std.StringHashMap(*Module),
    /// Named step ("zmpl:compile") that builds every template.
    compile_step: *Build.Step,
};

/// Wire zmpl into a downstream project.
///
/// `dep` is the zmpl dependency from `b.dependency("zmpl", .{...})`. Establishes
/// the relationship the framework needs: the consumer's `config` module imports
/// the zmpl module ("zmpl"), and zmpl's template compiler imports `config` back
/// as "zmpl_options" to read `zmpl_config` while compiling templates.
///
/// Template directories come from the `config` module's own `template_directories`
/// declaration, so the caller never lists them here. After `setup` returns, `main`
/// already has `zmpl` and every template imported — just build the exe from it.
/// `config` and `main` may be the same module.
///
///     const zmpl_build = @import("zmpl");
///     const dep = b.dependency("zmpl", .{ .target = target, .optimize = optimize });
///     const app = b.createModule(.{
///         .root_source_file = b.path("app/main.zig"),
///         .target = target,
///         .optimize = optimize,
///     });
///     _ = try zmpl_build.setup(b, dep, .{ .config = app, .main = app });
///     const exe = b.addExecutable(.{ .name = "app", .root_module = app });
pub fn setup(b: *Build, dep: *Build.Dependency, options: SetupOptions) !Setup {
    const core = dep.module("zmpl");
    const target = options.target orelse core.resolved_target.?;
    const optimize = options.optimize orelse core.optimize orelse .Debug;

    // Reuse the exact sub-dependency modules zmpl already wired into `core`, so
    // the compiler and generated template modules share one instance of each.
    const zmd = core.import_table.get("zmd").?;
    const datetime = core.import_table.get("datetime").?;

    // Close the cycle: `zmpl_config` can now resolve `@import("zmpl_config")`.
    options.config.addImport("zmpl_config", core);
    // App code uses zmpl directly too.
    options.main.addImport("zmpl", core);

    // A compiler bound to *this* consumer's config, not zmpl's dummy options.
    const compiler = templateCompiler(
        b,
        target,
        optimize,
        dep.path("src/compiler/main.zig"),
        core,
        zmd,
        options.config,
    );

    const compile_step = b.step("zmpl:compile", "Compile zmpl templates");
    const template_dirs = try templateDirsFromConfig(b, options.config);
    const templates = try addZmplTemplates(
        b,
        target,
        optimize,
        compiler,
        .{ .core = core, .zmd = zmd, .datetime = datetime },
        template_dirs,
        compile_step,
    );

    // Import every compiled template straight into the app module.
    var it = templates.iterator();
    while (it.next()) |entry| options.main.addImport(entry.key_ptr.*, entry.value_ptr.*);

    return .{ .module = core, .templates = templates, .compile_step = compile_step };
}

/// Read the `template_directories` declaration from the config module's source
/// and turn each entry into a `ZmplDir`. Directory names are resolved relative
/// to the config module's own directory, e.g. `"views"` beside `app/main.zig`
/// becomes `app/views` with prefix `views`.
fn templateDirsFromConfig(b: *Build, config: *Module) ![]const ZmplDir {
    const io = b.graph.io;
    const gpa = b.allocator;

    const lazy = config.root_source_file orelse return error.ZmplConfigHasNoSource;
    const sub_path = switch (lazy) {
        .src_path => |sp| sp.sub_path,
        else => return error.ZmplConfigSourceUnsupported,
    };
    const base = std.fs.path.dirname(sub_path) orelse "";

    const file = try std.Io.Dir.openFileAbsolute(io, b.pathFromRoot(sub_path), .{});
    defer file.close(io);
    const size = try file.length(io);
    var read_buf: [4096]u8 = undefined;
    var reader = file.reader(io, &read_buf);
    const bytes = try reader.interface.readAlloc(gpa, @intCast(size));
    const source = try gpa.dupeZ(u8, bytes);

    var ast = try std.zig.Ast.parse(gpa, source, .zig);
    defer ast.deinit(gpa);

    const token_tags = ast.tokens.items(.tag);
    for (ast.nodes.items(.tag), 0..) |tag, i| {
        if (tag != .simple_var_decl) continue;
        const decl = ast.simpleVarDecl(@enumFromInt(i));
        if (!std.mem.eql(u8, ast.tokenSlice(decl.ast.mut_token + 1), "template_directories")) continue;

        const init_node = decl.ast.init_node.unwrap() orelse return error.ZmplTemplateDirectoriesEmpty;
        var dirs: ArrayList(ZmplDir) = .empty;
        var tok = ast.firstToken(init_node);
        const last = ast.lastToken(init_node);
        while (tok <= last) : (tok += 1) {
            if (token_tags[tok] != .string_literal) continue;
            const literal = ast.tokenSlice(tok);
            const name = literal[1 .. literal.len - 1]; // template dir names contain no escapes
            try dirs.append(gpa, .{
                .path = if (base.len == 0)
                    try gpa.dupe(u8, name)
                else
                    try std.fs.path.join(gpa, &.{ base, name }),
                .prefix = try gpa.dupe(u8, name),
            });
        }
        return dirs.toOwnedSlice(gpa);
    }
    return error.ZmplTemplateDirectoriesNotFound;
}

pub fn templateCompiler(
    b: *Build,
    target: ResolvedTarget,
    optimize: OptimizeMode,
    compiler_src: LazyPath,
    core_mod: *Module,
    zmd_mod: *Module,
    options: *Module,
) *Build.Step.Compile {
    return b.addExecutable(.{
        .name = "zmpl_compiler",
        .root_module = b.createModule(.{
            .root_source_file = compiler_src,
            .target = target,
            .optimize = optimize,
            .imports = &.{
                import("core", core_mod),
                import("zmd", zmd_mod),
                import("zmpl_options", options),
            },
        }),
    });
}

pub const ZmplDir = struct {
    path: []const u8,
    prefix: ?[]const u8 = null,
};

pub const ZmplDeps = struct {
    core: *Module,
    zmd: *Module,
    datetime: *Module,
};

const Dep = struct {
    module_name: []const u8,
    map_key: []const u8,
    prefix: []const u8,
};

const TemplateMeta = struct {
    absolute_path: []const u8,
    prefix: []const u8,
    root: []const u8,
    module_name: []const u8,
    deps: []const Dep,
};

pub fn addZmplTemplates(
    b: *Build,
    target: ResolvedTarget,
    optimize: OptimizeMode,
    compiler: *Build.Step.Compile,
    deps: ZmplDeps,
    dirs: []const ZmplDir,
    compile_step: *Build.Step,
) !std.StringHashMap(*Module) {
    const io = b.graph.io;
    const gpa = b.allocator;

    var metas: ArrayList(TemplateMeta) = .empty;
    defer metas.deinit(gpa);

    for (dirs) |dir| {
        const prefix = dir.prefix orelse std.fs.path.basename(dir.path);
        const dir_path = b.pathFromRoot(dir.path);
        const root_abs = std.Io.Dir.cwd().realPathFileAlloc(io, dir_path, gpa) catch |err| switch (err) {
            error.FileNotFound => {
                std.log.warn("[zmpl] template dir not found, skipping: {s}", .{dir.path});
                continue;
            },
            else => return err,
        };

        var d = try std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
        defer d.close(io);

        var walker = try d.walk(gpa);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.path, ".zmpl")) continue;

            const rel = try std.mem.replaceOwned(u8, gpa, entry.path, "\\", "/");
            const key = stripTemplateExt(rel);
            const basename = std.fs.path.basenamePosix(key);
            const partial = std.mem.startsWith(u8, basename, "_");
            const module_name = if (partial)
                try std.fmt.allocPrint(gpa, "partial/{s}", .{try stripPartialUnderscore(gpa, key)})
            else
                try std.fmt.allocPrint(gpa, "{s}/{s}", .{ prefix, key });

            const absolute_path = try d.realPathFileAlloc(io, entry.path, gpa);
            try metas.append(gpa, .{
                .absolute_path = absolute_path,
                .prefix = prefix,
                .root = root_abs,
                .module_name = module_name,
                .deps = try parseDeps(io, gpa, prefix, absolute_path),
            });
        }
    }

    var modules = std.StringHashMap(*Module).init(gpa);
    for (metas.items) |meta| {
        const unique = try sanitizeFilename(gpa, meta.module_name);

        const compile_run = b.addRunArtifact(compiler);
        compile_run.addArg("compile");
        compile_run.addFileArg(.{ .cwd_relative = meta.absolute_path });
        compile_run.addArg(meta.prefix);
        compile_run.addArg(meta.root);
        const out = compile_run.addOutputFileArg(try std.fmt.allocPrint(gpa, "{s}.zig", .{unique}));
        for (meta.deps) |dep| {
            if (!std.mem.eql(u8, dep.prefix, meta.prefix)) continue;
            compile_run.addArg(try std.fmt.allocPrint(gpa, "--dep={s}", .{dep.map_key}));
        }
        compile_step.dependOn(&compile_run.step);

        const mod = b.createModule(.{
            .root_source_file = out,
            .target = target,
            .optimize = optimize,
            .imports = &.{
                import("core", deps.core),
                import("zmd", deps.zmd),
                import("datetime", deps.datetime),
            },
        });
        try modules.put(meta.module_name, mod);
    }

    for (metas.items) |meta| {
        const mod = modules.get(meta.module_name).?;
        for (meta.deps) |dep| {
            const dep_mod = modules.get(dep.module_name) orelse {
                std.log.warn(
                    "[zmpl] {s}: dependency module not found: {s}",
                    .{ meta.module_name, dep.module_name },
                );
                continue;
            };
            mod.addImport(dep.module_name, dep_mod);
        }
    }

    return modules;
}

fn parseDeps(io: std.Io, gpa: Allocator, prefix: []const u8, absolute_path: []const u8) ![]const Dep {
    const file = std.Io.Dir.openFileAbsolute(io, absolute_path, .{}) catch return &.{};
    defer file.close(io);
    const size = file.length(io) catch return &.{};
    var read_buf: [4096]u8 = undefined;
    var reader = file.reader(io, &read_buf);
    const content = reader.interface.readAlloc(gpa, @intCast(size)) catch return &.{};

    var deps: ArrayList(Dep) = .empty;
    var seen = std.StringHashMap(void).init(gpa);
    defer seen.deinit();

    var pos: usize = 0;
    while (std.mem.indexOfScalarPos(u8, content, pos, '@')) |index| {
        pos = index + 1;
        if (index > 0 and content[index - 1] == '\\') continue;

        const tag_end = std.mem.indexOfNonePos(u8, content, pos, "abcdefghijklmnopqrstuvwxyz") orelse continue;
        const tag = content[pos..tag_end];
        const is_partial = std.mem.eql(u8, tag, "partial");
        const is_extend = std.mem.eql(u8, tag, "extend");
        if (!is_partial and !is_extend) continue;
        pos = tag_end;

        const name_start = std.mem.indexOfNonePos(u8, content, pos, &std.ascii.whitespace) orelse continue;
        var name: []const u8 = undefined;
        if (content[name_start] == '"') {
            const close = std.mem.indexOfScalarPos(u8, content, name_start + 1, '"') orelse continue;
            name = content[name_start + 1 .. close];
            pos = close + 1;
        } else {
            const name_end = std.mem.indexOfAnyPos(u8, content, name_start, " ({\r\n\t") orelse content.len;
            name = content[name_start..name_end];
            pos = name_end;
        }
        if (name.len == 0) continue;

        const dep_prefix, const ref = if (std.mem.indexOfScalar(u8, name, ':')) |i|
            .{ name[0..i], name[i + 1 ..] }
        else
            .{ prefix, name };

        const module_name = if (is_partial)
            try std.fmt.allocPrint(gpa, "partial/{s}", .{ref})
        else
            try std.fmt.allocPrint(gpa, "{s}/{s}", .{ dep_prefix, ref });

        if (seen.contains(module_name)) continue;
        try seen.put(module_name, {});

        try deps.append(gpa, .{
            .module_name = module_name,
            .map_key = if (is_partial) try templatePathFetchKey(gpa, ref) else try gpa.dupe(u8, ref),
            .prefix = dep_prefix,
        });
    }

    return deps.toOwnedSlice(gpa);
}

fn stripTemplateExt(path: []const u8) []const u8 {
    inline for (.{ ".md.zmpl", ".html.zmpl", ".zmpl" }) |ext| {
        if (std.mem.endsWith(u8, path, ext)) return path[0 .. path.len - ext.len];
    }
    return path;
}

fn stripPartialUnderscore(gpa: Allocator, key: []const u8) ![]const u8 {
    if (std.mem.lastIndexOfScalar(u8, key, '/')) |slash| {
        return std.fmt.allocPrint(gpa, "{s}/{s}", .{ key[0..slash], std.mem.trimStart(u8, key[slash + 1 ..], "_") });
    }
    return gpa.dupe(u8, std.mem.trimStart(u8, key, "_"));
}

fn templatePathFetchKey(gpa: Allocator, name: []const u8) ![]const u8 {
    const basename = std.fs.path.basenamePosix(name);
    if (std.fs.path.dirnamePosix(name)) |dirname| {
        return std.fmt.allocPrint(gpa, "{s}/_{s}", .{ dirname, basename });
    }
    return std.fmt.allocPrint(gpa, "_{s}", .{basename});
}

fn sanitizeFilename(gpa: Allocator, name: []const u8) ![]const u8 {
    const out = try gpa.dupe(u8, name);
    for (out) |*c| {
        if (c.* == '/') c.* = '_';
    }
    return out;
}

fn testFilters(b: *Build) []const []const u8 {
    return b.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match any filter",
    ) orelse &.{};
}
