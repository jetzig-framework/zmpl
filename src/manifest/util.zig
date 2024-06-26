const std = @import("std");

/// The first non-whitespace character of a given input (line).
pub fn firstMeaningfulChar(input: []const u8) ?u8 {
    const stripped = std.mem.trimLeft(u8, input, &std.ascii.whitespace);

    if (stripped.len == 0) return null;

    return stripped[0];
}

/// Detect if a given input string begins with a given value, ignoring leading whitespace.
pub fn startsWithIgnoringWhitespace(haystack: []const u8, needle: []const u8) bool {
    const stripped = std.mem.trimLeft(u8, haystack, &std.ascii.whitespace);

    return std.mem.startsWith(u8, stripped, needle);
}

/// Detect if a given input string begins with a given value, ignoring leading whitespace.
pub fn indexOfIgnoringWhitespace(haystack: []const u8, needle: []const u8) ?usize {
    const trimmed = std.mem.trimLeft(u8, haystack, &std.ascii.whitespace);
    if (std.mem.indexOf(u8, trimmed, needle)) |index| {
        return (haystack.len - trimmed.len) + index;
    } else {
        return null;
    }
}

/// Generate a random variable name with enough entropy to be considered unique.
pub fn generateVariableName(buf: *[32]u8) void {
    const first_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const any_chars = "0123456789" ++ first_chars;

    for (0..3) |index| {
        buf[index] = first_chars[std.crypto.random.intRangeAtMost(u8, 0, first_chars.len - 1)];
    }

    for (3..32) |index| {
        buf[index] = any_chars[std.crypto.random.intRangeAtMost(u8, 0, any_chars.len - 1)];
    }
}

/// Same as `generateVariableName` but allocates memory.
pub fn generateVariableNameAlloc(allocator: std.mem.Allocator) ![]const u8 {
    const buf = try allocator.create([32]u8);
    generateVariableName(buf);
    return buf;
}

// Normalize input by swapping DOS linebreaks for Unix linebreaks and ensuring that the input is
// closed by a `\n`.
pub fn normalizeInput(allocator: std.mem.Allocator, input: []const u8) []const u8 {
    const normalized = std.mem.replaceOwned(u8, allocator, input, "\r\n", "\n") catch @panic("OOM");
    if (std.mem.endsWith(u8, normalized, "\n")) return normalized;

    defer allocator.free(normalized);
    return std.mem.concat(allocator, u8, &[_][]const u8{ input, "\n" }) catch @panic("OOM");
}

/// Strip surrounding whitespace from a []const u8
pub inline fn strip(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, &std.ascii.whitespace);
}

/// Strip surrounding parentheses from a []const u8: `(foobar)` becomes `foobar`.
pub inline fn trimParentheses(input: []const u8) []const u8 {
    return std.mem.trimRight(u8, std.mem.trimLeft(u8, input, "("), ")");
}

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

/// Normalize a template path for storing in a template lookup map.
/// Strips root template path, forces posix-style path separators, and strips extension.
pub fn templatePathStore(allocator: std.mem.Allocator, root: []const u8, path: []const u8) ![]const u8 {
    const relative = try std.fs.path.relative(allocator, root, path);
    defer allocator.free(relative);

    const normalized = try std.mem.replaceOwned(u8, allocator, relative, "\\", "/");

    const extension = if (std.mem.endsWith(u8, normalized, ".md.zmpl"))
        ".md.zmpl"
    else if (std.mem.endsWith(u8, normalized, ".html.zmpl"))
        ".html.zmpl"
    else
        std.fs.path.extension(normalized);
    return normalized[0 .. normalized.len - extension.len];
}

/// Normalize a template path for fetching from a lookup map.
/// Assumes posix-style path separators, prefixes basename with `_` for partials.
pub fn templatePathFetch(allocator: std.mem.Allocator, path: []const u8, partial: bool) ![]u8 {
    const dirname = std.fs.path.dirnamePosix(path);
    const basename = std.fs.path.basenamePosix(path);
    const prefixed = if (partial)
        try std.mem.concat(allocator, u8, &[_][]const u8{ "_", basename })
    else
        try allocator.dupe(u8, basename);

    if (dirname == null) return prefixed;

    defer allocator.free(prefixed);

    return try std.mem.concat(allocator, u8, &[_][]const u8{ dirname.?, "/", prefixed });
}

pub fn normalizePathPosix(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var buf = std.ArrayList([]const u8).init(allocator);
    defer buf.deinit();
    var it = std.mem.tokenizeSequence(u8, path, std.fs.path.sep_str);
    while (it.next()) |segment| try buf.append(segment);

    return try std.mem.join(allocator, "/", buf.items);
}

/// Try to read a file and return content, output a helpful error on failure.
pub fn readFile(allocator: std.mem.Allocator, dir: std.fs.Dir, path: []const u8) ![]const u8 {
    const stat = dir.statFile(path) catch |err| {
        switch (err) {
            error.FileNotFound => {
                std.debug.print("[zmpl] File not found: {s}\n", .{path});
                return error.ZmplFileNotFound;
            },
            else => return err,
        }
    };
    const content = std.fs.cwd().readFileAlloc(allocator, path, @intCast(stat.size));
    return content;
}

/// Output an escaped string suitable for use in generated Zig code.
pub fn zigStringEscape(allocator: std.mem.Allocator, input: ?[]const u8) ![]const u8 {
    if (input) |string| {
        var buf = std.ArrayList(u8).init(allocator);
        const writer = buf.writer();
        try writer.writeByte('"');
        try std.zig.stringEscape(string, "", .{}, writer);
        try writer.writeByte('"');
        return try buf.toOwnedSlice();
    } else {
        return try allocator.dupe(u8, "null");
    }
}
