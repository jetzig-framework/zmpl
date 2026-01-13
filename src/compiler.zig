const std = @import("std");
const builtin = @import("builtin");
const process = std.process;
const debug = std.debug;
const File = std.fs.File;
const StringHashMap = std.StringHashMapUnmanaged;
const ArenaAllocator = std.heap.ArenaAllocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{});
const Writer = std.Io.Writer;

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
    if (args.len != 6) {
        debug.print("Usage: {s} <template.zmpl> <prefix> <root_path> <output.zig> <template_map_file>\n", .{args[0]});
        debug.print("  Compiles a single .zmpl template file to an output file\n", .{});
        debug.print("\n", .{});
        debug.print("  template.zmpl: Template file to compile\n", .{});
        debug.print("  prefix: Template prefix (e.g., 'templates')\n", .{});
        debug.print("  root_path: Root directory for templates\n", .{});
        debug.print("  output.zig: Output file path\n", .{});
        debug.print("  template_map_file: JSON file containing template key->name mappings\n", .{});
        process.exit(1);
    }

    const input_path = args[1];
    const prefix = args[2];
    const root_path = args[3];
    const output_path = args[4];
    const template_map_file_path = args[5];

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

    // Read and parse the JSON template map file
    const map_file = std.fs.cwd().openFile(template_map_file_path, .{}) catch |err| {
        debug.print("Failed to open template map file '{s}': {}\n", .{ template_map_file_path, err });
        return err;
    };
    defer map_file.close();

    const map_size = (try map_file.stat()).size;
    const template_map_json = try map_file.readToEndAlloc(allocator, @intCast(map_size));

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        template_map_json,
        .{},
    );
    defer parsed.deinit();

    if (parsed.value.object.get(prefix)) |prefix_map| {
        var iter = prefix_map.object.iterator();
        while (iter.next()) |entry| {
            const template_key = entry.key_ptr.*;
            const template_name = entry.value_ptr.string;
            try result.value_ptr.putNoClobber(allocator, template_key, template_name);
        }
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

    const basename = std.fs.path.basename(input_path);
    const is_partial = std.mem.startsWith(u8, basename, "_");

    // Extract blocks from the compiled template
    var blocks_buf: Writer.Allocating = .init(allocator);
    defer blocks_buf.deinit();
    const blocks_writer = &blocks_buf.writer;

    try blocks_writer.writeAll("&[_]__zmpl.Template.Block{");
    var block_iter = template.block_map.iterator();
    var first = true;
    while (block_iter.next()) |entry| {
        const block_list = entry.value_ptr.*;
        for (block_list.items) |block| {
            if (!first) try blocks_writer.writeAll(", ");
            first = false;
            try blocks_writer.print(".{{ .name = \"{s}\", .func = \"{s}\", .template_name = \"{s}\" }}", .{
                block.name,
                block.func,
                simple_name,
            });
        }
    }
    try blocks_writer.writeAll("}");

    const metadata = try std.fmt.allocPrint(allocator,
        \\
        \\pub const __template_metadata = .{{
        \\    .key = "{s}",
        \\    .name = "{s}",
        \\    .prefix = "{s}",
        \\    .partial = {any},
        \\    .blocks = {s},
        \\}};
        \\
    , .{ key, simple_name, prefix, is_partial, blocks_buf.writer.buffered() });

    // Write to output file
    const output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();
    try output_file.writeAll(output);
    try output_file.writeAll(metadata);
}
