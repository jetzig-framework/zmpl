const std = @import("std");

pub const Writer = std.ArrayList(u8).Writer;

const Self = @This();

_allocator: std.mem.Allocator,
arena: ?std.heap.ArenaAllocator = null,
arena_allocator: std.mem.Allocator = undefined,
json_buf: std.ArrayList(u8),
output_buf: std.ArrayList(u8),
output_writer: ?std.ArrayList(u8).Writer = null,
value: ?Value = null,
Null: Value = .{ .Null = NullType{} },

pub fn init(allocator: std.mem.Allocator) Self {
    const json_buf = std.ArrayList(u8).init(allocator);
    const output_buf = std.ArrayList(u8).init(allocator);

    return .{
        ._allocator = allocator,
        .json_buf = json_buf,
        .output_buf = output_buf,
    };
}

pub fn deinit(self: *Self) void {
    if (self.arena) |arena| arena.deinit();
    self.output_buf.deinit();
    self.json_buf.deinit();
}

pub fn getValue(self: *Self, key: []const u8) !?Value {
    if (self.value) |val| {
        var tokens = std.mem.splitSequence(u8, key, ".");
        var current_value = val;

        while (tokens.next()) |token| {
            switch (current_value) {
                .object => |*capture| {
                    var capt = capture.*;
                    current_value = capt.get(token) orelse return null;
                },
                .array => |*capture| {
                    var capt = capture.*;
                    current_value = capt.get(try std.fmt.parseInt(usize, token, 10)) orelse return null;
                },
                else => |*capture| {
                    return capture.*;
                },
            }
        }
        return current_value;
    } else return null;
}

pub fn getValueString(self: *Self, key: []const u8) ![]const u8 {
    if (try self.getValue(key)) |val| {
        switch (val) {
            .object, .array => return "", // Implement on Object and Array ?
            else => |*capture| {
                var v = capture.*;
                return try v.toString();
            },
        }
    } else return "";
}

pub fn reset(self: *Self) void {
    if (self.value) |*ptr| {
        ptr.deinit();
    }
    self.value = null;
}

pub fn object(self: *Self) !*Value {
    if (self.value) |_| {
        return try self.createObject();
    } else {
        self.value = (try self.createObject()).*;
        return &self.value.?;
    }
}

pub fn createObject(self: *Self) !*Value {
    const obj = Object.init(self.getAllocator());
    const ptr = try self.getAllocator().create(Value);
    ptr.* = Value{ .object = obj };
    return ptr;
}

pub fn array(self: *Self) !*Value {
    const arr = Array.init(self.getAllocator());

    if (self.value) |_| {
        const ptr = try self.getAllocator().create(Value);
        ptr.* = Value{ .array = arr };
        return ptr;
    } else {
        self.value = Value{ .array = arr };
        return &self.value.?;
    }
}

pub fn string(self: *Self, value: []const u8) Value {
    return .{ .string = .{ .value = value, .allocator = self.getAllocator() } };
}

pub fn integer(self: *Self, value: i64) Value {
    return .{ .integer = .{ .value = value, .allocator = self.getAllocator() } };
}

pub fn float(self: *Self, value: f64) Value {
    return .{ .float = .{ .value = value, .allocator = self.getAllocator() } };
}

pub fn boolean(self: *Self, value: bool) Value {
    return .{ .boolean = .{ .value = value, .allocator = self.getAllocator() } };
}

pub fn write(self: *Self, slice: []const u8) !void {
    if (self.output_writer) |writer| {
        try writer.writeAll(slice);
    } else {
        self.output_writer = self.output_buf.writer();
        try (self.output_writer.?).writeAll(slice);
    }
}

pub fn read(self: *Self) []const u8 {
    return self.output_buf.items;
}

pub fn get(self: *Self, key: []const u8) !Value {
    return (try self.getValue(key)) orelse .{ .Null = NullType{} }; // XXX: Raise an error here ?
}

pub fn formatDecl(self: *Self, comptime decl: anytype) ![]const u8 {
    if (comptime isZigString(@TypeOf(decl))) {
        return try std.fmt.allocPrint(self.getAllocator(), "{s}", .{decl});
    } else {
        return try std.fmt.allocPrint(self.getAllocator(), "{}", .{decl});
    }
}

pub fn toJson(self: *Self) ![]const u8 {
    if (self.value) |_| {} else return "";

    const writer = self.json_buf.writer();
    self.json_buf.clearAndFree();
    try self.value.?.toJson(writer);
    return self._allocator.dupe(u8, self.json_buf.items[0..self.json_buf.items.len]);
}

pub fn fromJson(self: *Self, json: []const u8) !void {
    const parsed = try std.json.parseFromSlice(std.json.Value, self.getAllocator(), json, .{});
    self.value = try self.parseJsonValue(parsed.value);
}

fn parseJsonValue(self: *Self, value: std.json.Value) !Value {
    return switch (value) {
        .object => |*val| blk: {
            var it = val.iterator();
            const obj = try self.createObject();
            while (it.next()) |item| {
                try obj.put(item.key_ptr.*, try self.parseJsonValue(item.value_ptr.*));
            }
            break :blk obj.*;
        },
        .array => |*val| blk: {
            var arr = try self.array();
            for (val.items) |item| try arr.append(try self.parseJsonValue(item));
            break :blk arr.*;
        },
        .string => |val| self.string(val),
        .number_string => |val| self.string(val), // TODO: Special-case this somehow?
        .integer => |val| self.integer(val),
        .float => |val| self.float(val),
        .bool => |val| self.boolean(val),
        .null => self.Null,
    };
}

pub const Value = union(enum) {
    object: Object,
    array: Array,
    float: Float,
    integer: Integer,
    boolean: Boolean,
    string: String,
    Null: NullType,

    pub fn put(self: *Value, key: []const u8, value: Value) !void {
        switch (self.*) {
            .object => |*capture| try capture.put(key, value),
            inline else => unreachable,
        }
    }

    pub fn append(self: *Value, value: Value) !void {
        switch (self.*) {
            .array => |*capture| try capture.append(value),
            inline else => unreachable,
        }
    }

    pub fn toJson(self: *Value, writer: Writer) !void {
        return switch (self.*) {
            inline else => |*capture| try capture.toJson(writer),
        };
    }

    pub fn toString(self: *Value) ![]const u8 {
        return switch (self.*) {
            .object, .array => unreachable,
            inline else => |*capture| try capture.toString(),
        };
    }

    pub fn iterator(self: *Value) *Iterator {
        switch (self.*) {
            .array => |*capture| return capture.*.iterator(),
            .object => unreachable, // TODO
            else => unreachable, // TODO: return error
        }
    }

    pub fn deinit(self: *Value) void {
        switch (self.*) {
            .array => |*ptr| ptr.deinit(),
            .object => |*ptr| ptr.deinit(),
            else => {},
        }
    }
};

pub const NullType = struct {
    pub fn toJson(self: *NullType, writer: Writer) !void {
        _ = self;
        try writer.writeAll("null");
    }

    pub fn toString(self: *NullType) ![]const u8 {
        _ = self;
        return "";
    }
};

pub const Float = struct {
    value: f64,
    allocator: std.mem.Allocator,

    pub fn toJson(self: *Float, writer: Writer) !void {
        try writer.print("{}", .{self.value});
    }

    pub fn toString(self: *Float) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{}", .{self.value});
    }
};

pub const Integer = struct {
    value: i64,
    allocator: std.mem.Allocator,

    pub fn toJson(self: *Integer, writer: Writer) !void {
        try writer.print("{}", .{self.value});
    }

    pub fn toString(self: *Integer) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{}", .{self.value});
    }
};

pub const Boolean = struct {
    value: bool,
    allocator: std.mem.Allocator,

    pub fn toJson(self: *Boolean, writer: Writer) !void {
        try writer.writeAll(if (self.value) "true" else "false");
    }

    pub fn toString(self: *Boolean) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{}", .{self.value});
    }
};

pub const String = struct {
    value: []const u8,
    allocator: std.mem.Allocator,

    pub fn toJson(self: *String, writer: Writer) !void {
        try std.json.encodeJsonString(self.value, .{}, writer);
    }

    pub fn toString(self: *String) ![]const u8 {
        return self.value;
    }
};

pub const Object = struct {
    hashmap: std.StringHashMap(Value),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Object {
        return .{ .hashmap = std.StringHashMap(Value).init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *Object) void {
        var it = self.hashmap.iterator();
        while (it.next()) |entry| {
            self.allocator.destroy(entry.key_ptr);
            self.allocator.destroy(entry.value_ptr);
        }
        self.hashmap.clearAndFree();
    }

    pub fn put(self: *Object, key: []const u8, value: Value) !void {
        const ptr = try self.allocator.create(Value);
        ptr.* = value;
        try self.hashmap.put(try self.allocator.dupe(u8, key), ptr.*);
    }

    pub fn get(self: *Object, key: []const u8) ?Value {
        if (self.hashmap.getEntry(key)) |entry| {
            return entry.value_ptr.*;
        } else return null;
    }

    pub fn toJson(self: *Object, writer: Writer) anyerror!void {
        try writer.writeAll("{");
        var it = self.hashmap.keyIterator();
        var index: i64 = 0;
        const count = self.hashmap.count();
        while (it.next()) |key| {
            try std.json.encodeJsonString(key.*, .{}, writer);
            try writer.writeAll(":");
            var value = self.hashmap.get(key.*).?;
            try value.toJson(writer);
            index += 1;
            if (index < count) try writer.writeAll(",");
        }
        try writer.writeAll("}");
    }
};

pub const Array = struct {
    allocator: std.mem.Allocator,
    array: std.ArrayList(Value),
    it: Iterator = undefined,

    pub fn init(allocator: std.mem.Allocator) Array {
        return .{ .array = std.ArrayList(Value).init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *Array) void {
        self.array.clearAndFree();
    }

    pub fn get(self: *Array, index: usize) ?Value {
        return if (self.array.items.len > index) self.array.items[index] else null;
    }

    pub fn append(self: *Array, value: Value) !void {
        try self.array.append(value);
    }

    pub fn toJson(self: *Array, writer: Writer) anyerror!void {
        try writer.writeAll("[");
        for (self.array.items, 0..) |*item, index| {
            try item.toJson(writer);
            if (index < self.array.items.len - 1) try writer.writeAll(",");
        }
        try writer.writeAll("]");
    }

    pub fn iterator(self: *Array) *Iterator {
        self.it = .{ .array = self.array };
        return &self.it;
    }
};

pub const Iterator = struct {
    array: std.ArrayList(Value),
    index: usize = 0,

    pub fn next(self: *Iterator) ?Value {
        self.index += 1;
        if (self.index > self.array.items.len) return null;
        return self.array.items[self.index - 1];
    }
};

pub fn getAllocator(self: *Self) std.mem.Allocator {
    if (self.arena) |_| {
        return self.arena_allocator;
    } else {
        self.arena = std.heap.ArenaAllocator.init(self._allocator);
        self.arena_allocator = self.arena.?.allocator();
        return self.arena_allocator;
    }
}

fn isZigString(comptime T: type) bool {
    return comptime blk: {
        // Only pointer types can be strings, no optionals
        const info = @typeInfo(T);
        if (info != .Pointer) break :blk false;

        const ptr = &info.Pointer;
        // Check for CV qualifiers that would prevent coerction to []const u8
        if (ptr.is_volatile or ptr.is_allowzero) break :blk false;

        // If it's already a slice, simple check.
        if (ptr.size == .Slice) {
            break :blk ptr.child == u8;
        }

        // Otherwise check if it's an array type that coerces to slice.
        if (ptr.size == .One) {
            const child = @typeInfo(ptr.child);
            if (child == .Array) {
                const arr = &child.Array;
                break :blk arr.child == u8;
            }
        }

        break :blk false;
    };
}
