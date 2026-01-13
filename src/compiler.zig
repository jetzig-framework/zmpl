const std = @import("std");
const builtin = @import("builtin");
const process = std.process;
const debug = std.debug;
const File = std.fs.File;
const StringHashMap = std.StringHashMapUnmanaged;
const ArenaAllocator = std.heap.ArenaAllocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{});

const Template = @import("manifest/Template.zig");
const util = @import("manifest/util.zig");
const zmpl_options = @import("zmpl_options");

pub fn main() !void {
    var gpa: GeneralPurposeAllocator = .init;
    defer debug.assert(gpa.deinit() == .ok);
    const gpa_allocator = gpa.allocator();

    var arena: ArenaAllocator = .init(gpa_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len < 4) {
        debug.print("Usage: {s} <template.zmpl> <prefix> <root_path> [all_templates...]\n", .{args[0]});
        debug.print("  Compiles a single .zmpl template file to stdout\n", .{});
        debug.print("\n", .{});
        debug.print("  template.zmpl: Template file to compile\n", .{});
        debug.print("  prefix: Template prefix (e.g., 'templates')\n", .{});
        debug.print("  root_path: Root directory for templates\n", .{});
        debug.print("  all_templates...: Paths to all templates (for partial resolution)\n", .{});
        process.exit(1);
    }

    const input_path = args[1];
    const prefix = args[2];
    const root_path = args[3];
    const all_template_paths = args[4..];

    const input_file = std.fs.cwd().openFile(input_path, .{}) catch |err| {
        debug.print("Failed to open input file '{s}': {}\n", .{ input_path, err });
        return err;
    };
    defer input_file.close();

    const size = (try input_file.stat()).size;
    const content = try input_file.readToEndAlloc(allocator, @intCast(size));

    const key = try util.templatePathStore(allocator, root_path, input_path);
    const simple_name = try util.sanitizeKeyForZigIdentifier(allocator, key);

    var template_map: StringHashMap(Template.TemplateMap) = .empty;
    defer template_map.deinit(allocator);

    const result = try template_map.getOrPut(allocator, prefix);
    if (!result.found_existing) {
        result.value_ptr.* = Template.TemplateMap.empty;
    }

    for (all_template_paths) |template_path| {
        const template_key = try util.templatePathStore(allocator, root_path, template_path);
        const template_name = try util.sanitizeKeyForZigIdentifier(allocator, template_key);
        try result.value_ptr.putNoClobber(allocator, template_key, template_name);
    }

    var templates_paths_map: StringHashMap([]const u8) = .empty;
    defer templates_paths_map.deinit(allocator);
    try templates_paths_map.put(allocator, prefix, root_path);

    var template: Template = .init(
        allocator,
        simple_name,
        root_path,
        prefix,
        input_path,
        templates_paths_map,
        content,
        template_map,
    );

    const output = try template.compile(zmpl_options);

    const stdout_file = File.stdout();
    try stdout_file.writeAll(output);

    const basename = std.fs.path.basename(input_path);
    const is_partial = std.mem.startsWith(u8, basename, "_");

    const metadata = try std.fmt.allocPrint(allocator,
        \\
        \\pub const __template_metadata = .{{
        \\    .key = "{s}",
        \\    .name = "{s}",
        \\    .prefix = "{s}",
        \\    .partial = {any},
        \\    .blocks = &.{{}},
        \\}};
        \\
    , .{ key, simple_name, prefix, is_partial });

    try stdout_file.writeAll(metadata);
}
