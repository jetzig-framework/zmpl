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
            if (byte == '\\' and !self.escape) {
                self.escape = true;
                continue;
            }

            if (byte == '"') {
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
        if (std.mem.startsWith(u8, self.reference_buffer.items, ".")) {
            return try self.compileDataReference();
        } else {
            return try self.compileDeclReference();
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
        return std.mem.concat(self.allocator, u8, &[_][]const u8{
            \\var foo = try zmpl.formatDecl(
            ,
            self.reference_buffer.items,
            \\);
            \\try zmpl.write(foo);
            \\allocator.free(foo);
        });
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
    var ptr: []u8 = try self.allocator.dupe(u8, self.name);
    // TODO: Sanitize names - must be valid variable names.
    std.mem.replaceScalar(u8, ptr, '/', '_');
    std.mem.replaceScalar(u8, ptr, '.', '_');
    const extension = std.fs.path.extension(self.name);
    return ptr[0 .. self.name.len - extension.len];
}

pub fn compile(self: *Self) ![]const u8 {
    self.buffer.clearAndFree();
    try self.buffer.append(
        \\const std = @import("std");
        \\const __zmpl = @import("zmpl");
        \\const __Context = __zmpl.Context;
        \\pub fn render(zmpl: *__Context) anyerror!void {
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

    try self.buffer.append("}");

    return try std.mem.join(self.allocator, "\n", self.buffer.items);
}

fn compileMarkupLine(self: *Self, line: []const u8) ![]const u8 {
    var markup_line = MarkupLine.init(self.allocator, line);
    return markup_line.compile();
}

fn compileZigLine(self: *Self, line: []const u8) ![]const u8 {
    _ = self;
    // const line_z = try std.mem.concatWithSentinel(self.allocator, u8, &[_][]const u8{line}, 0);
    // const ast = try std.zig.Ast.parse(self.allocator, line_z, .zig);
    // for (ast.nodes.items(h) |node| {
    //     std.debug.print("node: {any}\n", .{node});
    // }
    // var tokenizer = std.zig.Tokenizer.init(line_z);
    // while (true) {
    //     const token = tokenizer.next();
    //     if (token.tag == .eof) break;
    //     if (token.tag == .identifier) {
    //         std.debug.print("identifier: {s}\n", .{line[token.loc.start..token.loc.end]});
    //     }
    // }
    return line;
}

fn escapeText(self: *Self, text: []const u8) ![]const u8 {
    _ = self;
    return text;
}
