const std = @import("std");

pub const ZmplOptions = struct {
    markdown_fragments: fn (*std.Io.Writer) anyerror!void,
};

