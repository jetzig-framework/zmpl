const std = @import("std");

const build_options = @import("build_options");

pub const zmd = @import("zmd");
pub const jetcommon = @import("jetcommon");

// XXX: Ensure that `@import("zmpl").zmpl` always works. This is a workaround to allow Zmpl to be
// imported at build time because `@import("zmpl")` at build time imports `zmpl/build.zig`.
pub const zmpl = @This();

/// Generic, JSON-compatible data type.
pub const Data = @import("zmpl/Data.zig");
pub const Template = @import("zmpl/Template.zig");
const Writer = std.Io.Writer;
pub const Manifest = Template.Manifest;
pub const colors = @import("zmpl/colors.zig");
pub const format = @import("zmpl/format.zig");
pub const debug = @import("zmpl/debug.zig");

pub const isZmplValue = Data.isZmplValue;

pub const InitOptions = struct {
    templates_path: []const u8 = "src/templates",
};

pub const util = @import("zmpl/util.zig");

pub const find = Manifest.find;
pub const findPrefixed = Manifest.findPrefixed;

pub fn chomp(input: []const u8) []const u8 {
    return std.mem.trimRight(u8, input, "\r\n");
}

/// Sanitize input. Used internally for rendering data refs. Use `zmpl.fmt.sanitize` to manually
/// sanitize other values.
pub fn sanitize(writer: *Writer, input: []const u8) !void {
    if (!build_options.sanitize) {
        _ = try writer.write(input);
        return;
    }
    _ = try format.sanitize(input);
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

    // Handle ZmplValue
    if (comptime isZmplValue(T)) {
        return value.isPresent();
    }

    // For booleans, return the value directly
    if (T == bool) return value;

    // For strings, check if the string is not empty
    if (comptime std.meta.trait.isZigString(T)) {
        return value.len > 0;
    }

    // For numbers, check if the value is not zero
    if (comptime std.meta.trait.isNumber(T)) {
        return value != 0;
    }

    // Default to true for any other value that exists
    return true;
}

pub fn refIsPresent(data: *Data, ref_key: []const u8) !bool {
    return data.refPresence(ref_key);
}

test {
    std.testing.refAllDecls(@This());
}
