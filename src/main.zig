const std = @import("std");
const manifest = @import("templates/manifest.zig");
pub const zmpl = @import("zmpl.zig");
const testing = std.testing;

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var array = std.ArrayList(u8).init(allocator);
    defer array.deinit();
    const writer = array.writer();
    var data = zmpl.Data.init(arena.allocator());
    var object = try data.object();
    try object.add("foo", data.string("bar"));
    var context = zmpl.Context{ .allocator = arena.allocator(), .writer = writer, .data = &data };
    try manifest.templates.example.render(&context);

    // defer array.deinit();

    std.debug.print("{s}\n", .{array.items});
}
