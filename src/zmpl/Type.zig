// I don't have a good name for this yet
const std = @import("std");
const StringArrayHashMap = std.StringArrayHashMap;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const zmpl = @import("../zmpl.zig");
const Stringify = std.json.Stringify;
const Writer = std.Io.Writer;
const jetcommon = @import("jetcommon");
const ToJsonOptions = @import("Data.zig").ToJsonOptions;
const DateTime = jetcommon.types.DateTime;
const Value = @import("Data.zig").Value;

pub const Info = union(enum) {
    int: i128,
    null: null,
    bool: bool,
    float: f128,
    string: []const u8,
    datetime: DateTime,

    pub fn init(info: Info) Info {
        return info;
    }

    pub fn deinit(self: *Info, allocator: Allocator) void {
        switch (self) {
            .array => self.array.array.clearAndFree(allocator),
            else => {},
        }
        self.* = undefined;
    }

    pub fn value(self: Info) switch (self) {
        .int => i128,
        .null => null,
        .bool => bool,
        .float => f128,
        .string => []const u8,
        .datetime => DateTime,
    } {
        return switch (self) {
            else => |val| val,
        };
    }

    pub fn eql(self: Info, other: Info) bool {
        switch (self.info) {
            .int, .null, .float, .bool => return defaultEql(self, other),
            .string => |this| {
                const that = other.value();
                if (isSameType(this, that)) return std.mem.eql(u8, this, that);
                return false;
            },
            .datetime => |this| {
                const that = other.value();
                if (isSameType(this, that)) return this.eql(that);
                return false;
            },
        }
    }

    pub fn toJson(
        self: Info,
        allocator: Allocator,
        writer: *Writer,
        comptime options: ToJsonOptions,
    ) !void {
        switch (self.info) {
            .int => |val| try highlight(writer, .integer, .{val}, options.color),
            .float => |val| try highlight(writer, .float, .{val}, options.color),
            .bool => |val| try highlight(writer, .boolean, .{val}, options.color),
            .null => try highlight(writer, .null, .{}, options.color),
            .string => |val| {
                var aw: Writer.Allocating = .init(allocator);
                defer aw.deinit();
                try Stringify.value(val, .{}, &aw.writer);
                try highlight(
                    writer,
                    .string,
                    .{try aw.toOwnedSlice()},
                    options.color,
                );
            },
            .datetime => |val| {
                var aw: Writer.Allocating = .init(allocator);
                defer aw.deinit();
                try val.toJson(&aw.writer);
                try highlight(
                    writer,
                    .datetime,
                    .{try aw.toOwnedSlice()},
                    options.color,
                );
            },
        }
    }

    pub fn toString(self: Info, allocator: Allocator) ![]const u8 {
        return switch (self.info) {
            .int => |val| std.fmt.allocPrint(allocator, "{}", .{val}),
            .float => |val| std.fmt.allocPrint(allocator, "{d}", .{val}),
            .bool => |val| std.fmt.allocPrint(allocator, "{}", .{val}),
            .null, .array => "",
            .string => |val| val,
            .datetime => |val| blk: {
                var aw: Writer.Allocating = .init(allocator);
                defer aw.deinit();
                try val.toString(&aw.writer);
                break :blk aw.toOwnedSlice();
            },
        };
    }
};

fn isSameType(this: anytype, that: anytype) bool {
    return @TypeOf(this) == @TypeOf(that);
}

/// simple comparison between simple like objects
fn defaultEql(self: Info, other: Info) bool {
    const this = self.value();
    const that = other.value();
    if (isSameType(this, that)) return this == that;
    return false;
}

pub const Syntax = enum {
    open_array,
    close_array,
    open_object,
    close_object,
    field,
    float,
    integer,
    string,
    boolean,
    datetime,
    null,
};

pub fn highlight(writer: *Writer, comptime syntax: Syntax, args: anytype, comptime color: bool) !void {
    const template = comptime switch (syntax) {
        .open_array => if (color) zmpl.colors.cyan("[") else "[",
        .close_array => if (color) zmpl.colors.cyan("]") else "]",
        .open_object => if (color) zmpl.colors.cyan("{{") else "{{",
        .close_object => if (color) zmpl.colors.cyan("}}") else "}}",
        .field => if (color) zmpl.colors.yellow("{s}") else "{s}",
        .float => if (color) zmpl.colors.magenta("{}") else "{}",
        .integer => if (color) zmpl.colors.blue("{}") else "{}",
        .string => if (color) zmpl.colors.green("{s}") else "{s}",
        .datetime => if (color) zmpl.colors.bright(.blue, "{s}") else "{s}",
        .boolean => if (color) zmpl.colors.green("{}") else "{}",
        .null => if (color) zmpl.colors.cyan("null") else "null",
    };

    try writer.print(template, args);
}
