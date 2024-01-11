const std = @import("std");
const manifest = @import("templates/manifest.zig");
pub const zmpl = @import("zmpl");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    var buf = std.ArrayList(u8).init(allocator);
    const writer = buf.writer();
    defer buf.deinit();

    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var object = try data.object();
    var array = try data.array();
    try array.append(data.string("yay"));
    try array.append(data.string("hoo"));
    try object.add("foo", array.*);

    var context = zmpl.Context{ .allocator = allocator, .writer = writer, .data = &data };
    try manifest.templates.example_with_iteration.render(&context);

    std.debug.print("Hello --> {s} <--\n", .{buf.items});
}
