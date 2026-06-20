const std = @import("std");
const Writer = std.Io.Writer;
const _zmd = @import("zmd");

/// Constants made available as a local `const` in every compiled template, declared by name and
/// type. Replaces the old `zmpl_options.template_constants`. Each constant is bound to the
/// matching field on the comptime-known render `context`, so every template's `Context` must
/// expose a field of the declared name and type.
constants: []const Constant = &.{},

/// Raw Zig source prepended to the generated manifest.
headers: []const u8 = "",

/// Markdown rendering configuration.
zmd: _zmd.Config = .{ .root = divFormatter },

/// A single named constant available to every template, declared by name and type.
pub const Constant = struct {
    name: []const u8,
    type: type,
};

fn divFormatter(writer: *Writer, _: _zmd.Node) anyerror![]const u8 {
    try writer.writeAll(
        \\<div>
        \\
    );
    return
    \\</div>
    \\
    ;
}
