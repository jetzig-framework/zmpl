const std = @import("std");

// XXX: Ensure that `@import("zmpl").zmpl` always works. This is a workaround to allow Zmpl to be
// imported at build time because `@import("zmpl")` at build time imports `zmpl/build.zig`.
pub const zmpl = @This();

/// Generic, JSON-compatible data type.
pub const Data = @import("./zmpl/Data.zig");

pub const manifest = @import("zmpl.manifest").__Manifest;
pub const Template = manifest.Template;

pub const InitOptions = struct {
    templates_path: []const u8 = "src/templates",
};

pub const util = @import("zmpl/util.zig");

pub const find = manifest.find;

pub fn chomp(input: []const u8) []const u8 {
    return std.mem.trimRight(u8, input, "\r\n");
}
