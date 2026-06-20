const std = @import("std");
const Writer = std.Io.Writer;
const zmd = @import("zmd");
const datetime = @import("datetime");
const data = @import("core/data.zig");

/// Compile-time Zmpl configuration (the replacement for the old generated `zmpl_options` module).
pub const Config = @import("Config.zig");

/// Factory that builds the per-render `Data` type carrying the comptime-known `context`. Templates
/// read all render data from `context`.
pub const Data = data.Data;
pub const Slot = data.Slot;
pub const LayoutContent = data.LayoutContent;
pub const ErrorName = data.ErrorName;
pub const ZmplError = data.ZmplError;
pub const zmplError = data.zmplError;
pub const Interface = data.Interface;
pub const unknownRef = data.unknownRef;

pub const Format = @import("core/Format.zig");
pub const util = @import("core/util.zig");

/// Returns true if `T` is a pointer to a `Data(Context)` instance.
pub fn isData(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .pointer) return false;
    const Child = info.pointer.child;
    return @typeInfo(Child) == .@"struct" and
        @hasField(Child, "interface") and @hasField(Child, "context");
}

pub const InitOptions = struct {
    templates_path: []const u8 = "src/templates",
};

pub fn chomp(input: []const u8) []const u8 {
    return std.mem.trimEnd(u8, input, "\r\n");
}

/// Sanitize input. Always applied when rendering data refs. Use `zmpl.fmt.sanitize` to manually
/// sanitize other values.
pub fn sanitize(writer: *Writer, input: []const u8) !void {
    const fmt = Format{ .writer = writer };
    _ = try fmt.sanitize(input);
}

/// Check if a value is present for use in if conditions.
/// This is used to make nullable values behave intuitively in if statements.
/// For example, `@if (foo.bar)` will be true if `foo.bar` is not null.
pub fn isPresent(value: anytype) !bool {
    const T = @TypeOf(value);

    // Handle null values
    if (T == @TypeOf(null)) return false;

    // Handle optional values
    if (@typeInfo(T) == .optional) {
        if (value == null) return false;
        return try isPresent(value.?);
    }

    // For booleans, return the value directly
    if (T == bool) return value;

    return switch (@typeInfo(T)) {
        // For numbers, check if the value is not zero
        .int, .comptime_int, .float, .comptime_float => value != 0,
        // For strings, check if the string is not empty
        .pointer => |ptr| if (ptr.size == .slice and ptr.child == u8) value.len > 0 else true,
        // Default to true for any other value that exists
        else => true,
    };
}

pub const CompareOp = enum { equal, less_than, greater_than, less_or_equal, greater_or_equal };

/// Compare two context values in an `@if` condition. Strings compare by content; everything else
/// uses the corresponding Zig operator.
pub fn compare(comptime op: CompareOp, lhs: anytype, rhs: anytype) !bool {
    if (comptime isStringValue(@TypeOf(lhs)) and isStringValue(@TypeOf(rhs))) {
        return switch (op) {
            .equal => std.mem.eql(u8, lhs, rhs),
            .less_than => std.mem.order(u8, lhs, rhs) == .lt,
            .greater_than => std.mem.order(u8, lhs, rhs) == .gt,
            .less_or_equal => std.mem.order(u8, lhs, rhs) != .gt,
            .greater_or_equal => std.mem.order(u8, lhs, rhs) != .lt,
        };
    }
    return switch (op) {
        .equal => lhs == rhs,
        .less_than => lhs < rhs,
        .greater_than => lhs > rhs,
        .less_or_equal => lhs <= rhs,
        .greater_or_equal => lhs >= rhs,
    };
}

fn isStringValue(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |p| (p.size == .slice and p.child == u8) or
            (p.size == .one and @typeInfo(p.child) == .array and @typeInfo(p.child).array.child == u8),
        else => false,
    };
}

test {
    std.testing.refAllDecls(@This());
}
