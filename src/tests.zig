const std = @import("std");

test "basic template" {
    const zmpl = @import("zmpl");

    const manifest = @import("templates/manifest.zig");
    const allocator = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var array = std.ArrayList(u8).init(allocator);
    const writer = array.writer();
    defer array.deinit();

    var data = zmpl.Data.init(arena.allocator());
    var object = try data.object();
    try object.add("foo", data.string("bar"));
    var context = zmpl.Context{ .allocator = arena.allocator(), .writer = writer, .data = &data };
    try manifest.templates.example.render(&context);

    try std.testing.expectEqualStrings("  <div>Hi!</div>\n", array.items);
}
