const std = @import("std");

pub const Writer = std.ArrayList(u8).Writer;

const Self = @This();

// arena: std.heap.ArenaAllocator,
allocator: std.mem.Allocator = undefined,
writer_array: std.ArrayList(u8),
nested_value: Value = undefined,
value: ?Value = null,
Null: Value = .{ .Null = NullType{} },

pub fn init(allocator: std.mem.Allocator) Self {
    const writer_array = std.ArrayList(u8).init(allocator);

    return .{
        .allocator = allocator,
        .writer_array = writer_array,
    };
}

pub fn getValueString(self: *Self, key: []const u8) !?[]const u8 {
    if (self.value) |val| {
        switch (val) {
            .object => |*capture| {
                var capt = capture.*;
                var v = capt.get(key) orelse return null;
                return try v.toString();
            },
            else => return "",
        }
    } else return "";
}

pub fn object(self: *Self) !*Value {
    const obj = Object.init(self.allocator);
    if (self.value) |_| {
        const ptr = try self.allocator.create(Value);
        ptr.* = Value{ .object = obj };
        return ptr;
    } else {
        self.value = Value{ .object = obj };
        return &self.value.?;
    }
}

pub fn array(self: *Self) *Value {
    var arr = Array.init(self.allocator);

    if (self.value) |_| {
        return &arr;
    } else {
        self.value = Value{ .array = arr };
        switch (self.value.?) {
            .array => |*capture| return capture,
            else => unreachable,
        }
    }
}

pub fn string(self: *Self, value: []const u8) Value {
    return .{ .string = .{ .value = value, .allocator = self.allocator } };
}

pub fn integer(self: *Self, value: i64) Value {
    return .{ .integer = .{ .value = value, .allocator = self.allocator } };
}

pub fn float(self: *Self, value: f64) Value {
    return .{ .float = .{ .value = value, .allocator = self.allocator } };
}

pub fn boolean(self: *Self, value: bool) Value {
    return .{ .boolean = .{ .value = value, .allocator = self.allocator } };
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

    pub fn append(self: *Value, key: []const u8, value: Value) !void {
        switch (self.*) {
            .array => |*capture| try capture.append(key, value),
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

    pub fn init(allocator: std.mem.Allocator) Array {
        return .{ .array = std.ArrayList(Value).init(allocator), .allocator = allocator };
    }

    pub fn toJson(self: *Array, writer: Writer) anyerror!void {
        try writer.writeAll("[");
        for (self.array.items, 0..) |*item, index| {
            try item.toJson(writer);
            if (index < self.array.items.len - 1) try writer.writeAll(",");
        }
        try writer.writeAll("]");
    }
};
