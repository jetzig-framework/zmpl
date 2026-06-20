const std = @import("std");
const Dir = Io.Dir;
const Io = std.Io;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Writer = Io.Writer;

/// Counter for generating unique temporary variable names
var temp_var_counter: std.atomic.Value(u64) = .init(0);

pub const ignore_whitespace = struct {
    pub fn startsWith(haystack: []const u8, needle: []const u8) bool {
        const index = startIndex(haystack) orelse return false;
        return std.mem.startsWith(u8, haystack[index..], needle);
    }

    pub fn indexOf(haystack: []const u8, needle: []const u8) ?usize {
        const index = startIndex(haystack) orelse return null;
        return std.mem.indexOfPos(u8, haystack, index, needle);
    }

    pub fn startIndex(slice: []const u8) ?usize {
        return std.mem.findNone(u8, slice, &std.ascii.whitespace);
    }

    pub fn firstChar(input: []const u8) ?u8 {
        const index = startIndex(input) orelse
            return null;
        return input[index];
    }
};

pub fn stripComments(content: []u8) usize {
    var write: usize = 0;
    var read: usize = 0;
    while (read < content.len) {
        const rel = std.mem.indexOfScalar(u8, content[read..], '\n');
        const line = content[read..][0..if (rel) |i| i + 1 else content.len - read];
        read += line.len;
        if (ignore_whitespace.startsWith(line, "@//")) continue;
        if (write != read - line.len) std.mem.copyForwards(u8, content[write..][0..line.len], line);
        write += line.len;
    }
    return write;
}

pub fn indexOfWord(haystack: []const u8, needle: []const u8) ?usize {
    return if (std.mem.indexOf(u8, haystack, needle)) |index| blk: {
        const lhs = if (index == 0)
            true
        else switch (haystack[index - 1]) {
            'a'...'z', 'A'...'Z', '0'...'9', '_' => false,
            else => true,
        };

        if (!lhs) break :blk null;

        const rhs = if (index + needle.len + 1 >= haystack.len)
            true
        else switch (haystack[index + needle.len]) {
            'a'...'z', 'A'...'Z', '0'...'9', '_' => false,
            else => true,
        };

        break :blk if (rhs) index else null;
    } else null;
}

pub fn generateTempVariableName(buf: []u8) []u8 {
    const counter = temp_var_counter.fetchAdd(1, .monotonic);
    buf[0] = 'v';
    buf[1] = '_';
    _ = std.fmt.bufPrint(buf[2..], "{x:0>4}", .{counter}) catch unreachable;
    return buf[0..6]; // Return only the valid portion
}

pub fn generateTempVariableNameAlloc(allocator: Allocator) ![]const u8 {
    const buf = try allocator.alloc(u8, 6); // "v_" + 4 hex chars
    _ = generateTempVariableName(buf);
    return buf;
}

pub fn sanitizeKey(key: []const u8, writer: *Writer) !void {
    const starts_with_digit = key.len > 0 and std.ascii.isDigit(key[0]);
    if (starts_with_digit) try writer.writeByte('_');
    for (key) |c| {
        switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9' => try writer.writeByte(c),
            else => try writer.writeByte('_'),
        }
    }
}

pub fn sanitizeKeyAlloc(allocator: Allocator, key: []const u8) ![]const u8 {
    var buffer: Writer.Allocating = .init(allocator);
    defer buffer.deinit();
    try sanitizeKey(key, &buffer.writer);
    return buffer.toOwnedSlice();
}

pub fn generateVariableName(buf: []u8, key: []const u8, content: []const u8) void {
    // Hash the content for deterministic naming
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(content);
    const hash = hasher.final();

    const hash_str_len = 16;
    const key_len = @min(key.len, buf.len - hash_str_len - 1);

    for (0..key_len) |i| {
        buf[i] = switch (key[i]) {
            'a'...'z', 'A'...'Z', '0'...'9' => key[i],
            else => '_',
        };
    }
    buf[key_len] = '_';
    _ = std.fmt.bufPrint(buf[key_len + 1 ..], "{x:0>16}", .{hash}) catch unreachable;
}

pub fn generateVariableNameAlloc(allocator: Allocator, key: []const u8, content: []const u8) ![]const u8 {
    const sanitized_key = try sanitizeKeyAlloc(allocator, key);
    defer allocator.free(sanitized_key);

    const buf = try allocator.alloc(u8, sanitized_key.len + 1 + 16); // key + "_" + 16 hex chars
    generateVariableName(buf, key, content);
    return buf;
}

pub fn normalizeInput(allocator: Allocator, input: []const u8) []const u8 {
    const normalized = std.mem.replaceOwned(
        u8,
        allocator,
        input,
        "\r\n",
        "\n",
    ) catch @panic("OOM");
    if (std.mem.endsWith(u8, normalized, "\n")) return normalized;

    defer allocator.free(normalized);
    return std.mem.concat(allocator, u8, &[_][]const u8{ input, "\n" }) catch @panic("OOM");
}

pub inline fn strip(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, &std.ascii.whitespace);
}

pub inline fn trimParentheses(input: []const u8) []const u8 {
    return std.mem.trimEnd(u8, std.mem.trimStart(u8, input, "("), ")");
}

pub fn chomp(input: []const u8) []const u8 {
    if (input.len == 0 or input.len == 1) return input;

    const start = std.mem.indexOfNone(u8, input, "\n") orelse 0;
    const end = std.mem.lastIndexOfNone(u8, input, "\n") orelse input.len - 1;
    const trim_start = if (start == 0) 0 else start - 1;
    _ = trim_start;
    const trim_end = if (end == input.len - 1) input.len else end + 2;
    return input[0..trim_end];
}

pub fn templatePathStore(allocator: Allocator, root: []const u8, path: []const u8) ![]const u8 {
    const relative = try std.fs.path.relative(allocator, "", null, root, path);
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

pub fn templatePathFetch(allocator: Allocator, path: []const u8, partial: bool) ![]u8 {
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

pub fn normalizePathPosix(allocator: Allocator, path: []const u8) ![]const u8 {
    var buf: ArrayList([]const u8) = .empty;
    defer buf.deinit(allocator);
    var it = std.mem.tokenizeSequence(u8, path, std.fs.path.sep_str);
    while (it.next()) |segment| try buf.append(allocator, segment);

    return std.mem.join(allocator, "/", buf.items);
}

pub fn readFile(allocator: Allocator, io: Io, dir: Dir, path: []const u8) ![]const u8 {
    const stat = dir.statFile(io, path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => {
                std.debug.print("[zmpl] File not found: {s}\n", .{path});
                return error.ZmplFileNotFound;
            },
            else => return err,
        }
    };
    const content = try allocator.alloc(u8, stat.size);
    const file = try dir.openFile(io, path, .{});
    defer file.close(io);
    _ = try file.readPositionalAll(io, content, 0);
    return content;
}

pub fn zigStringEscape(allocator: Allocator, input: ?[]const u8) ![]const u8 {
    const string = input orelse return allocator.dupe(u8, "null");
    var buf: Writer.Allocating = .init(allocator);
    defer buf.deinit();
    const writer = &buf.writer;
    try writer.writeByte('"');
    try std.zig.stringEscape(string, writer);
    try writer.writeByte('"');
    return buf.toOwnedSlice();
}
