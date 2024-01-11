const std = @import("std");

pub const Writer = std.ArrayList(u8).Writer;

const Self = @This();

_allocator: std.mem.Allocator,
arena: ?std.heap.ArenaAllocator = null,
arena_allocator: std.mem.Allocator = undefined,
writer_array: std.ArrayList(u8),
nested_value: Value = undefined,
value: ?Value = null,
Null: Value = .{ .Null = NullType{} },

pub fn init(allocator: std.mem.Allocator) Self {
    const writer_array = std.ArrayList(u8).init(allocator);

    return .{
        ._allocator = allocator,
        .writer_array = writer_array,
    };
}

pub fn deinit(self: *Self) void {
    if (self.arena) |arena| arena.deinit();
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

pub fn getValueString(self: *Self, key: []const u8) !?[]const u8 {
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

pub fn object(self: *Self) !*Value {
    const obj = Object.init(self.getAllocator());
    if (self.value) |_| {
        const ptr = try self.getAllocator().create(Value);
        ptr.* = Value{ .object = obj };
        return ptr;
    } else {
        self.value = Value{ .object = obj };
        return &self.value.?;
    }
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

pub fn toJson(self: *Self) ![]const u8 {
    const writer = self.writer_array.writer();
    try self.value.?.toJson(writer);
    return self.writer_array.items[0..self.writer_array.items.len];
}

pub const Value = union(enum) {
    object: Object,
    array: Array,
    float: Float,
    integer: Integer,
    boolean: Boolean,
    string: String,
    Null: NullType,

    pub fn add(self: *Value, key: []const u8, value: Value) !void {
        switch (self.*) {
            .object => |*capture| try capture.add(key, value),
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
            else => unreachable, // TODO: return error
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

    pub fn add(self: *Object, key: []const u8, value: Value) !void {
        try self.hashmap.put(key, value);
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

fn getAllocator(self: *Self) std.mem.Allocator {
    if (self.arena) |_| {
        return self.arena_allocator;
    } else {
        self.arena = std.heap.ArenaAllocator.init(self._allocator);
        self.arena_allocator = self.arena.?.allocator();
        return self.arena_allocator;
    }
}
