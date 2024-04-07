const std = @import("std");

const Manifest = @import("Manifest.zig");
const Template = @import("Template.zig");
const ModalTemplate = @import("ModalTemplate.zig");
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
    const templates_path = args[2];
    const template_paths = args[3..];

    const zmpl_version = try getVersion(allocator);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const arena_allocator = arena.allocator();
    var manifest = Manifest.init(arena_allocator, templates_path, template_paths);

    const content = switch (zmpl_version) {
        .v1 => try manifest.compile(.v1, Template, zmpl_options),
        .v2 => try manifest.compile(.v2, ModalTemplate, zmpl_options),
    };

    const file = try std.fs.createFileAbsolute(manifest_path, .{ .truncate = true });
    try file.writeAll(content);
    file.close();
}

fn getVersion(allocator: std.mem.Allocator) !Manifest.Version {
    const default_version = "v1";
    const version = std.process.getEnvVarOwned(allocator, "ZMPL_VERSION") catch |err| blk: {
        break :blk switch (err) {
            error.EnvironmentVariableNotFound => try allocator.dupe(u8, default_version),
            else => return err,
        };
    };

    defer allocator.free(version);

    if (std.mem.eql(u8, version, "v1")) return .v1;
    if (std.mem.eql(u8, version, "v2")) return .v2;

    std.debug.print("Unrecognized Zmpl version: `{s}`. Expected: {{ v1, v2 }}\n", .{version});
    unreachable;
}
