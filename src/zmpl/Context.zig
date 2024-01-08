const std = @import("std");

const root = @import("../zmpl.zig");
const Self = @This();

allocator: std.mem.Allocator,
writer: std.ArrayList(u8).Writer,
data: *root.Data,

pub fn write(self: *Self, slice: []const u8) !void {
    try self.writer.writeAll(slice);
}

pub fn getValueString(self: *Self, key: []const u8) ![]const u8 {
    return (try self.data.getValueString(key)) orelse "";
}

pub fn formatDecl(self: *Self, comptime decl: anytype) ![]const u8 {
    if (comptime std.meta.trait.isZigString(@TypeOf(decl))) {
        return try std.fmt.allocPrint(self.allocator, "{s}", .{decl});
    } else {
        return try std.fmt.allocPrint(self.allocator, "{}", .{decl});
    }
}
