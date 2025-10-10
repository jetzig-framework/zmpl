const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

/// Strip all leading and trailing `\n` except one.
pub fn chomp(input: []const u8) []const u8 {
    if (input.len == 0 or input.len == 1) return input;

    const end = std.mem.lastIndexOfNone(u8, input, "\n") orelse input.len - 1;
    const trim_end = if (end == input.len - 1) input.len else end + 2;
    return input[0..trim_end];
}

/// Strip surrounding whitespace from a []const u8
pub inline fn strip(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, &std.ascii.whitespace);
}

/// Indent a line-separated string with the given indent size.
pub fn indent(
    allocator: Allocator,
    input: []const u8,
    comptime indent_size: usize,
) ![]const u8 {
    var it = std.mem.splitScalar(u8, input, '\n');
    var buf: Writer.Allocating = .init(allocator);
    defer buf.deinit();

    while (it.next()) |line| {
        for (0..indent_size - 1) |_| try buf.writer.print(" ", .{});
        //try buf.writer.writeByteNTimes(' ', indent_size);
        try buf.writer.print("{s}\n", .{line});
    }
    return buf.toOwnedSlice();
}
