const std = @import("std");
const ArrayList = std.ArrayList;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;

const Manifest = @import("Manifest.zig");
const Template = @import("Template.zig");
const zmpl_options = @import("zmpl_options");

pub fn main() !void {
    const options_fields = switch (@typeInfo(zmpl_options)) {
        .@"struct" => |info| info.fields,
        else => @compileError("Invalid type for template constants, expected struct, found: " ++
            @typeName(zmpl_options)),
    };

    const permitted_fields = .{ "template_constants", "markdown_fragments", "manifest_header" };

    inline for (options_fields) |field| {
        inline for (permitted_fields) |permitted_field| {
            if (std.mem.eql(u8, permitted_field, field.name)) break;
        } else {
            std.debug.print(
                "[zmpl] Unrecognized option: `{s}: {s}`\n",
                .{ field.name, @typeName(field.type) },
            );
            std.process.exit(1);
        }
    }

    var gpa: GeneralPurposeAllocator(.{}) = .init;
    defer assert(gpa.deinit() == .ok);

    const gpa_allocator = gpa.allocator();

    var arena: ArenaAllocator = .init(gpa_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    const manifest_path = args[1];

    var templates_paths: ArrayList(Manifest.TemplatePath) = .empty;
    defer templates_paths.deinit(allocator);

    var it = std.mem.tokenizeSequence(u8, args[2], ";");
    while (it.next()) |syntax| {
        const prefix_start = "prefix=".len;
        const prefix_end = std.mem.indexOf(u8, syntax, ",path=").?;
        const path_start = prefix_end + ",path=".len;
        const prefix = syntax[prefix_start..prefix_end];
        const path = syntax[path_start..];
        const present = !std.mem.eql(u8, path, "_");
        try templates_paths.append(allocator, .{
            .prefix = prefix,
            .path = if (present) try std.fs.realpathAlloc(allocator, path) else "_",
            .present = present,
        });
    }

    var template_paths_buf: ArrayList(Manifest.TemplatePath) = .empty;
    defer template_paths_buf.deinit(allocator);

    // for each template path
    path_loop: for (args[3..]) |path| {
        for (templates_paths.items) |template_path| {
            if (!std.mem.startsWith(u8, path, template_path.path)) continue;
            try template_paths_buf.append(allocator, .{
                .path = path,
                .prefix = template_path.prefix,
                .present = template_path.present,
            });
            continue :path_loop;
        }
        @panic("template not found");
    }

    var manifest: Manifest = .init(templates_paths.items, template_paths_buf.items);

    const file = try std.fs.cwd().createFile(manifest_path, .{ .truncate = true });
    var buffer: [1024]u8 = undefined;
    var writer = file.writerStreaming(&buffer);
    try manifest.compile(
        allocator,
        &writer.interface,
        zmpl_options,
    );
    file.close();
}

test {
    _ = std.testing.refAllDeclsRecursive(@This());
}
