const Interface = @This();

arena: *ArenaAllocator,
allocator: Allocator,
parent_allocator: Allocator,
output_buf: *Writer.Allocating,
output_writer: *Writer,
partial: bool = false,
content: LayoutContent = .{ .data = "" },
slots: ?[]const Slot = null,
fmt: zmpl.Format,
io: std.Io,

/// Convenience wrapper for `util.strip` to be used by compiled templates. Takes (and discards)
/// `self` so templates can call it as `data_struct.interface.strip(...)`.
pub fn strip(_: Interface, input: []const u8) []const u8 {
    return util.strip(input);
}

pub fn sanitize(self: *Interface, input: []const u8) !void {
    const fmt: zmpl.Format = .{ .writer = self.output_writer };
    try fmt.sanitize(input);
}

/// Convenience wrapper for `util.chomp` to be used by compiled templates. Takes (and discards)
/// `self` so templates can call it as `data_struct.interface.chomp(...)`.
pub fn chomp(_: Interface, input: []const u8) []const u8 {
    return util.chomp(input);
}

pub fn toJsonAlloc(self: *Interface, value: anytype, options: Options) ![]const u8 {
    var buffer: Writer.Allocating = .init(self.allocator);
    defer buffer.deinit();
    try toJson(value, &buffer.writer, options);
    return buffer.toOwnedSlice();
}

pub fn toJson(value: anytype, writer: *Writer, options: Options) !void {
    try Stringify.value(value, options, writer);
}

/// Chomps output buffer.
pub fn chompOutputBuffer(self: *Interface) void {
    if (std.mem.endsWith(u8, self.output_writer.buffered(), "\n"))
        self.output_writer.undo(1);
    if (std.mem.endsWith(u8, self.output_writer.buffered(), "\r"))
        self.output_writer.undo(1);
}

/// Coerce an arbitrary value to its string representation for rendering in a template.
pub fn coerceString(self: *Interface, value: anytype) ![]const u8 {
    const formatter: Formatter = switch (@typeInfo(@TypeOf(value))) {
        .bool => .default,
        .int => .default,
        .float => .float,
        .@"enum" => .enum_name,
        .@"struct" => blk: {
            if (@hasDecl(@TypeOf(value), "format")) {
                break :blk .default;
            } else {
                return zmplError(
                    .syntax,
                    "Struct does not implement `format()`: " ++ red.renderComptime("{s}"),
                    .{@TypeOf(value)},
                );
            }
        },
        .comptime_float => .float,
        .comptime_int => .default,
        .null => .none,
        .optional => if (@TypeOf(value) == ?[]const u8) .optional_string else .optional_default,
        .@"union" => .default,
        .pointer => |pointer| switch (pointer.child) {
            []const u8 => |child| blk: {
                if (isStringCoercablePointer(pointer, child)) {
                    break :blk .string_array;
                } else {
                    return zmplError(
                        .type,
                        "Unsupported type: " ++ red.renderComptime("{s}"),
                        .{@typeName(@TypeOf(pointer))},
                    );
                }
            },
            u8 => |child| blk: {
                if (isStringCoercablePointer(pointer, child)) {
                    break :blk .string;
                } else {
                    return zmplError(
                        .syntax,
                        "Unsupported type: " ++ red.renderComptime("{s}"),
                        .{@typeName(@TypeOf(pointer))},
                    );
                }
            },
            []u8 => .string,
            type => blk: {
                if (@hasDecl(@TypeOf(value.*), "format")) {
                    break :blk .default;
                } else {
                    return zmplError(
                        .type,
                        "Struct does not implement `format()`: " ++ red.renderComptime("{s}"),
                        .{@TypeOf(value.*)},
                    );
                }
            },
            inline else => blk: {
                const child = @typeInfo(pointer.child);
                if (child == .array) {
                    const arr = &child.array;
                    if (arr.child == u8) break :blk .string;
                }
                return zmplError(
                    .type,
                    "Unsupported type: " ++ red.renderComptime("{s}"),
                    .{@typeName(@TypeOf(pointer))},
                );
            },
        },

        // This must be consistent with `std.builtin.Type` - we want to see an error if a
        // new field is added so we specifically do not want an `else` clause here:
        .type,
        .void,
        .noreturn,
        .array,
        .undefined,
        .error_union,
        .error_set,
        .@"fn",
        .@"opaque",
        .frame,
        .@"anyframe",
        .vector,
        .enum_literal,
        => {
            return zmplError(
                .type,
                "Unsupported type: " ++ red.renderComptime("{s}"),
                .{@typeName(@TypeOf(value))},
            );
        },
    };

    const arena = self.allocator;

    return switch (formatter) {
        .default => try std.fmt.allocPrint(arena, "{any}", .{value}),
        .optional_default => try std.fmt.allocPrint(arena, "{?}", .{value}),
        .string => try std.fmt.allocPrint(arena, "{s}", .{value}),
        .optional_string => try std.fmt.allocPrint(arena, "{?s}", .{value}),
        .string_array => try std.mem.join(arena, "\n", value),
        .float => try std.fmt.allocPrint(arena, "{d}", .{value}),
        .enum_name => @tagName(value),
        .none => "",
    };
}

/// Write a given string to the output buffer. Used by compiled Zmpl templates.
pub fn write(self: *Interface, maybe_err_slice: anytype) !void {
    const slice = try self.resolveSlice(maybe_err_slice);
    try self.output_buf.writer.writeAll(slice);
}

/// No-op function. Used by templates to prevent unused local constant errors for values
/// that might not be used by the template (e.g. allocator).
pub fn noop(_: Interface, T: type, _: T) void {}

// Resolve an optional or error union to a `[]const u8`. Empty string if optional is null,
// error if error union is an error.
fn resolveSlice(self: *Interface, maybe_err_slice: anytype) ![]const u8 {
    return switch (@typeInfo(@TypeOf(maybe_err_slice))) {
        .error_union => if (maybe_err_slice) |slice| try self.resolveSlice(slice) else |err| err,
        .optional => if (maybe_err_slice) |slice| self.resolveSlice(slice) else "",
        else => try self.coerceString(maybe_err_slice), // Let Zig compiler fail if incorrect type.
    };
}

fn isStringCoercablePointer(pointer: std.builtin.Type.Pointer, child: type) bool {
    const child_info = @typeInfo(child);

    // Logic borrowed from old implementation of std.meta.isZigString
    if (!pointer.is_volatile and
        !pointer.is_allowzero and
        pointer.size == .slice and pointer.child == u8) return true;
    if (!pointer.is_volatile and
        !pointer.is_allowzero and pointer.size == .one and
        child_info == .array and
        child_info.array.child == u8) return true;
    return false;
}

const Formatter = enum {
    default,
    optional_default,
    string,
    optional_string,
    string_array,
    float,
    enum_name,
    none,
};

const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Data = @import("data.zig");
const LayoutContent = Data.LayoutContent;
const Slot = Data.Slot;
const zmpl = @import("../root.zig");
const Stringify = std.json.Stringify;
const util = @import("util.zig");
const zmplError = Data.zmplError;
const Options = Stringify.Options;
const blush = @import("blush");
const red = blush.style(.{ .foreground = .red });
