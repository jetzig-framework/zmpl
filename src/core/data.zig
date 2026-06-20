//! Output stream for writing values into a rendered template. The render data is the
//! comptime-known `context` stored on `Data(Context)`; templates read all values from it.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const ArenaAllocator = std.heap.ArenaAllocator;
const Writer = std.Io.Writer;
const Stringify = std.json.Stringify;
const blush = @import("blush");
const cyan = blush.new().fg(.cyan);
const yellow = blush.new().fg(.yellow);
const bright_red = blush.new().fg(.bright_red);
const red = blush.new().fg(.red);

const zmpl = @import("../root.zig");
const util = zmpl.util;

pub var log_errors = true;

pub const LayoutContent = struct {
    data: []const u8,

    pub fn format(self: LayoutContent, writer: *Writer) !void {
        try writer.writeAll(self.data);
    }
};

pub const Slot = struct {
    data: []const u8,

    pub fn format(self: Slot, writer: *Writer) !void {
        try writer.writeAll(self.data);
    }
};

pub const ErrorName = enum { ref, type, syntax, constant, compare };
pub const ZmplError = error{
    ZmplUnknownDataReferenceError,
    ZmplTypeError,
    ZmplSyntaxError,
    ZmplConstantError,
    ZmplCompareError,
    ZmplCoerceError,
};

pub fn zmplError(comptime err_name: ErrorName, comptime message: []const u8, args: anytype) ZmplError {
    const err = switch (err_name) {
        .ref => error.ZmplUnknownDataReferenceError,
        .type => error.ZmplTypeError,
        .syntax => error.ZmplSyntaxError,
        .constant => error.ZmplConstantError,
        .compare => error.ZmplCompareError,
    };

    if (log_errors) {
        std.debug.print(
            std.fmt.comptimePrint(
                "{s} [{s}:{s}] {s}\n",
                .{
                    cyan.renderComptime("[zmpl]"),
                    yellow.renderComptime("error"),
                    bright_red.renderComptime(@errorName(err)),
                    red.renderComptime(message),
                },
            ),
            args,
        );
    }

    return err;
}

pub fn unknownRef(name: []const u8) ZmplError {
    return zmplError(.ref, "Unknown data reference: `{s}`", .{name});
}

pub const Interface = @import("Interface.zig");

/// Per-render state plus the comptime-known `context`. Initialize with `init`, then render a
/// template via the generated manifest, which reads all data from `context`.
pub fn Data(comptime Context: type) type {
    return struct {
        const Self = @This();

        /// User-defined, comptime-known render context.
        context: Context = undefined,
        interface: Interface,

        /// Creates a new `Data` instance.
        pub fn init(io: Io, gpa: Allocator, context: Context) Self {
            const arena = gpa.create(ArenaAllocator) catch unreachable;
            arena.* = .init(gpa);

            const arena_allocator = arena.allocator();

            var output_buf = arena_allocator.create(Writer.Allocating) catch unreachable;
            output_buf.* = .init(arena_allocator);
            _ = &output_buf;

            return .{
                .context = context,
                .interface = .{
                    .parent_allocator = gpa,
                    .arena = arena,
                    .allocator = arena_allocator,
                    .output_buf = output_buf,
                    .output_writer = &output_buf.writer,
                    .partial = false,
                    .content = .{ .data = "" },
                    .fmt = .{ .writer = &output_buf.writer },
                    .io = io,
                },
            };
        }

        /// Frees all resources used by this `Data` instance.
        pub fn deinit(self: *Self) void {
            self.interface.output_buf.clearRetainingCapacity();
            self.interface.output_buf.deinit();
            self.interface.arena.deinit();
            self.interface.parent_allocator.destroy(self.interface.arena);
        }
    };
}
