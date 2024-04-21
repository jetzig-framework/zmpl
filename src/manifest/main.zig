const std = @import("std");

const Manifest = @import("Manifest.zig");
const Template = @import("Template.zig");
const zmpl_options = @import("zmpl_options");

pub fn main() !void {
    const options_fields = switch (@typeInfo(zmpl_options)) {
        .Struct => |info| info.fields,
        else => @compileError("Invalid type for template constants, expected struct, found: " ++
            @typeName(zmpl_options)),
    };

    const permitted_fields = .{"template_constants"};

    inline for (options_fields) |field| {
        inline for (permitted_fields) |permitted_field| {
            if (std.mem.eql(u8, permitted_field, field.name)) break;
        } else {
            std.debug.print(
                "[zmpl] Unrecgonized option: `{s}: {s}`\n",
                .{ field.name, @typeName(field.type) },
            );
            std.process.exit(1);
        }
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const manifest_path = args[1];

    var templates_paths_buf = std.ArrayList(Manifest.TemplatesPath).init(allocator);
    defer templates_paths_buf.deinit();
    var it = std.mem.tokenizeSequence(u8, args[2], ";");
    while (it.next()) |syntax| {
        const prefix_start = "prefix=".len;
        const prefix_end = std.mem.indexOf(u8, syntax, ",path=").?;
        const path_start = prefix_end + ",path=".len;
        const prefix = syntax[prefix_start..prefix_end];
        const path = syntax[path_start..];
        try templates_paths_buf.append(.{ .prefix = prefix, .path = path });
    }

    const template_paths = args[3..];

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const arena_allocator = arena.allocator();
    var manifest = Manifest.init(arena_allocator, templates_paths_buf.items, template_paths);

    const content = try manifest.compile(Template, zmpl_options);

    const file = try std.fs.createFileAbsolute(manifest_path, .{ .truncate = true });
    try file.writeAll(content);
    file.close();
}
