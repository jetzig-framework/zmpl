const std = @import("std");

const build_options = @import("build_options");

pub const zmd = @import("zmd");

// XXX: Ensure that `@import("zmpl").zmpl` always works. This is a workaround to allow Zmpl to be
// imported at build time because `@import("zmpl")` at build time imports `zmpl/build.zig`.
pub const zmpl = @This();

/// Generic, JSON-compatible data type.
pub const Data = @import("zmpl/Data.zig");
pub const Template = @import("zmpl/Template.zig");
pub const manifest = Template.manifest;
pub const colors = @import("zmpl/colors.zig");
pub const Format = @import("zmpl/Format.zig");
pub const isZmplValue = Data.isZmplValue;

pub const InitOptions = struct {
    templates_path: []const u8 = "src/templates",
};

pub const util = @import("zmpl/util.zig");

pub const find = manifest.find;
pub const findPrefixed = manifest.findPrefixed;

pub fn chomp(input: []const u8) []const u8 {
    return std.mem.trimRight(u8, input, "\r\n");
}

/// Sanitize input. Used internally for rendering data refs. Use `zmpl.fmt.sanitize` to manually
/// sanitize other values.
pub fn sanitize(writer: anytype, input: []const u8) !void {
    if (!build_options.sanitize) {
        _ = try writer.write(input);
        return;
    }

    const fmt = Format{ .writer = if (@TypeOf(writer) == *Data) writer.output_writer else writer };
    _ = try fmt.sanitize(input);
}

test {
    std.testing.refAllDecls(@This());
}
