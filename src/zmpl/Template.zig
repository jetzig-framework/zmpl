const std = @import("std");

pub const zmd = @import("zmd");

pub const manifest = @import("zmpl.manifest");
pub const Manifest = manifest.__Manifest;

const Data = @import("Data.zig");
const debug = @import("debug.zig");

name: []const u8,
prefix: []const u8,
key: []const u8,
blocks: []const Block,

const Template = @This();

pub const Block = struct {
    name: []const u8,
    func: []const u8,
};

/// Options to control specific render behaviour.
pub const RenderOptions = struct {
    /// Specify a layout to wrap the rendered content within. In the template layout, use
    /// `{{zmpl.content}}` to render the inner content.
    layout: ?Manifest.Template = null,
};

pub fn render(
    self: Template,
    io: std.Io,
    data: *Data,
    Context: ?type,
    context: if (Context) |C| C else @TypeOf(null),
    comptime blocks: []const Block,
    options: RenderOptions,
) ![]const u8 {
    const DefaultContext = struct {};
    const C = Context orelse DefaultContext;
    const c = if (comptime Context == null) DefaultContext{} else context;

    return if (options.layout) |layout| blk: {
        inline for (Manifest.templates) |template| {
            if (std.mem.eql(u8, template.name, self.name)) {
                const renderFn = @field(Manifest, template.name ++ "_renderWithLayout");
                break :blk renderFn(layout, data, C, c, template.blocks) catch |err| {
                    if (@errorReturnTrace()) |stack_trace| {
                        try debug.printSourceInfo(io, data.allocator, err, stack_trace);
                    }
                    break :blk err;
                };
            }
        }
        unreachable;
    } else blk: {
        inline for (Manifest.templates) |template| {
            if (std.mem.eql(u8, template.name, self.name)) {
                const renderFn = @field(Manifest, template.name ++ "_render");
                break :blk renderFn(data, C, c, blocks) catch |err| {
                    if (@errorReturnTrace()) |stack_trace| {
                        try debug.printSourceInfo(io, data.allocator, err, stack_trace);
                    }
                    break :blk err;
                };
            }
        }
        unreachable;
    };
}
