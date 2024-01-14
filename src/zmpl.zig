const std = @import("std");

pub const Template = @import("./zmpl/Template.zig");
pub const Data = @import("./zmpl/Data.zig");
pub const ZmplBuild = @import("./zmpl/Build.zig");

pub const InitOptions = struct {
    templates_path: []const u8 = "src/templates",
    manifest_path: []const u8 = "src/templates/manifest.zig",
};

pub fn init(build: *std.Build, lib: *std.Build.Step.Compile, options: InitOptions) !void {
    var zmpl_build = ZmplBuild.init(build, lib, options.manifest_path, options.templates_path);
    try zmpl_build.compile();
}
