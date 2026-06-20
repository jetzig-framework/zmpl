const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Io = std.Io;
const Dir = Io.Dir;
const StringHashMap = std.StringHashMapUnmanaged;
const process = std.process;
const debug = std.debug;

const Template = @import("Template.zig");
const util = @import("util.zig");
const core = @import("core");
const zmpl_options = @import("zmpl_options");

/// Compile-time Zmpl configuration driving codegen. The app's `zmpl_options` module (app/main.zig)
/// exports a `zmpl_config` value; the empty dummy used for test templates does not, so fall back to
/// defaults.
const config: core.Config = if (@hasDecl(zmpl_options, "zmpl_config")) zmpl_options.zmpl_config else .{};

/// Single host executable that owns all Zmpl codegen. Dispatched on `argv[1]`:
///
///   compile  <in.zmpl> <prefix> <root> <out.zig> [--dep=<key>...]   compile one template (cached per-file)
///   generate <out_manifest.zig> <name...>                           write the import-only manifest
///
/// `build.zig` runs `compile` once per template (so the build system caches each one) and `generate`
/// once to assemble the manifest that imports them.
pub fn main(init: std.process.Init) !void {
    var arena: ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 2) return usage(args[0]);

    const subcommand = args[1];
    if (std.mem.eql(u8, subcommand, "compile")) {
        try compile(allocator, init.io, args);
    } else {
        return usage(args[0]);
    }
}

fn usage(exe: []const u8) noreturn {
    debug.print("Usage:\n", .{});
    debug.print("  {s} compile <template.zmpl> <prefix> <root_path> <output.zig> [--dep=<key>...]\n", .{exe});
    process.exit(1);
}

fn compile(allocator: Allocator, io: Io, args: []const []const u8) !void {
    if (args.len < 6) return usage(args[0]);

    const input_path = args[2];
    const prefix = args[3];
    const root_path = args[4];
    const output_path = args[5];
    const dep_args = args[6..]; // each `--dep=<key>`: this template's same-prefix partial/extend deps

    const input_file = Dir.cwd().openFile(io, input_path, .{}) catch |err| {
        debug.print("Failed to open input file '{s}': {}\n", .{ input_path, err });
        return err;
    };
    defer input_file.close(io);

    const size = (try input_file.stat(io)).size;
    const input_content = try allocator.alloc(u8, @intCast(size));
    _ = try input_file.readPositionalAll(io, input_content, 0);

    const source = input_content[0..util.stripComments(input_content)];

    const key = try util.templatePathStore(allocator, root_path, input_path);
    const simple_name = try util.sanitizeKeyAlloc(allocator, key);

    var template_map: StringHashMap(Template.TemplateMap) = .empty;
    defer template_map.deinit(allocator);

    const result = try template_map.getOrPut(allocator, prefix);
    if (!result.found_existing) {
        result.value_ptr.* = Template.TemplateMap.empty;
    }

    for (dep_args) |arg| {
        const flag = "--dep=";
        if (!std.mem.startsWith(u8, arg, flag)) {
            debug.print("Unexpected argument '{s}', expected '--dep=<key>'\n", .{arg});
            return usage(args[0]);
        }
        const dep_key = arg[flag.len..];
        try result.value_ptr.putNoClobber(allocator, dep_key, dep_key);
    }

    var templates_paths_map: StringHashMap([]const u8) = .empty;
    defer templates_paths_map.deinit(allocator);
    try templates_paths_map.put(allocator, prefix, root_path);

    var template: Template = .init(
        allocator,
        io,
        simple_name,
        root_path,
        prefix,
        input_path,
        templates_paths_map,
        source,
        template_map,
    );

    const basename = std.fs.path.basename(input_path);
    const is_partial = std.mem.startsWith(u8, basename, "_");

    const output_file = try std.Io.Dir.cwd().createFile(io, output_path, .{});
    defer output_file.close(io);
    var write_buf: [4096]u8 = undefined;
    var file_writer = output_file.writer(io, &write_buf);
    const writer = &file_writer.interface;
    try writer.writeAll(try template.compile(config));
    try writer.print(
        \\
        \\pub const __metadata: __core.Metadata = .{{
        \\    .key = "{s}",
        \\    .name = "{s}",
        \\    .prefix = "{s}",
        \\    .partial = {any},
        \\    .blocks = &.{{
    , .{
        key,
        simple_name,
        prefix,
        is_partial,
    });

    var block_iter = template.block_map.iterator();
    while (block_iter.next()) |entry| {
        const block_list = entry.value_ptr.*;
        for (block_list.items) |block| {
            try writer.print(
                \\
                \\        .{{ .name = "{[name]s}", .func = "{[func]s}", .template_name = "{[template]s}" }},
                \\
            , .{
                .name = block.name,
                .func = block.func,
                .template = simple_name,
            });
        }
    }
    try writer.writeAll(
        \\    },
        \\};
        \\
    );
    try writer.flush();
}

test {
    _ = std.testing.refAllDecls(@This());
}
