const std = @import("std");

// XXX: Ensure that `@import("zmpl").zmpl` always works. This is a workaround to allow Zmpl to be
// imported at build time because `@import("zmpl")` at build time imports `zmpl/build.zig`.
pub const zmpl = @This();

/// Reads a template source file, parses it, and compiles it into a Zig function that, when
/// called (receiving a `Data` argument), renders the output of the template as a `[]const u8`.
pub const Template = @import("./zmpl/Template.zig");

/// Generic, JSON-compatible data type.
pub const Data = @import("./zmpl/Data.zig");
pub const ZmplBuild = @import("./zmpl/Build.zig");

pub const InitOptions = struct {
    templates_path: []const u8 = "src/templates",
    manifest_path: []const u8 = "src/templates/zmpl.manifest.zig",
};

pub fn init(build: *std.Build, lib: *std.Build.Step.Compile, options: InitOptions) !void {
    var zmpl_build = ZmplBuild.init(build, lib, options.manifest_path, options.templates_path);
    try zmpl_build.compile();
}
