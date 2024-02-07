const std = @import("std");

// XXX: Ensure that `@import("zmpl").zmpl` always works. This is a workaround to allow Zmpl to be
// imported at build time because, for some reason, doing `@import("zmpl")` at build time imports
// `zmpl/build.zig` instead of `zmpl/src/zmpl.zig`. This is probably due to a misconfiguration in
// Zmpl.
pub const zmpl = @This();

pub const Template = @import("./zmpl/Template.zig");
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
