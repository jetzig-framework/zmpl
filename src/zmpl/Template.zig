const std = @import("std");

pub const zmd = @import("zmd");

pub const manifest = @import("zmpl.manifest");
pub const Manifest = manifest.__Manifest;

const Data = @import("Data.zig");
const debug = @import("debug.zig");

name: []const u8,
prefix: []const u8,
key: []const u8,

const Template = @This();

pub const RenderOptions = struct {
    layout: ?Manifest.Template = null,
};

pub fn render(
    self: Template,
    data: *Data,
    Context: ?type,
    context: if (Context) |C| C else @TypeOf(null),
    options: RenderOptions,
) ![]const u8 {
    const DefaultContext = struct {};
    const C = Context orelse DefaultContext;
    const c = if (comptime Context == null) DefaultContext{} else context;

    return if (options.layout) |layout| blk: {
        inline for (Manifest.templates) |template| {
            if (std.mem.eql(u8, template.name, self.name)) {
                const renderFn = @field(manifest, template.name ++ "_renderWithLayout");
                break :blk renderFn(layout, data, C, c) catch |err| {
                    if (@errorReturnTrace()) |stack_trace| {
                        try debug.printSourceInfo(data.allocator(), err, stack_trace);
                    }
                    break :blk err;
                };
            }
        }
        unreachable;
    } else blk: {
        inline for (Manifest.templates) |template| {
            if (std.mem.eql(u8, template.name, self.name)) {
                const renderFn = @field(manifest, template.name ++ "_render");
                break :blk renderFn(data, C, c) catch |err| {
                    if (@errorReturnTrace()) |stack_trace| {
                        try debug.printSourceInfo(data.allocator(), err, stack_trace);
                    }
                    break :blk err;
                };
            }
        }
        unreachable;
    };
}
