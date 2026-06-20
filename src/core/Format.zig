const std = @import("std");
const Stringify = std.json.Stringify;
const Writer = std.Io.Writer;

const DateTime = @import("datetime").DateTime;

writer: *Writer,

const Format = @This();

pub fn datetime(self: Format, value: anytype, comptime fmt: []const u8) ![]const u8 {
    const parsed_datetime = try resolveDateTime(value);
    try parsed_datetime.strftime(self.writer, fmt);
    return ""; // We use the writer to output but Zmpl expects a string returned by `{{foo}}`
}

// Resolve a context value to a `DateTime`: pass through a `DateTime`, parse a string, deref a
// pointer, or unwrap an optional.
fn resolveDateTime(value: anytype) !DateTime {
    const T = @TypeOf(value);
    if (T == DateTime) return value;
    return switch (@typeInfo(T)) {
        .optional => if (value) |capture| try resolveDateTime(capture) else error.ZmplDateTimeFormatNull,
        .pointer => |info| if (info.size == .one)
            try resolveDateTime(value.*)
        else
            try DateTime.parse(value),
        else => @compileError("Unsupported datetime type: `" ++ @typeName(T) ++ "`"),
    };
}

pub fn sanitize(self: Format, value: anytype) ![]const u8 {
    for (try resolveString(value)) |char| {
        const output = switch (char) {
            '<' => "&lt;",
            '>' => "&gt;",
            '"' => "&quot;",
            '\'' => "&#039;",
            '&' => "&amp;",
            else => &.{char},
        };
        try self.writer.writeAll(output);
    }
    return "";
}

pub fn raw(self: Format, value: anytype) ![]const u8 {
    try self.writer.writeAll(try resolveString(value));
    return "";
}

fn resolveString(value: anytype) ![]const u8 {
    return switch (@typeInfo(@TypeOf(value))) {
        .optional => if (value) |capture| capture else "",
        else => value,
    };
}

pub fn json(self: Format, value: anytype) ![]const u8 {
    try Stringify.value(value, .{}, self.writer);
    return "";
}
