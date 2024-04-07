const std = @import("std");

const util = @import("util.zig");

const Self = @This();

allocator: std.mem.Allocator,
content: []const u8,
name: []const u8,
templates_path: []const u8,
path: []const u8,
buffer: std.ArrayList([]const u8),
args: ?[]const u8 = null, // v2 compat.
partial: bool = false, // v2 compat.

const MarkupLine = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    reference_buffer: std.ArrayList(u8),
    line: []const u8,
    open: bool = false,
    decl: bool = false,
    partial: bool = false,

    pub fn init(allocator: std.mem.Allocator, line: []const u8) MarkupLine {
        return .{
            .allocator = allocator,
            .line = line,
            .buffer = std.ArrayList(u8).init(allocator),
            .reference_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    // TODO: For now we somehow get away with a stackless parser by relying on lookahead but this
    // is limiting and fragile. Build a proper syntax grammar and AST.
    pub fn compile(self: *MarkupLine) ![]const u8 {
        var position: isize = -1;

        for (self.line) |_| {
            const index: usize = @intCast(position + 1);
            if (index >= self.line.len) break;
            position += 1;

            const byte = self.line[index];

            if (byte == '\r' or byte == '\n') continue;

            if (byte == ':' and self.open and self.reference_buffer.items.len == 0) {
                self.decl = true;
                continue;
            }

            if (byte == '^' and self.open and self.reference_buffer.items.len == 0) {
                self.partial = true;
                continue;
            }

            if (byte == '"' and !self.open) {
                try self.buffer.append('\\');
                try self.buffer.append('"');
                continue;
            }

            if (byte == '{' and lookAhead(self.line[index..], "{{")) {
                position += 1;
                try self.buffer.append('{');
                continue;
            }

            if (byte == '}' and lookAhead(self.line[index..], "}}")) {
                position += 1;
                try self.buffer.append('}');
                continue;
            }

            if (byte == '{') {
                self.openReference();
                continue;
            }

            if (byte == '}') {
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
                \\
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
        } else if (self.partial) {
            return try self.compilePartial();
        } else if (std.mem.startsWith(u8, self.reference_buffer.items, ".")) {
            return try self.compileDataReference();
        } else if (std.mem.indexOfAny(u8, self.reference_buffer.items, " \"+-/*{}!?()")) |_| {
            return try self.compileZigLiteral(); // Some unexpected characters - assume Zig code evalutaing to a []const u8
        } else {
            return try self.compileValueReference();
        }
    }

    // Convert `foo/bar/baz` into `_foo_bar_baz` to match template name.
    fn compilePartial(self: *MarkupLine) ![]const u8 {
        self.partial = false;
        if (self.reference_buffer.items.len == 0) return error.ZmplPartialNameError;

        const args = try self.compilePartialArgs();
        defer args.deinit();
        defer for (args.items) |arg| {
            self.allocator.free(arg.name);
            self.allocator.free(arg.value);
        };

        const first_arg_token = std.mem.indexOfScalar(u8, self.reference_buffer.items, '(');
        const partial_path = if (first_arg_token) |index|
            self.reference_buffer.items[0..index]
        else
            self.reference_buffer.items;

        const partial_basename = std.fs.path.basenamePosix(partial_path);
        const partial_dirname = std.fs.path.dirnamePosix(partial_path);
        const partial_name = try std.mem.concat(
            self.allocator,
            u8,
            &[_][]const u8{
                if (partial_dirname) |dirname| dirname else "",
                if (partial_dirname) |_| "/" else "",
                "_",
                partial_basename,
            },
        );
        defer self.allocator.free(partial_name);

        var args_buf = std.ArrayList(u8).init(self.allocator);
        defer args_buf.deinit();
        const args_writer = args_buf.writer();

        for (args.items) |arg| {
            const value = try arg.toZmpl();
            defer self.allocator.free(value);
            const output = try std.fmt.allocPrint(
                self.allocator,
                \\    try partial_data.put("{s}", {s});
                \\
            ,
                .{ arg.name, value },
            );
            defer self.allocator.free(output);
            try args_writer.writeAll(output);
        }
        const template =
            \\{{
            \\    var partial_data = try zmpl.createObject();
            \\    defer partial_data.deinit();
            \\{s}
            \\    try zmpl.renderPartial("{s}", &partial_data.object, &.{{}});
            \\}}
        ;
        return try std.fmt.allocPrint(self.allocator, template, .{ args_buf.items, strip(partial_name) });
    }

    const Arg = struct {
        name: []const u8,
        value: []const u8,
        allocator: std.mem.Allocator,

        /// Attempt to infer the type unless explicitly defined, e.g.:
        /// `zmpl.string("..."))`
        pub fn toZmpl(self: Arg) ![]const u8 {
            if (std.mem.startsWith(u8, self.value, "zmpl.")) return try self.allocator.dupe(u8, self.value);
            if (self.isString()) return try self.zmplValue(.string);
            if (self.isInteger()) return try self.zmplValue(.integer);
            if (self.isFloat()) return try self.zmplValue(.float);
            if (self.isBoolean()) return try self.zmplValue(.boolean);
            if (self.isNull()) return try self.zmplValue(.Null);
            // Currently we only support scalars as partial args - array/object not supported.
            std.debug.print("Unable to parse argument: {s}: {s}\n", .{ self.name, self.value });
            return error.ZmplPartialArgumentError;
        }

        // Convert an inferred value argument to a Zmpl data type.
        fn zmplValue(self: Arg, zmpl_type: enum { string, integer, float, boolean, Null }) ![]const u8 {
            if (zmpl_type == .Null) return try self.allocator.dupe(u8, "zmpl._null()");

            return try std.mem.concat(
                self.allocator,
                u8,
                &[_][]const u8{ "zmpl.", @tagName(zmpl_type), "(", self.value, ")" },
            );
        }

        // Identify a string argument.
        fn isString(self: Arg) bool {
            if (!std.mem.startsWith(u8, self.value, "\"")) return false;
            if (!std.mem.endsWith(u8, self.value, "\"")) return false;
            return true;
        }

        // Identify an integer number argument.
        fn isInteger(self: Arg) bool {
            for (self.value) |char| if (!std.ascii.isDigit(char)) return false;
            return true;
        }

        // Identify a floating point number argument.
        fn isFloat(self: Arg) bool {
            if (std.mem.count(u8, self.value, ".") != 1) return false;
            for (self.value) |char| if (!std.ascii.isDigit(char) and char != '.') return false;
            return true;
        }

        // Identify a boolean argument.
        fn isBoolean(self: Arg) bool {
            return std.mem.eql(u8, self.value, "true") or std.mem.eql(u8, self.value, "false");
        }

        // Identify a `null` argument.
        fn isNull(self: Arg) bool {
            return std.mem.eql(u8, self.value, "null");
        }
    };

    fn compilePartialArgs(self: *MarkupLine) !std.ArrayList(Arg) {
        var args = std.ArrayList(Arg).init(self.allocator);

        // The entire markup line is escaped further up the stack, so we unescape here to
        // simplify parsing.
        const reference = try std.mem.replaceOwned(
            u8,
            self.allocator,
            self.reference_buffer.items,
            "\\\\",
            "\\",
        );
        defer self.allocator.free(reference);

        const first_token = std.mem.indexOfScalar(u8, reference, '(');
        const last_token = std.mem.lastIndexOfScalar(u8, reference, ')');
        if (first_token == null or last_token == null) return args;
        if (first_token.? + 1 >= last_token.?) return args;

        var chunks = std.ArrayList([]const u8).init(self.allocator);
        defer chunks.deinit();
        defer for (chunks.items) |chunk| self.allocator.free(chunk);

        var chunk_buf = std.ArrayList(u8).init(self.allocator);
        defer chunk_buf.deinit();

        var quote_open = false;
        var escape = false;

        for (reference[first_token.? + 1 .. last_token.?]) |char| {
            if (char == '\\' and !escape) {
                escape = true;
            } else if (escape) {
                try chunk_buf.append('\\');
                try chunk_buf.append(char);
                escape = false;
            } else if (char == '"' and !quote_open) {
                quote_open = true;
                try chunk_buf.append(char);
            } else if (char == '"' and quote_open) {
                quote_open = false;
                try chunk_buf.append(char);
            } else if (char == ',' and !quote_open) {
                try chunks.append(try self.allocator.dupe(u8, strip(chunk_buf.items)));
                chunk_buf.clearAndFree();
            } else {
                try chunk_buf.append(char);
            }
        }

        if (strip(chunk_buf.items).len > 0) {
            try chunks.append(try self.allocator.dupe(u8, strip(chunk_buf.items)));
        }

        for (chunks.items) |chunk| {
            var name: []const u8 = undefined;
            var value: []const u8 = undefined;

            const keypair_sep = ": ";
            if (std.mem.indexOf(u8, chunk, keypair_sep)) |token_lhs| {
                name = strip(chunk[0..token_lhs]);
                if (chunk.len > token_lhs + keypair_sep.len + 1) {
                    value = strip(chunk[token_lhs + keypair_sep.len ..]);
                } else {
                    debugPartialArgumentError(chunk);
                    return error.ZmplPartialArgumentError;
                }
            } else {
                debugPartialArgumentError(chunk);
                return error.ZmplPartialArgumentError;
            }

            try args.append(.{
                .allocator = self.allocator,
                .name = try self.allocator.dupe(u8, name),
                .value = try self.allocator.dupe(u8, value),
            });
        }

        return args;
    }

    fn compileDataReference(self: *MarkupLine) ![]const u8 {
        return std.mem.concat(self.allocator, u8, &[_][]const u8{
            \\try zmpl.write(try zmpl.getValueString("
            ,
            self.reference_buffer.items[1..self.reference_buffer.items.len],
            \\"));
            \\
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

pub fn init(
    allocator: std.mem.Allocator,
    name: []const u8,
    templates_path: []const u8,
    path: []const u8,
    content: []const u8,
    template_map: std.StringHashMap([]const u8),
) Self {
    _ = template_map; // v2 compat.
    return .{
        .allocator = allocator,
        .path = path,
        .name = name,
        .templates_path = templates_path,
        .content = util.normalizeInput(allocator, content),
        .buffer = std.ArrayList([]const u8).init(allocator),
    };
}

pub fn identifier(self: *Self) ![]const u8 {
    const path = try std.fs.path.relative(self.allocator, self.templates_path, self.path);
    defer self.allocator.free(path);

    var segments = std.ArrayList([]const u8).init(self.allocator);
    defer segments.deinit();

    var it = std.mem.splitScalar(u8, path, std.fs.path.sep);
    while (it.next()) |segment| {
        try segments.append(segment);
    }
    const basename = segments.pop();
    defer self.allocator.free(basename);

    var partial = false;

    if (basename.len > 0 and std.mem.startsWith(u8, basename, "_")) {
        partial = true;
        try segments.append(basename[1..]);
    } else {
        try segments.append(basename);
    }

    const name = try std.mem.join(self.allocator, "_", segments.items);
    defer self.allocator.free(name);

    var valid_name_array = std.ArrayList(u8).init(self.allocator);
    defer valid_name_array.deinit();

    const valid_anywhere = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_";
    const valid_after_zero = valid_anywhere ++ "0123456789";
    const substitutable = ".";

    const extension = std.fs.path.extension(self.path);
    const base_path = name[0 .. name.len - extension.len];

    for (base_path, 0..) |char, index| {
        if (index == 0 and partial) try valid_name_array.append('_');
        if (index == 0 and std.mem.containsAtLeast(u8, valid_anywhere, 1, &[_]u8{char})) {
            try valid_name_array.append(char);
        } else if (index > 0 and std.mem.containsAtLeast(u8, valid_after_zero, 1, &[_]u8{char})) {
            try valid_name_array.append(char);
        } else if (std.mem.containsAtLeast(u8, substitutable, 1, &[_]u8{char})) {
            try valid_name_array.append('_');
        } else {
            std.debug.print("[zmpl] Invalid filename (must be '[a-zA-Z0-9_]+.zmpl'): {s}\n", .{self.path});
            return error.ZmplInvalidFileNameError;
        }
    }

    return try self.allocator.dupe(u8, valid_name_array.items);
}

pub fn compile(self: *Self, comptime options: type) ![]const u8 {
    self.buffer.clearAndFree();

    var decls_buf = std.ArrayList(u8).init(self.allocator);
    defer decls_buf.deinit();

    if (@hasDecl(options, "template_constants")) {
        inline for (std.meta.fields(options.template_constants)) |field| {
            const type_str = switch (field.type) {
                []const u8, i64, f64, bool => @typeName(field.type),
                else => @compileError("Unsupported template constant type: " ++ @typeName(field.type)),
            };

            const decl_string = "const " ++ field.name ++ ": " ++ type_str ++ " = try zmpl.getConst(" ++ type_str ++ ", \"" ++ field.name ++ "\");\n"; // :(

            try decls_buf.appendSlice("    " ++ decl_string);
            try decls_buf.appendSlice("    zmpl.noop(" ++ type_str ++ ", " ++ field.name ++ ");\n");
        }
    }

    const header = try std.fmt.allocPrint(
        self.allocator,
        \\pub fn {s}_render(zmpl: *__zmpl.Data) anyerror![]const u8 {{
        \\{s}
        \\    const allocator = zmpl.getAllocator();
        \\    zmpl.noop(std.mem.Allocator, allocator);
    ,
        .{ self.name, decls_buf.items },
    );
    defer self.allocator.free(header);
    try self.buffer.append(header);

    var line_buf = std.ArrayList([]const u8).init(self.allocator);
    defer line_buf.deinit();

    var char_buf = std.ArrayList(u8).init(self.allocator);
    defer char_buf.deinit();

    var tag_open = false;
    var quote_open = false;
    var is_zig_line = false;
    var is_raw = false;
    var index: usize = 0;

    const raw_tag_open = "<#>";
    const raw_tag_close = "</#>";
    const fragment_tag_open = "<>";
    const fragment_tag_close = "</>";

    while (index < self.content.len) : (index += 1) {
        const char = self.content[index];

        if (is_raw and !lookAhead(self.content[index..], raw_tag_close)) {
            try char_buf.append(char);
            continue;
        }

        if (char_buf.items.len == 0) {
            if (firstToken(self.content[index..])) |token| {
                switch (token) {
                    .markup => is_zig_line = false,
                    .zig => is_zig_line = if (tag_open or quote_open) false else true,
                }
            }
        }

        if (is_zig_line and char != '\n') {
            try char_buf.append(char);
            continue;
        }

        if (is_zig_line and char == '\n') {
            try line_buf.append(try self.compileZigLine(char_buf.items));
            char_buf.clearAndFree();
            is_zig_line = false;
            continue;
        }

        if (char == '<' and !tag_open and !quote_open) {
            if (lookAhead(self.content[index..], raw_tag_open)) {
                is_raw = true;

                // When line includes *only* the raw tag `<#>` (with optional leading
                // whitespace), skip that line in output:
                //
                // ```
                // <#>
                // some raw text
                // </#>
                // ```
                //
                // becomes:
                // ```
                // some raw text
                // ```
                //
                // and not:
                // ```
                //
                // some raw text
                //
                // ```

                if (isWhitespace(char_buf.items)) char_buf.clearAndFree();

                if (char_buf.items.len == 0) {
                    if (lookAhead(self.content[index..], raw_tag_open ++ "\n")) {
                        index += (raw_tag_open ++ "\n").len - 1;
                    }
                } else {
                    index += raw_tag_open.len - 1;
                }

                continue;
            }

            if (is_raw and lookAhead(self.content[index..], raw_tag_close)) {
                is_raw = false;

                if (lookAhead(self.content[index..], raw_tag_close ++ "\n")) {
                    index += (raw_tag_close ++ "\n").len - 1;
                    clearDanglingWhitespace(&char_buf);
                } else {
                    index += raw_tag_close.len - 1;
                }
                try line_buf.append(try self.compileRaw(char_buf.items, true));
                char_buf.clearAndFree();
                continue;
            }

            if (lookAhead(self.content[index..], fragment_tag_open)) {
                index = index + fragment_tag_open.len - 1;
                continue;
            }

            if (lookAhead(self.content[index..], fragment_tag_close)) {
                index = index + fragment_tag_close.len - 1;
                continue;
            }

            tag_open = true;
            try char_buf.append(char);
            continue;
        }

        if (char == '>' and tag_open and !quote_open) {
            tag_open = false;
            try char_buf.append(char);
            continue;
        }

        if (char == '"' and !quote_open) {
            quote_open = true;
            try char_buf.append(char);
            continue;
        }

        if (char == '"' and quote_open) {
            quote_open = false;
            try char_buf.append(char);
            continue;
        }

        if (!tag_open and !quote_open and char == '\n') {
            try line_buf.append(try self.compileMarkupLine(char_buf.items));
            try line_buf.append("\n");
            char_buf.clearAndFree();
            continue;
        }

        for (escapeChar(char)) |escaped_char| try char_buf.append(escaped_char);
    }

    if (char_buf.items.len > 0) {
        std.debug.print(
            \\Char buffer has unparsed content.
            \\This is a parser bug, please report to https://github.com/jetzig-framework/zmpl/issues
            \\
            \\Content:
            \\{s}
            \\
            \\Buffer:
            \\{s}
        ,
            .{ self.content, char_buf.items },
        );
    }

    for (line_buf.items) |line| try self.buffer.append(line);

    try self.buffer.append(
        \\if (zmpl.partial) zmpl.chompOutputBuffer();
        \\return zmpl._allocator.dupe(u8, if (zmpl.partial) "" else zmpl.output_buf.items);
    );
    try self.buffer.append("}");

    try self.buffer.append(try std.fmt.allocPrint(
        self.allocator,
        \\
        \\fn {0s}_renderWithLayout(
        \\    layout: __Manifest.Template,
        \\    zmpl: *__zmpl.Data,
        \\) anyerror![]const u8 {{
        \\    const inner_content = try {0s}_render(zmpl);
        \\    defer zmpl._allocator.free(inner_content);
        \\    zmpl.output_buf.clearAndFree();
        \\    zmpl.content = .{{ .data = __zmpl.chomp(inner_content) }};
        \\    const content = try layout.render(zmpl);
        \\    zmpl.output_buf.clearAndFree();
        \\    return content;
        \\}}
        \\
    ,
        .{self.name},
    ));

    return try std.mem.join(self.allocator, "\n", self.buffer.items);
}

fn firstToken(string: []const u8) ?enum { markup, zig } {
    for (string) |char| {
        if (char == '\n') return null;
        if (char == '\t' or char == ' ') continue;
        return if (char == '<') .markup else .zig;
    }
    return null;
}

// TODO: Multi-line fragments - curently just assumes there might be a `</>` on the same line and
// removes it if present.
fn parseFragment(string: []const u8) ?[]const u8 {
    const tag = "<>";
    if (std.mem.startsWith(u8, string, tag)) {
        const close_index = std.mem.lastIndexOf(u8, string, "</>") orelse string.len - 1;
        return string[tag.len..close_index];
    }
    return null;
}

fn isMultilineFragmentOpen(line: []const u8) bool {
    const tag = "<#>";
    if (std.mem.indexOf(u8, line, tag)) |index| {
        if (chompString(line[index + 1 ..]).len > tag.len) {
            @panic("Found unexpected characters after multi-line raw text open tag <#>");
        } else {
            return true;
        }
    } else {
        return false;
    }
}

fn isMultilineFragmentClose(line: []const u8) bool {
    const tag = "</#>";
    if (std.mem.indexOf(u8, line, tag)) |index| {
        if (chompString(line[index + 1 ..]).len > tag.len) {
            @panic("Found unexpected characters after multi-line raw text close tag. </#>");
        } else {
            return true;
        }
    } else {
        return false;
    }
}

fn lookAhead(haystack: []const u8, needle: []const u8) bool {
    if (haystack.len < needle.len) return false;
    return std.mem.eql(u8, haystack[0..needle.len], needle);
}

fn compileMarkupLine(self: *Self, line: []const u8) ![]const u8 {
    var markup_line = MarkupLine.init(self.allocator, line);
    return markup_line.compile();
}

fn compileRaw(self: *Self, string: []const u8, chomp: bool) ![]const u8 {
    const chomped = if (chomp) chompString(string) else string;
    const escaped_backslash = try std.mem.replaceOwned(
        u8,
        self.allocator,
        chomped,
        "\"",
        "\\\"",
    );
    defer self.allocator.free(escaped_backslash);

    const escaped_linebreak = try std.mem.replaceOwned(
        u8,
        self.allocator,
        escaped_backslash,
        "\n",
        "\\n",
    );
    defer self.allocator.free(escaped_linebreak);

    const compiled = escaped_linebreak;

    return std.mem.join(
        self.allocator,
        "",
        &[_][]const u8{
            "try zmpl.write(\"",
            compiled,
            "\\n\");",
        },
    );
}

fn compileZigLine(self: *Self, line: []const u8) ![]const u8 {
    return try self.allocator.dupe(u8, line);
}

fn escapeText(self: *Self, text: []const u8) ![]const u8 {
    _ = self;
    return text;
}

fn escapeChar(char: u8) []const u8 {
    if (char == '\r') return "\\r";
    if (char == '\n') return "\\n";
    if (char == '"') return "\"";
    if (char == '\\') return "\\\\";

    return &[_]u8{char};
}

fn chompString(string: []const u8) []const u8 {
    if (std.mem.endsWith(u8, string, "\n")) {
        return string[0 .. string.len - 2];
    } else return string;
}

fn isWhitespace(string: []const u8) bool {
    for (string) |char| {
        if (char == ' ' or char == '\t') continue;
        return false;
    }
    return true;
}

fn clearDanglingWhitespace(buf: *std.ArrayList(u8)) void {
    var index: ?usize = null;

    if (std.mem.lastIndexOf(u8, buf.items, "\n")) |linebreak_index| index = linebreak_index;

    if (index) |capture| {
        for (buf.items[capture..buf.items.len]) |char| {
            if (char == '\t' or char == ' ' or char == '\r' or char == '\n') continue;
            return;
        }

        for (capture..buf.items.len) |_| _ = buf.pop();
    }
}

fn strip(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, &std.ascii.whitespace);
}

fn debugPartialArgumentError(input: []const u8) void {
    std.debug.print("Error parsing partial arguments in: `{s}`\n", .{input});
}
