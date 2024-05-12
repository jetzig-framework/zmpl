const std = @import("std");

const Zmd = @import("zmd").Zmd;
const ZmdNode = @import("zmd").Node;

const Token = @import("Template.zig").Token;
const util = @import("util.zig");

token: Token,
children: std.ArrayList(*Node),
generated_template_name: []const u8,
allocator: std.mem.Allocator,
template_map: std.StringHashMap([]const u8),
templates_path: []const u8,

const Node = @This();

const WriterOptions = struct { zmpl_write: []const u8 = "zmpl.write" };

pub fn compile(self: Node, input: []const u8, writer: anytype, options: type) !void {
    if (self.token.mode == .partial and self.children.items.len > 0) {
        std.debug.print(
            "Partial slots cannot contain mode blocks:\n{s}\n",
            .{input[self.token.start - self.token.mode_line.len .. self.token.end]},
        );
        return error.ZmplSyntaxError;
    }

    // Write chunks for current token between child token boundaries, rendering child token
    // immediately after.
    var start: usize = self.token.startOfContent();
    for (self.children.items) |child_node| {
        if (start < child_node.token.start) {
            const content = input[start .. child_node.token.start - 1];
            const rendered_content = try self.render(content, options);
            try writer.writeAll(rendered_content);
        }

        start = child_node.token.end + 1;
        try child_node.compile(input, writer, options);
    }

    if (self.children.items.len == 0) {
        const content = input[self.token.startOfContent()..self.token.endOfContent()];
        const rendered_content = try self.render(content, options);
        try writer.writeAll(rendered_content);
    } else {
        const last_child = self.children.items[self.children.items.len - 1];
        if (last_child.token.end + 1 < self.token.endOfContent()) {
            const content = input[last_child.token.end + 1 .. self.token.endOfContent()];
            const rendered_content = try self.render(content, options);
            try writer.writeAll(rendered_content);
        }
    }
}

fn render(self: Node, content: []const u8, options: type) ![]const u8 {
    const markdown_fragments = if (@hasDecl(options, "markdown_fragments"))
        options.markdown_fragments
    else
        struct {
            pub const root = .{ "<div>", "</div>" };
        };

    return switch (self.token.mode) {
        .zig => try self.renderZig(content),
        .html => try self.renderHtml(content, .{}),
        .markdown => try self.renderHtml(try self.renderMarkdown(content, markdown_fragments), .{}),
        .partial => try self.renderPartial(content),
        .args => try self.renderArgs(),
    };
}

fn renderZig(self: Node, content: []const u8) ![]const u8 {
    var html_it = self.htmlIterator(content);
    var buf = std.ArrayList(u8).init(self.allocator);
    defer buf.deinit();

    while (html_it.next()) |line| {
        const mode = getHtmlLineMode(line);
        switch (mode) {
            .html => try buf.appendSlice(try self.renderHtml(line, .{})),
            .zig => {
                try buf.appendSlice(line);
                try buf.append('\n');
            },
        }
    }

    return try buf.toOwnedSlice();
}

const HtmlIterator = struct {
    allocator: std.mem.Allocator,
    content: []const u8,
    index: usize = 0,

    pub fn init(allocator: std.mem.Allocator, content: []const u8) HtmlIterator {
        return .{ .allocator = allocator, .content = content };
    }

    pub fn next(self: *HtmlIterator) ?[]const u8 {
        if (self.content.len == 0 or self.index >= self.content.len - 1) return null;

        const start = self.index;

        if (util.firstMeaningfulChar(self.content[start..])) |char| {
            // If an HTML tag is opened, treat all content up to the line with a the relevant
            // closing `>` (including the rest of the line) as a single line to allow breaking
            // tag definitions across multiple lines.
            // Note that the terminology is confusing here - "tag end" is the end of the opening
            // tag. We don't care about the close tag of a pair of HTML tags.
            if (char == '<') {
                const end = self.findTagEnd();
                self.index = end + 1;
                return self.content[start..end];
            }
        }

        if (std.mem.indexOfScalar(u8, self.content[start..], '\n')) |index| {
            self.index = start + index + 1;
            return self.content[start .. start + index];
        } else {
            self.index = self.content.len;
            return self.content[start..];
        }
        return null;
    }

    fn findTagEnd(self: HtmlIterator) usize {
        var stack: isize = 0;
        var escape = false;
        var quote = false;

        for (self.content[self.index..], self.index..) |char, cursor| {
            if (char == '\\') {
                escape = true;
                continue;
            }
            if (escape) {
                escape = false;
                continue;
            }
            if (char == '"') {
                quote = true;
                continue;
            }
            if (quote and char == '"') {
                quote = false;
                continue;
            }
            if (char == Syntax.tag_open[0]) {
                stack += 1;
                continue;
            }
            if (char == Syntax.tag_close[0]) {
                stack -= 1;
                if (stack == 0) {
                    if (std.mem.indexOfScalar(u8, self.content[cursor..], '\n')) |line_end| {
                        return cursor + line_end;
                    } else {
                        return self.content.len;
                    }
                }
            }
        }

        return self.content.len;
    }
};

fn htmlIterator(self: Node, content: []const u8) HtmlIterator {
    return HtmlIterator.init(self.allocator, content);
}
fn getHtmlLineMode(line: []const u8) enum { html, zig } {
    return if (util.startsWithIgnoringWhitespace(line, Syntax.tag_open))
        .html
    else if (util.startsWithIgnoringWhitespace(line, Syntax.ref_open))
        .html
    else
        .zig;
}

fn renderMarkdown(self: Node, content: []const u8, fragments: type) ![]const u8 {
    var zmd = Zmd.init(self.allocator);
    defer zmd.deinit();

    try zmd.parse(content);
    return try zmd.toHtml(fragments);
}

const Syntax = struct {
    pub const ref_open = "{{";
    pub const ref_close = "}}";
    pub const tag_open = "<";
    pub const tag_close = ">";
};

fn renderHtml(self: *const Node, content: []const u8, writer_options: WriterOptions) ![]const u8 {
    var index: usize = 0;

    var buf = std.ArrayList(u8).init(self.allocator);
    var ref_buf = std.ArrayList(u8).init(self.allocator);
    var html_buf = std.ArrayList(u8).init(self.allocator);
    var ref_open = false;
    var escaped = false;

    while (index < content.len) : (index += 1) {
        const char = content[index];

        if (std.mem.startsWith(u8, content[index..], Syntax.ref_open)) {
            try buf.appendSlice(try self.renderWrite(html_buf.items, writer_options));
            html_buf.clearAndFree();
            index += Syntax.ref_open.len - 1;
            ref_open = true;
        } else if (ref_open and std.mem.startsWith(u8, content[index..], Syntax.ref_close)) {
            index += Syntax.ref_close.len - 1;
            ref_open = false;
            try buf.appendSlice(try self.renderRef(ref_buf.items, writer_options));
            ref_buf.clearAndFree();
        } else if (ref_open) {
            try ref_buf.append(char);
        } else if (char == '\\' and !escaped) {
            escaped = true;
        } else {
            escaped = false;
            try html_buf.append(char);
        }
    }

    if (html_buf.items.len > 0) {
        if (std.mem.eql(u8, writer_options.zmpl_write, "zmpl.write")) {
            try html_buf.append('\n');
        }
        try buf.appendSlice(try self.renderWrite(
            html_buf.items,
            writer_options,
        ));
    }

    return try buf.toOwnedSlice();
}

fn renderPartial(self: Node, content: []const u8) ![]const u8 {
    if (self.token.args == null) {
        std.debug.print(
            "Expected `@partial` with name, no name was given [{}->{}]: '{s}'\n",
            .{
                self.token.start,
                self.token.end,
                std.mem.trim(u8, self.token.mode_line, &std.ascii.whitespace),
            },
        );
        return error.ZmplSyntaxError;
    }

    const args = self.token.args.?;
    const partial_name_end = std.mem.indexOfAny(u8, args, "({ ") orelse args.len;
    const partial_name = std.mem.trim(u8, args[0..partial_name_end], &std.ascii.whitespace);
    const partial_args = try self.parsePartialArgs(args[partial_name_end..]);

    var some_keyword = false;
    var some_positional = false;

    for (partial_args) |arg| {
        if (arg.name == null) some_positional = true else some_keyword = true;
    }

    if (some_positional and some_keyword) {
        std.debug.print(
            "Partial args must be either all keyword or all positional, found: {s}\n",
            .{args},
        );
        return error.ZmplSyntaxError;
    }

    const expected_partial_args = try self.getPartialArgsSignature(partial_name);

    var reordered_args = std.ArrayList(Arg).init(self.allocator);
    defer reordered_args.deinit();

    outer: for (expected_partial_args, 0..) |expected_arg, expected_arg_index| {
        for (partial_args, 0..) |actual_arg, actual_arg_index| {
            if (actual_arg.name == null) {
                if (actual_arg_index == expected_arg_index) {
                    try reordered_args.append(actual_arg);
                    continue :outer;
                } else continue;
            }
            if (expected_arg.name == null) {
                std.debug.print("Error parsing @args pragma for partial `{s}`", .{partial_name});
                return error.ZmplSyntaxError;
            }
            if (std.mem.eql(u8, actual_arg.name.?, expected_arg.name.?)) {
                try reordered_args.append(actual_arg);
            }
        }
    }

    for (expected_partial_args, 0..) |expected_arg, index| {
        if (index > reordered_args.items.len - 1) {
            if (expected_arg.default) |default| try reordered_args.append(
                .{ .name = expected_arg.name, .value = default },
            );
        }
    }

    if (reordered_args.items.len != expected_partial_args.len) {
        std.debug.print("Expected args for partial `{s}`: ", .{partial_name});
        for (expected_partial_args, 0..) |arg, index| std.debug.print(
            "{s}{s}",
            .{ arg.name.?, if (index + 1 < expected_partial_args.len) ", " else "\n" },
        );
        std.debug.print("Found: ", .{});
        for (partial_args, 0..) |arg, index| std.debug.print(
            "{s}{s}",
            .{ arg.name orelse "[]", if (index + 1 < partial_args.len) ", " else "\n" },
        );
        return error.ZmplSyntaxError;
    }

    const generated_partial_name = self.template_map.get(
        try util.templatePathFetch(self.allocator, partial_name, true),
    );

    if (generated_partial_name == null) {
        std.debug.print("Partial not found: {s}\n", .{partial_name});
        return error.ZmplSyntaxError;
    }

    const slots = try self.renderSlots(content);

    var args_buf = std.ArrayList([]const u8).init(self.allocator);
    defer args_buf.deinit();

    for (reordered_args.items) |arg| {
        if (std.mem.startsWith(u8, arg.value, ".")) {
            // Pass a *Zmpl.Value to partial using regular data lookup syntax.
            const value = try std.fmt.allocPrint(
                self.allocator,
                \\(try zmpl._get("{s}"))
            ,
                .{arg.value[1..]},
            );
            try args_buf.append(value);
        } else {
            try args_buf.append(arg.value);
        }
    }

    const template =
        \\{{
        \\{0s}
        \\        const __slots = [_][]const u8{{
        \\{1s}
        \\        }};
        \\        var __partial_data = __zmpl.Data.init(allocator);
        \\        __partial_data.template_decls = zmpl.template_decls;
        \\        defer __partial_data.deinit();
        \\
        \\    const __partial_output = try {2s}_renderPartial(&__partial_data, &__slots, {3s});
        \\    defer allocator.free(__partial_output);
        \\    try zmpl.write(__partial_output);
        \\}}
        \\
    ;
    return try std.fmt.allocPrint(self.allocator, template, .{
        slots.content_generators,
        slots.items,
        generated_partial_name.?,
        try std.mem.join(self.allocator, ", ", args_buf.items),
    });
}

const Slots = struct {
    content_generators: []const u8,
    items: []const u8,
};

fn renderSlots(self: Node, content: []const u8) !Slots {
    var slots_buf = std.ArrayList(u8).init(self.allocator);
    defer slots_buf.deinit();

    var slots_content_buf = std.ArrayList(u8).init(self.allocator);
    defer slots_content_buf.deinit();

    var slots_it = std.mem.splitScalar(u8, content, '\n');
    while (slots_it.next()) |slot| {
        if (util.strip(slot).len == 0) continue;

        const slot_name = try util.generateVariableNameAlloc(self.allocator);
        const slot_write = try std.fmt.allocPrint(self.allocator,
            \\{s}_writer.write
        , .{slot_name});

        try slots_content_buf.appendSlice(
            try std.fmt.allocPrint(self.allocator,
                \\var {0s}_buf = std.ArrayList(u8).init(allocator);
                \\const {0s}_writer = {0s}_buf.writer();
                \\{1s}
                \\
            , .{
                slot_name,
                try self.renderHtml(util.strip(slot), .{ .zmpl_write = slot_write }),
            }),
        );

        try slots_buf.appendSlice(try std.fmt.allocPrint(
            self.allocator,
            \\    {s}_buf.items,
            \\
        ,
            .{slot_name},
        ));
    }

    return Slots{
        .content_generators = try slots_content_buf.toOwnedSlice(),
        .items = try slots_buf.toOwnedSlice(),
    };
}

fn renderArgs(self: Node) ![]const u8 {
    const fields = self.token.mode_line["@args".len..];
    return std.fmt.allocPrint(
        self.allocator,
        \\const __args_type = struct {{ {s} }};
        \\zmpl.noop(type, __args_type);
        \\
    ,
        .{fields},
    );
}

// Represents a name/value keypair OR a name/type keypair.
const Arg = struct {
    name: ?[]const u8,
    value: []const u8,
    default: ?[]const u8 = null,
};

fn parsePartialArgsSignature(self: Node, input: []const u8) ![]Arg {
    // var args = std.ArrayList(Arg).init(self.allocator);
    const args = try self.parsePartialArgs(input);
    for (args) |arg| {
        std.debug.print("arg: {any}\n", .{arg});
    }
    return args;
}

pub fn parsePartialArgs(self: Node, input: []const u8) ![]Arg {
    var args = std.ArrayList(Arg).init(self.allocator);

    const first_token = std.mem.indexOfScalar(u8, input, '(');
    const last_token = std.mem.lastIndexOfScalar(u8, input, ')');
    if (first_token == null or last_token == null) return try args.toOwnedSlice();
    if (first_token.? + 1 >= last_token.?) return try args.toOwnedSlice();

    var chunks = std.ArrayList([]const u8).init(self.allocator);
    defer chunks.deinit();
    defer for (chunks.items) |chunk| self.allocator.free(chunk);

    var chunk_buf = std.ArrayList(u8).init(self.allocator);
    defer chunk_buf.deinit();

    var quote_open = false;
    var escape = false;

    for (input[first_token.? + 1 .. last_token.?]) |char| {
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
            try chunks.append(try self.allocator.dupe(u8, util.strip(chunk_buf.items)));
            chunk_buf.clearAndFree();
        } else {
            try chunk_buf.append(char);
        }
    }

    if (util.strip(chunk_buf.items).len > 0) {
        try chunks.append(try self.allocator.dupe(u8, util.strip(chunk_buf.items)));
    }

    for (chunks.items) |chunk| {
        var name: ?[]const u8 = null;
        var value: []const u8 = undefined;
        var default: ?[]const u8 = null;

        const keypair_sep = ": ";
        if (std.mem.indexOf(u8, chunk, keypair_sep)) |token_lhs| { // Keyword arg
            name = util.strip(chunk[0..token_lhs]);
            if (chunk.len > token_lhs + keypair_sep.len) {
                value = util.strip(chunk[token_lhs + keypair_sep.len ..]);
                if (std.mem.indexOfScalar(u8, value, '=')) |index| {
                    if (index + 1 > value.len - 1) {
                        std.debug.print("Error parsing default value: `{s}`\n", .{chunk});
                        return error.ZmplSyntaxError;
                    }
                    default = value[index + 1 ..];
                    value = value[0..index];
                }
            } else {
                debugPartialArgumentError(chunk);
                return error.ZmplPartialArgumentError;
            }
        } else { // Positional arg
            name = null;
            value = util.strip(chunk);
        }

        try args.append(.{
            .name = if (name) |capture| try self.allocator.dupe(u8, capture) else null,
            .value = try self.allocator.dupe(u8, value),
            .default = if (default) |capture| try self.allocator.dupe(u8, capture) else null,
        });
    }

    return try args.toOwnedSlice();
}

fn renderWrite(self: Node, input: []const u8, writer_options: WriterOptions) ![]const u8 {
    var buf = std.ArrayList(u8).init(self.allocator);
    defer buf.deinit();
    const writer = buf.writer();
    try std.zig.stringEscape(input, "", .{}, writer);

    return std.fmt.allocPrint(
        self.allocator,
        \\_ = try {s}(zmpl.chomp("{s}"));
        \\
    ,
        .{ writer_options.zmpl_write, buf.items },
    );
}

fn renderRef(self: Node, input: []const u8, writer_options: WriterOptions) ![]const u8 {
    if (std.mem.startsWith(u8, input, ".")) {
        return try self.renderDataRef(input[1..], writer_options);
    } else if (std.mem.indexOfAny(u8, input, " \"+-/*{}!?()")) |_| {
        return try self.renderZigLiteral(input, writer_options);
    } else {
        return try self.renderValueRef(input, writer_options);
    }
}

fn renderDataRef(self: Node, input: []const u8, writer_options: WriterOptions) ![]const u8 {
    return std.fmt.allocPrint(
        self.allocator,
        \\_ = try {s}(try zmpl.getValueString("{s}"));
        \\
    ,
        .{ writer_options.zmpl_write, input },
    );
}

fn renderValueRef(self: Node, input: []const u8, writer_options: WriterOptions) ![]const u8 {
    var buf: [32]u8 = undefined;
    util.generateVariableName(&buf);
    return std.fmt.allocPrint(
        self.allocator,
        \\const {0s} = {1s};
        \\_ = try {2s}(try zmpl.coerceString({0s}));
        \\
    ,
        .{ &buf, input, writer_options.zmpl_write },
    );
}

fn renderZigLiteral(self: Node, input: []const u8, writer_options: WriterOptions) ![]const u8 {
    return std.fmt.allocPrint(
        self.allocator,
        \\_ = try {s}({s});
        \\
    ,
        .{ writer_options.zmpl_write, input },
    );
}

// Parse a target partial's `@args` pragma in order to re-order keyword args if needed.
// We need to read direct from the file here because we can't guarantee that the target partial
// has been parsed yet.
fn getPartialArgsSignature(self: Node, partial_name: []const u8) ![]Arg {
    const fetch_name = try util.templatePathFetch(self.allocator, partial_name, true);
    std.mem.replaceScalar(u8, fetch_name, '/', std.fs.path.sep);
    const with_extension = try std.mem.concat(self.allocator, u8, &[_][]const u8{ fetch_name, ".zmpl" });
    defer self.allocator.free(with_extension);
    const path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.templates_path, with_extension });
    defer self.allocator.free(path);
    const content = try util.readFile(self.allocator, std.fs.cwd(), path);
    defer self.allocator.free(content);
    var it = std.mem.splitScalar(u8, content, '\n');

    var args: ?[]Arg = null;

    while (it.next()) |line| {
        if (util.startsWithIgnoringWhitespace(line, "@args")) {
            const normalized = try std.mem.concat(
                self.allocator,
                u8,
                &[_][]const u8{ "(", util.trimParentheses(util.strip(line)["@args".len..]), ")" },
            );
            defer self.allocator.free(normalized);
            args = try self.parsePartialArgs(normalized);
        }
    }

    if (args) |capture| {
        return capture;
    } else {
        return &.{};
    }
}

fn debugPartialArgumentError(input: []const u8) void {
    std.debug.print("Error parsing partial arguments in: `{s}`\n", .{input});
}
