const std = @import("std");

pub const zmd = @import("zmd");

pub const manifest = @import("zmpl.manifest").__Manifest;

const Data = @import("Data.zig");
const debug = @import("debug.zig");

name: []const u8,
prefix: []const u8,
key: []const u8,
_render: RenderWithMarkdownFormatterFn,
_renderWithLayout: RenderWithLayoutFn,

const Template = @This();

pub const RenderFn = *const fn (*Data) anyerror![]const u8;
pub const RenderWithMarkdownFormatterFn = *const fn (*Data) anyerror![]const u8;
pub const RenderWithLayoutFn = *const fn (Template, *Data) anyerror![]const u8;
pub const RenderOptions = struct {
    layout: ?manifest.Template = null,
};

pub fn render(self: Template, data: *Data) ![]const u8 {
    return self.renderWithOptions(data, .{});
}

pub fn renderWithOptions(self: Template, data: *Data, options: RenderOptions) ![]const u8 {
    return if (options.layout) |layout|
        self._renderWithLayout(layout, data) catch |err| {
            if (@errorReturnTrace()) |stack_trace| {
                try debug.printSourceInfo(data.allocator(), err, stack_trace);
            }
            return err;
        }
    else
        self._render(data) catch |err| {
            if (@errorReturnTrace()) |stack_trace| {
                try debug.printSourceInfo(data.allocator(), err, stack_trace);
            }
            return err;
        };
}
