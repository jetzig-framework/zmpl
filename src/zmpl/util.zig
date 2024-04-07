const std = @import("std");

/// Strip all leading and trailing `\n` except one.
pub fn chomp(input: []const u8) []const u8 {
    if (input.len == 0 or input.len == 1) return input;

    const start = std.mem.indexOfNone(u8, input, "\n") orelse 0;
    const end = std.mem.lastIndexOfNone(u8, input, "\n") orelse input.len - 1;
    const trim_start = if (start == 0) 0 else start - 1;
    _ = trim_start;
    const trim_end = if (end == input.len - 1) input.len else end + 2;
    return input[0..trim_end];
}

/// Strip surrounding whitespace from a []const u8
pub inline fn strip(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, &std.ascii.whitespace);
}
