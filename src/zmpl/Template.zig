const std = @import("std");

const root = @import("root");

const Self = @This();

allocator: std.mem.Allocator,
content: []const u8,
name: []const u8,
buffer: std.ArrayList([]const u8),

const MarkupLine = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    reference_buffer: std.ArrayList(u8),
    line: []const u8,
    open: bool = false,
    escape: bool = false,
    decl: bool = false,

    pub fn init(allocator: std.mem.Allocator, line: []const u8) MarkupLine {
        return .{
            .allocator = allocator,
            .line = line,
            .buffer = std.ArrayList(u8).init(allocator),
            .reference_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn compile(self: *MarkupLine) ![]const u8 {
        for (self.line) |byte| {
            if (byte == '\r') continue;

            if (byte == '\\' and !self.escape) {
                self.escape = true;
                continue;
            }

            if (byte == ':' and self.open and self.reference_buffer.items.len == 0) {
                self.decl = true;
                continue;
            }

            if (byte == '"' and !self.open) {
                try self.buffer.append('\\');
                try self.buffer.append('"');
                continue;
            }

            if (self.escape and !self.open) {
                try self.buffer.append(byte);
                self.escape = false;
                continue;
            }

            if (self.escape and self.open) {
                try self.reference_buffer.append(byte);
                self.escape = false;
                continue;
            }

            if (byte == '{') {
                self.openReference();
                continue;
            }

            if (byte == '}' and self.open) {
                try self.closeReference();
                continue;
            }

            if (self.open) {
                try self.reference_buffer.append(byte);
                continue;
            }

            try self.buffer.append(byte);
        }

        return std.mem.join(
            self.allocator,
            "",
            &[_][]const u8{
                "try zmpl.write(\"",
                self.buffer.items,
                "\\n\");",
            },
        );
    }

    fn openReference(self: *MarkupLine) void {
        self.reference_buffer.clearAndFree();
        self.open = true;
    }

    fn closeReference(self: *MarkupLine) !void {
        const buf: []const u8 = try std.mem.concat(
            self.allocator,
            u8,
            &[_][]const u8{
                \\");
                ,
                try self.compileReference(),
                \\try zmpl.write("
            },
        );
        try self.buffer.appendSlice(buf);
        self.open = false;
    }

    fn compileReference(self: *MarkupLine) ![]const u8 {
        if (self.decl) {
            return try self.compileDeclReference();
        } else if (std.mem.startsWith(u8, self.reference_buffer.items, ".")) {
            return try self.compileDataReference();
        } else if (std.mem.indexOfAny(u8, self.reference_buffer.items, " \"+-/*{}!?()")) |_| {
            return try self.compileZigLiteral(); // Some unexpected characters - assume Zig code evalutaing to a []const u8
        } else {
            return try self.compileValueReference();
        }
    }

    fn compileDataReference(self: *MarkupLine) ![]const u8 {
        return std.mem.concat(self.allocator, u8, &[_][]const u8{
            \\try zmpl.write(try zmpl.getValueString("
            ,
            self.reference_buffer.items[1..self.reference_buffer.items.len],
            \\"));
        });
    }

    fn compileDeclReference(self: *MarkupLine) ![]const u8 {
        var buf: [32]u8 = undefined;
        self.generateVariableName(&buf);
        self.decl = false;
        return std.mem.concat(self.allocator, u8, &[_][]const u8{
            \\const 
            ,
            &buf,
            \\ = try zmpl.formatDecl(
            ,
            self.reference_buffer.items,
            \\); try zmpl.write(
            ,
            &buf,
            \\); allocator.free(
            ,
            &buf,
            \\);
        });
    }

    fn compileValueReference(self: *MarkupLine) ![]const u8 {
        var buf: [32]u8 = undefined;
        self.generateVariableName(&buf);
        return std.mem.concat(self.allocator, u8, &[_][]const u8{
            \\var 
            ,
            &buf,
            \\ = 
            ,
            self.reference_buffer.items,
            \\;
            ,
            \\try zmpl.write(try 
            ,
            &buf,
            \\.toString());
        });
    }

    fn compileZigLiteral(self: *MarkupLine) ![]const u8 {
        return std.mem.concat(self.allocator, u8, &[_][]const u8{
            \\try zmpl.write(
            ,
            self.reference_buffer.items,
            \\); 
        });
    }

    fn generateVariableName(self: *MarkupLine, buf: *[32]u8) void {
        _ = self;
        const chars = "abcdefghijklmnopqrstuvwxyz";

        for (0..32) |index| {
            buf[index] = chars[std.crypto.random.intRangeAtMost(u8, 0, 25)];
        }
    }
};

pub fn init(allocator: std.mem.Allocator, name: []const u8, content: []const u8) Self {
    return .{
        .allocator = allocator,
        .name = name,
        .content = content,
        .buffer = std.ArrayList([]const u8).init(allocator),
    };
}

pub fn identifier(self: *Self) ![]const u8 {
    var sanitized_array = std.ArrayList(u8).init(self.allocator);
    for (self.name, 0..) |char, index| {
        if (std.mem.indexOfAny(u8, &[_]u8{char}, "abcdefghijklmnopqrstuvwxyz")) |_| {
            try sanitized_array.append(char);
        } else if (index == 0) {
            try sanitized_array.append('_');
        } else if (index < self.name.len - 1 and sanitized_array.items[sanitized_array.items.len - 1] != '_') {
            try sanitized_array.append('_');
        }
    }

    const extension = std.fs.path.extension(self.name);
    return sanitized_array.items[0 .. sanitized_array.items.len - extension.len];
}

pub fn compile(self: *Self) ![]const u8 {
    self.buffer.clearAndFree();
    try self.buffer.append(
        \\const std = @import("std");
        \\const __zmpl = @import("zmpl");
        \\pub fn render(zmpl: *__zmpl.Data) anyerror![]const u8 {
        \\  const allocator = zmpl.getAllocator();
        \\  _ = try allocator.alloc(u8, 0); // no-op to avoid unused local constant
    );

    var it = std.mem.split(u8, self.content, "\n");

    while (it.next()) |line| {
        const index = std.mem.indexOfNone(u8, line, " ");

        if (index) |i| {
            if (line[i] == '<') {
                try self.buffer.append(try self.compileMarkupLine(line));
            } else {
                try self.buffer.append(try self.compileZigLine(line));
            }
        } else {
            try self.buffer.append("\n");
        }
    }

    try self.buffer.append("return zmpl._allocator.dupe(u8, zmpl.output_buf.items);");
    try self.buffer.append("}");

    return try std.mem.join(self.allocator, "\n", self.buffer.items);
}

fn compileMarkupLine(self: *Self, line: []const u8) ![]const u8 {
    var markup_line = MarkupLine.init(self.allocator, line);
    return markup_line.compile();
}

fn compileZigLine(self: *Self, line: []const u8) ![]const u8 {
    _ = self;
    return line;
}

fn escapeText(self: *Self, text: []const u8) ![]const u8 {
    _ = self;
    return text;
}
