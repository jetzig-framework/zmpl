/// Generic, JSON-compatible data type that can store a tree of values. The root value must be
/// `Object` or `Array`, which can contain any of:
/// `Object`, `Array`, 'NullType`, `String`, `Float`, `Integer`, `Boolean`.
///
/// Initialize a new `Data` instance and initialize its root object with the first call to
/// `array()` or `object()`.
///
/// Insert new values into the root object with either `append(value)` or `put(value)` depending
/// on the root value type. All inserted values must be of type `Data.Value`. Use the provided
/// member functions `object()`, `array()`, `string()`, `float()`, `integer()`, `boolean()` to
/// generate these values.
///
/// ```
/// var data = Data.init(allocator);
/// var root = try data.object(); // First call to `object()` or `array()` sets root value type.
/// try root.put("foo", data.string("a string"));
/// try root.put("bar", data.float(123.45));
/// try root.put("baz", data.integer(123));
/// try root.put("qux", data.boolean(true));
///
/// var object = data.object(); // Second call creates a new object without modifying root value.
/// var array = data.array(); // Since `data.object()` was called above, also creates a new array.
///
/// try object.put("nested_object", object);
/// try object.put("nested_array", array);
///
/// try array.append(data.string("value"));
/// try object.put("key", data.string("value"));
/// ```
///
/// `data.toJson()` returns a `[]const u8` with the full value tree converted to a JSON string.
/// `data.value` is a `Data.Value` generic which can be used with `switch` to walk through the
/// data tree (for Zmpl templates, use the `{.nested_object.key}` syntax to do this
/// automatically.
const std = @import("std");
const manifest = @import("zmpl.manifest");

/// Output stream for writing values into a rendered template.
pub const Writer = std.ArrayList(u8).Writer;

const Self = @This();

pub const RenderFn = *const fn (*Self) anyerror![]const u8;

pub const LayoutContent = struct {
    data: []const u8,

    pub fn toString(self: *const LayoutContent) ![]const u8 {
        return self.data;
    }
};

_allocator: std.mem.Allocator,
arena: ?std.heap.ArenaAllocator = null,
arena_allocator: std.mem.Allocator = undefined,
json_buf: std.ArrayList(u8),
output_buf: std.ArrayList(u8),
output_writer: ?std.ArrayList(u8).Writer = null,
value: ?*Value = null,
Null: Value = .{ .Null = NullType{} },
partial: bool = false,
content: LayoutContent = .{ .data = "" },
partial_data: ?*Object = null,

/// Creates a new `Data` instance which can then be used to store any tree of `Value`.
pub fn init(allocator: std.mem.Allocator) Self {
    const json_buf = std.ArrayList(u8).init(allocator);
    const output_buf = std.ArrayList(u8).init(allocator);

    return .{
        ._allocator = allocator,
        .json_buf = json_buf,
        .output_buf = output_buf,
    };
}

/// Frees all resources used by this `Data` instance.
pub fn deinit(self: *Self) void {
    if (self.arena) |arena| arena.deinit();
    self.output_buf.deinit();
    self.json_buf.deinit();
}

/// Render a partial template. Do not invoke directly, use `{^partial_name}` syntax instead.
pub fn renderPartial(self: *Self, name: []const u8, partial_data: *Object) !void {
    if (manifest.find(name)) |template| {
        self.partial = true;
        self.partial_data = partial_data;
        defer self.partial = false;
        defer self.partial_data = null;
        // Partials return an empty string as they share the same writer as parent template.
        _ = try template.render(self);
    } else {
        return error.ZmplPartialNotFound;
    }
}

/// Chomps output buffer. Used for partials to allow user to add an explicit blank line at the
/// end of a template if needed, otherwise `<div>{^partial_name}</div>` should not output a
/// newline.
pub fn chompOutputBuffer(self: *Self) void {
    if (std.mem.endsWith(u8, self.output_buf.items, "\r\n")) {
        _ = self.output_buf.pop();
        _ = self.output_buf.pop();
    } else if (std.mem.endsWith(u8, self.output_buf.items, "\n")) {
        _ = self.output_buf.pop();
    }
}

pub fn eql(self: *const Self, other: *const Self) bool {
    if (self.value != null and other.value != null) {
        return self.value.?.eql(other.value.?);
    } else if (self.value == null and other.value == null) {
        return true;
    } else return false;
}

/// Takes a string such as `.foo.bar.baz` and translates into a path into the data tree to return
/// a value that can be rendered in a template.
pub fn getValue(self: Self, key: []const u8) !?*Value {
    // Partial data always takes precedence over underlying template data.
    if (self.partial_data) |val| {
        if (val.get(key)) |partial_value| return partial_value;
    }

    if (self.value) |val| {
        var tokens = std.mem.splitSequence(u8, key, ".");
        var current_value = val;

        while (tokens.next()) |token| {
            switch (current_value.*) {
                .object => |*capture| {
                    var capt = capture.*;
                    current_value = capt.get(token) orelse return null;
                },
                .array => |*capture| {
                    var capt = capture.*;
                    const index = std.fmt.parseInt(usize, token, 10) catch |err| {
                        switch (err) {
                            error.InvalidCharacter => return null,
                            else => return err,
                        }
                    };
                    current_value = capt.get(index) orelse return null;
                },
                else => |*capture| {
                    return capture;
                },
            }
        }
        return current_value;
    } else return null;
}

/// Converts any `Value` in a root `Object` to a string. Returns an empty string if no match or
/// no compatible data type.
pub fn getValueString(self: Self, key: []const u8) ![]const u8 {
    if (try self.getValue(key)) |val| {
        switch (val.*) {
            .object, .array => return "", // No sense in trying to convert an object/array to a string
            else => |*capture| {
                var v = capture.*;
                return try v.toString();
            },
        }
    } else return "";
}

/// Resets the current `Data` object, allowing it to be re-initialized with a new root value.
pub fn reset(self: *Self) void {
    if (self.value) |*ptr| {
        ptr.*.deinit();
    }
    self.value = null;
}

/// Creates a new `Object`. The first call to `array()` or `object()` sets the root value.
/// Subsequent calls create a new `Object` without setting the root value. e.g.:
///
/// var data = Data.init(allocator);
/// var object = try data.object(); // <-- the root value is now an object.
/// try nested_object = try data.object(); // <-- creates a new, detached object.
/// try object.put("nested", nested_object); // <-- adds a nested object to the root object.
pub fn object(self: *Self) !*Value {
    if (self.value) |_| {
        return try self.createObject();
    } else {
        self.value = try self.createObject();
        return self.value.?;
    }
}

pub fn createObject(self: *Self) !*Value {
    const obj = Object.init(self.getAllocator());
    const ptr = try self.getAllocator().create(Value);
    ptr.* = Value{ .object = obj };
    return ptr;
}

/// Creates a new `Array`. The first call to `array()` or `object()` sets the root value.
/// Subsequent calls create a new `Array` without setting the root value. e.g.:
///
/// var data = Data.init(allocator);
/// var array = try data.array(); // <-- the root value is now an array.
/// try nested_array = try data.array(); // <-- creates a new, detached array.
/// try array.append(nested_array); // <-- adds a nested array to the root array.
pub fn array(self: *Self) !*Value {
    if (self.value) |_| {
        return try self.createArray();
    } else {
        self.value = try self.createArray();
        return self.value.?;
    }
}

/// Creates a new `Array`. For most use cases, use `array()` instead.
pub fn createArray(self: *Self) !*Value {
    const arr = Array.init(self.getAllocator());
    const ptr = try self.getAllocator().create(Value);
    ptr.* = Value{ .array = arr };
    return ptr;
}

/// Creates a new `Value` representing a string (e.g. `"foobar"`).
pub fn string(self: *Self, value: []const u8) *Value {
    const allocator = self.getAllocator();
    const duped = allocator.dupe(u8, value) catch @panic("Out of memory");
    const val = allocator.create(Value) catch @panic("Out of memory");
    val.* = .{ .string = .{ .value = duped, .allocator = self.getAllocator() } };
    return val;
}

/// Creates a new `Value` representing an integer (e.g. `1234`).
pub fn integer(self: *Self, value: i64) *Value {
    const allocator = self.getAllocator();
    const val = allocator.create(Value) catch @panic("Out of memory");
    val.* = .{ .integer = .{ .value = value, .allocator = self.getAllocator() } };
    return val;
}

/// Creates a new `Value` representing a float (e.g. `1.234`).
pub fn float(self: *Self, value: f64) *Value {
    const allocator = self.getAllocator();
    const val = allocator.create(Value) catch @panic("Out of memory");
    val.* = .{ .float = .{ .value = value, .allocator = self.getAllocator() } };
    return val;
}

/// Creates a new `Value` representing a boolean (true/false).
pub fn boolean(self: *Self, value: bool) *Value {
    const allocator = self.getAllocator();
    const val = allocator.create(Value) catch @panic("Out of memory");
    val.* = .{ .boolean = .{ .value = value, .allocator = self.getAllocator() } };
    return val;
}

/// Creates a new `Value` representing a `null` value. Public, but for internal use only.
pub fn _null(self: *Self) *Value {
    const allocator = self.getAllocator();
    const val = allocator.create(Value) catch @panic("Out of memory");
    val.* = .{ .Null = NullType{} };
    return val;
}

/// Writes a given string to the output buffer. Creates a new output buffer if not already
/// present. Used by compiled Zmpl templates.
pub fn write(self: *Self, slice: []const u8) !void {
    if (self.output_writer) |writer| {
        try writer.writeAll(slice);
    } else {
        self.output_writer = self.output_buf.writer();
        try (self.output_writer.?).writeAll(slice);
    }
}

/// Gets a value from the data tree, returns a `NullType` value (not `null`) if not found.
pub fn get(self: *Self, key: []const u8) !*Value {
    return (try self.getValue(key)) orelse self._null(); // XXX: Raise an error here ?
}

/// Formats a comptime value as a string, e.g.:
/// ```
/// const foo = "abc";
/// data.formatDecl(foo); // --> "foo"
///
/// const bar = 123;
/// data.formatDecl(bar); // --> "123"
/// ```
///
/// Used for rendering comptime values defined within a template.
pub fn formatDecl(self: *Self, comptime decl: anytype) ![]const u8 {
    if (comptime isZigString(@TypeOf(decl))) {
        return try std.fmt.allocPrint(self.getAllocator(), "{s}", .{decl});
    } else {
        return try std.fmt.allocPrint(self.getAllocator(), "{}", .{decl});
    }
}

/// Returns the entire `Data` tree as a JSON string.
pub fn toJson(self: *Self) ![]const u8 {
    if (self.value) |_| {} else return "";

    const writer = self.json_buf.writer();
    self.json_buf.clearAndFree();
    try self.value.?.toJson(writer);
    return self.getAllocator().dupe(u8, self.json_buf.items[0..self.json_buf.items.len]);
}

/// Parses a JSON string and updates the current `Data` object with the parsed data. Inverse of
/// `toJson`.
pub fn fromJson(self: *Self, json: []const u8) !void {
    const parsed = try std.json.parseFromSlice(std.json.Value, self.getAllocator(), json, .{});
    self.value = try self.parseJsonValue(parsed.value);
}

fn parseJsonValue(self: *Self, value: std.json.Value) !*Value {
    return switch (value) {
        .object => |*val| blk: {
            var it = val.iterator();
            const obj = try self.createObject();
            while (it.next()) |item| {
                try obj.put(item.key_ptr.*, try self.parseJsonValue(item.value_ptr.*));
            }
            break :blk obj;
        },
        .array => |*val| blk: {
            var arr = try self.array();
            for (val.items) |item| try arr.append(try self.parseJsonValue(item));
            break :blk arr;
        },
        .string => |val| self.string(val),
        .number_string => |val| self.string(val), // TODO: Special-case this somehow?
        .integer => |val| self.integer(val),
        .float => |val| self.float(val),
        .bool => |val| self.boolean(val),
        .null => self._null(),
    };
}

/// A generic type representing any supported type. All types are JSON-compatible and can be
/// serialized and deserialized losslessly.
pub const Value = union(enum) {
    object: Object,
    array: Array,
    float: Float,
    integer: Integer,
    boolean: Boolean,
    string: String,
    Null: NullType,

    /// Compares one `Value` to another `Value` recursively. Order of `Object` keys is ignored.
    pub fn eql(self: *const Value, other: *const Value) bool {
        switch (self.*) {
            .object => |*capture| switch (other.*) {
                .object => |*other_capture| return capture.eql(other_capture),
                inline else => return false,
            },
            .array => |*capture| switch (other.*) {
                .array => |*other_capture| return capture.eql(other_capture),
                inline else => return false,
            },
            .string => |*capture| switch (other.*) {
                .string => |*other_capture| return capture.eql(other_capture),
                inline else => return false,
            },
            .integer => |*capture| switch (other.*) {
                .integer => |*other_capture| return capture.eql(other_capture),
                inline else => return false,
            },
            .float => |*capture| switch (other.*) {
                .float => |*other_capture| return capture.eql(other_capture),
                inline else => return false,
            },
            .boolean => |*capture| switch (other.*) {
                .boolean => |*other_capture| return capture.eql(other_capture),
                inline else => return false,
            },
            .Null => |*capture| switch (other.*) {
                .Null => |*other_capture| return capture.eql(other_capture),
                inline else => return false,
            },
        }
    }

    /// Gets a `Value` from an `Object`.
    pub fn get(self: *Value, key: []const u8) ?*Value {
        switch (self.*) {
            .object => |*capture| return capture.get(key),
            inline else => unreachable,
        }
    }

    /// Puts a `Value` into an `Object`.
    pub fn put(self: *Value, key: []const u8, value: *Value) !void {
        switch (self.*) {
            .object => |*capture| try capture.put(key, value),
            inline else => unreachable,
        }
    }

    /// Appends a `Value` to an `Array`.
    pub fn append(self: *Value, value: *Value) !void {
        switch (self.*) {
            .array => |*capture| try capture.append(value),
            inline else => unreachable,
        }
    }

    /// Generates a JSON string representing the complete data tree.
    pub fn toJson(self: *Value, writer: Writer) !void {
        return switch (self.*) {
            inline else => |*capture| try capture.toJson(writer),
        };
    }

    /// Converts a primitive type (string, integer, float) to a string representation.
    pub fn toString(self: *Value) ![]const u8 {
        return switch (self.*) {
            .object, .array => unreachable,
            inline else => |*capture| try capture.toString(),
        };
    }

    /// Return the number of items in an array or an object.
    pub fn count(self: *Value) usize {
        switch (self.*) {
            .array => |capture| return capture.count(),
            .object => |capture| return capture.count(),
            else => unreachable,
        }
    }

    pub fn iterator(self: *Value) *Iterator {
        switch (self.*) {
            .array => |*capture| return capture.*.iterator(),
            .object => unreachable, // TODO
            else => unreachable,
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
    pub fn toJson(self: NullType, writer: Writer) !void {
        _ = self;
        try writer.writeAll("null");
    }

    pub fn eql(self: *const NullType, other: *const NullType) bool {
        _ = other;
        _ = self;
        return true;
    }

    pub fn toString(self: NullType) ![]const u8 {
        _ = self;
        return "";
    }
};

pub const Float = struct {
    value: f64,
    allocator: std.mem.Allocator,

    pub fn eql(self: *const Float, other: *const Float) bool {
        return self.value == other.value;
    }

    pub fn toJson(self: Float, writer: Writer) !void {
        try writer.print("{}", .{self.value});
    }

    pub fn toString(self: Float) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{d}", .{self.value});
    }
};

pub const Integer = struct {
    value: i64,
    allocator: std.mem.Allocator,

    pub fn eql(self: *const Integer, other: *const Integer) bool {
        return self.value == other.value;
    }

    pub fn toJson(self: Integer, writer: Writer) !void {
        try writer.print("{}", .{self.value});
    }

    pub fn toString(self: Integer) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{}", .{self.value});
    }
};

pub const Boolean = struct {
    value: bool,
    allocator: std.mem.Allocator,

    pub fn eql(self: *const Boolean, other: *const Boolean) bool {
        return self.value == other.value;
    }

    pub fn toJson(self: Boolean, writer: Writer) !void {
        try writer.writeAll(if (self.value) "true" else "false");
    }

    pub fn toString(self: Boolean) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{}", .{self.value});
    }
};

pub const String = struct {
    value: []const u8,
    allocator: std.mem.Allocator,

    pub fn eql(self: *const String, other: *const String) bool {
        return std.mem.eql(u8, self.value, other.value);
    }

    pub fn toJson(self: String, writer: Writer) !void {
        try std.json.encodeJsonString(self.value, .{}, writer);
    }

    pub fn toString(self: String) ![]const u8 {
        return self.value;
    }
};

pub const Object = struct {
    hashmap: std.StringHashMap(*Value),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Object {
        return .{ .hashmap = std.StringHashMap(*Value).init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *Object) void {
        var it = self.hashmap.iterator();
        while (it.next()) |entry| {
            self.allocator.destroy(entry.key_ptr);
            self.allocator.destroy(entry.value_ptr);
        }
        self.hashmap.clearAndFree();
    }

    /// Recursively compares equality of keypairs with another `Object`.
    pub fn eql(self: *const Object, other: *const Object) bool {
        if (self.count() != other.count()) return false;
        var it = self.hashmap.iterator();
        while (it.next()) |item| {
            const other_value = other.get(item.key_ptr.*);
            if (other_value) |capture| {
                if (!item.value_ptr.*.eql(capture)) return false;
            }
        }

        return true;
    }

    pub fn put(self: *Object, key: []const u8, value: *Value) !void {
        const key_dupe = try self.allocator.dupe(u8, key);
        switch (value.*) {
            .object, .array => try self.hashmap.put(key_dupe, value),
            inline else => {
                try self.hashmap.put(key_dupe, value);
            },
        }
    }

    pub fn get(self: Object, key: []const u8) ?*Value {
        if (self.hashmap.getEntry(key)) |entry| {
            return entry.value_ptr.*;
        } else return null;
    }

    pub fn contains(self: Object, key: []const u8) bool {
        return self.hashmap.contains(key);
    }

    pub fn count(self: Object) u32 {
        return self.hashmap.count();
    }

    pub fn toJson(self: *Object, writer: Writer) anyerror!void {
        try writer.writeAll("{");
        var it = self.hashmap.keyIterator();
        var index: i64 = 0;
        const size = self.hashmap.count();
        while (it.next()) |key| {
            try std.json.encodeJsonString(key.*, .{}, writer);
            try writer.writeAll(":");
            var value = self.hashmap.get(key.*).?;
            try value.toJson(writer);
            index += 1;
            if (index < size) try writer.writeAll(",");
        }
        try writer.writeAll("}");
    }
};

pub const Array = struct {
    allocator: std.mem.Allocator,
    array: std.ArrayList(*Value),
    it: Iterator = undefined,

    pub fn init(allocator: std.mem.Allocator) Array {
        return .{ .array = std.ArrayList(*Value).init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *Array) void {
        self.array.clearAndFree();
    }

    // Compares equality of all items in an array. Order must be identical.
    pub fn eql(self: *const Array, other: *const Array) bool {
        if (self.count() != other.count()) return false;
        for (self.array.items, other.array.items) |lhs, rhs| {
            if (!lhs.eql(rhs)) return false;
        }
        return true;
    }

    pub fn get(self: *const Array, index: usize) ?*Value {
        return if (self.array.items.len > index) self.array.items[index] else null;
    }

    pub fn append(self: *Array, value: *Value) !void {
        try self.array.append(value);
    }

    pub fn toJson(self: *Array, writer: Writer) anyerror!void {
        try writer.writeAll("[");
        for (self.array.items, 0..) |*item, index| {
            try item.*.toJson(writer);
            if (index < self.array.items.len - 1) try writer.writeAll(",");
        }
        try writer.writeAll("]");
    }

    pub fn count(self: Array) usize {
        return self.array.items.len;
    }

    pub fn iterator(self: *Array) *Iterator {
        self.it = .{ .array = self.array };
        return &self.it;
    }
};

pub const Iterator = struct {
    array: std.ArrayList(*Value),
    index: usize = 0,

    pub fn next(self: *Iterator) ?*Value {
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
