const std = @import("std");
const builtin = @import("builtin");

const Zmd = @import("zmd").Zmd;
const ZmdNode = @import("zmd").Node;

const Token = @import("Template.zig").Token;
const util = @import("util.zig");
const IfStatement = @import("IfStatement.zig");

token: Token,
children: std.ArrayList(*Node),
generated_template_name: []const u8,
allocator: std.mem.Allocator,
template_map: std.StringHashMap([]const u8),
templates_path: []const u8,

const else_token = "@else";

const Node = @This();

const WriterOptions = struct { zmpl_writer: []const u8 = "zmpl" };

/// Debugging writer - writes debug tokens after every print/write instruction. This requires
/// that all print/write operations are line-based, otherwise the injected Zig comment will
/// clobber any dangling output.
/// In non-debug builds, debug tokens are omitted as a stack trace is required for them to be
/// useful.
pub const Writer = struct {
    buf: *std.ArrayList(u8),
    token: Token,

    pub fn print(self: Writer, comptime input: []const u8, args: anytype) !void {
        if (builtin.mode == .Debug) {
            try self.buf.writer().print(input, args);
            try self.writeDebug();
        } else {
            try self.buf.writer().print(input, args);
        }
    }

    pub fn writeAll(self: Writer, input: []const u8) !void {
        if (builtin.mode == .Debug) {
            var it = std.mem.tokenizeScalar(u8, input, '\n');
            while (it.next()) |line| {
                try self.buf.writer().writeAll(line);
                try self.writeDebug();
            }
        } else try self.buf.writer().writeAll(input);
    }

    pub fn writeByte(self: Writer, byte: u8) !void {
        try self.buf.writer().writeByte(byte);
    }

    fn writeDebug(self: Writer) !void {
        try self.buf.writer().print(
            \\
            \\//zmpl:debug:{}:{}:{s}
            \\
        , .{
            self.token.start,
            self.token.end,
            self.token.path,
        });
    }
};

pub fn compile(self: Node, input: []const u8, writer: *Writer, options: type) !void {
    writer.token = self.token;

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
            try self.render(.initial, content, options, writer);
        }

        start = child_node.token.end + 1;
        try child_node.compile(input, writer, options);
    }

    if (self.children.items.len == 0) {
        const content = input[self.token.startOfContent()..self.token.endOfContent()];
        try self.render(.initial, content, options, writer);
    } else {
        const last_child = self.children.items[self.children.items.len - 1];
        if (last_child.token.end + 1 < self.token.endOfContent()) {
            const content = input[last_child.token.end + 1 .. self.token.endOfContent()];
            if (false and self.token.mode == .@"if") {
                try self.renderElse(content, writer);
            } else {
                try self.render(.secondary, content, options, writer);
            }
        }
    }
    try self.renderClose(writer);
}

const Context = enum { initial, secondary };
fn render(
    self: Node,
    context: Context,
    content: []const u8,
    options: type,
    writer: anytype,
) !void {
    const markdown_fragments = if (@hasDecl(options, "markdown_fragments"))
        options.markdown_fragments
    else
        struct {
            pub const root = .{ "<div>", "</div>" };
        };

    const stripped_content = try self.stripComments(content);
    switch (self.token.mode) {
        .zig => try self.renderZig(stripped_content, writer),
        .html => try self.renderHtml(stripped_content, .{}, writer),
        .markdown => try self.renderHtml(
            try self.renderMarkdown(stripped_content, markdown_fragments),
            .{},
            writer,
        ),
        .partial => try self.renderPartial(stripped_content, writer),
        .args => try self.renderArgs(writer),
        .extend => try self.renderExtend(writer),
        .@"for" => try self.renderFor(context, stripped_content, writer),
        .@"if" => try self.renderIf(context, stripped_content, writer),
    }
}

fn stripComments(self: Node, content: []const u8) ![]const u8 {
    const comment_token = "@//";

    var buf = std.ArrayList(u8).init(self.allocator);
    var it = util.tokenizeRetainToken(content, "\n");
    while (it.next()) |line| {
        if (util.startsWithIgnoringWhitespace(line, comment_token)) continue;
        try buf.appendSlice(line);
    }
    return try buf.toOwnedSlice();
}

fn renderClose(self: Node, writer: anytype) !void {
    switch (self.token.mode) {
        .@"for", .@"if" => try writer.writeAll("\n}\n"),
        .zig, .html, .markdown, .partial, .args, .extend => {},
    }
}

fn renderZig(self: Node, content: []const u8, writer: anytype) !void {
    var html_it = self.htmlIterator(content);

    while (html_it.next()) |line| {
        const mode = getHtmlLineMode(line);
        switch (mode) {
            .html => try self.renderHtml(line, .{}, writer),
            .zig => try writer.print("{s}\n", .{line}),
        }
    }
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

fn renderHtml(
    self: *const Node,
    content: []const u8,
    writer_options: WriterOptions,
    writer: anytype,
) !void {
    var index: usize = 0;

    var ref_buf = std.ArrayList(u8).init(self.allocator);
    var html_buf = std.ArrayList(u8).init(self.allocator);
    var ref_open = false;
    var escaped = false;

    while (index < content.len) : (index += 1) {
        const char = content[index];

        if (std.mem.startsWith(u8, content[index..], Syntax.ref_open)) {
            try self.renderWrite(html_buf.items, writer_options, writer);
            html_buf.clearAndFree();
            index += Syntax.ref_open.len - 1;
            ref_open = true;
        } else if (ref_open and std.mem.startsWith(u8, content[index..], Syntax.ref_close)) {
            index += Syntax.ref_close.len - 1;
            ref_open = false;
            try self.renderRef(ref_buf.items, writer_options, writer);
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
        if (std.mem.eql(u8, writer_options.zmpl_writer, "zmpl.*.output_writer")) {
            try html_buf.append('\n');
        }
        try self.renderWrite(html_buf.items, writer_options, writer);
    }
}

fn renderPartial(self: Node, content: []const u8, writer: anytype) !void {
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
        if (index + 1 > reordered_args.items.len) {
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

    const slots = try self.generateSlots(content);

    var args_buf = std.ArrayList([]const u8).init(self.allocator);
    defer args_buf.deinit();

    for (reordered_args.items, expected_partial_args, 0..) |arg, expected_arg, index| {
        if (std.mem.startsWith(u8, arg.value, ".") or std.mem.startsWith(u8, arg.value, "$.")) {
            // Pass a *Zmpl.Value to partial using regular data lookup syntax.
            const value = try std.fmt.allocPrint(
                self.allocator,
                \\(try zmpl.getCoerce({s}, "{s}"))
            ,
                .{ expected_arg.value, arg.value[1..] },
            );
            try args_buf.append(value);
        } else {
            var it = std.mem.tokenizeScalar(u8, arg.value, '.');
            const maybe_root = it.next();
            if (maybe_root) |root| {
                if (isIdentifier(root) and it.rest().len > 0) {
                    const chain = try std.fmt.allocPrint(
                        self.allocator,
                        \\if (comptime __zmpl.isZmplValue(@TypeOf({0s})))
                        \\    try {0s}.chainRefT(std.meta.fields(std.meta.ArgsTuple(@TypeOf({2s}_renderPartial)))[{3}].type, "{1s}",)
                        \\else
                        \\    {0s}{4s}{5s}
                    ,
                        .{
                            root,
                            it.rest(),
                            generated_partial_name.?,
                            // index + 2 to offset `data` and `slots` args:
                            index + 2,
                            if (it.rest().len == 0) "" else ".",
                            it.rest(),
                        },
                    );
                    try args_buf.append(chain);
                } else if (isIdentifier(root)) {
                    try args_buf.append(
                        try std.fmt.allocPrint(
                            self.allocator,
                            \\if (comptime __zmpl.isZmplValue(@TypeOf({0s})))
                            \\    try {0s}.coerce(std.meta.fields(std.meta.ArgsTuple(@TypeOf({1s}_renderPartial)))[{2}].type)
                            \\else
                            \\   {0s}
                        ,
                            .{
                                root,
                                generated_partial_name.?,
                                // index + 2 to offset `data` and `slots` args:
                                index + 2,
                            },
                        ),
                    );
                } else try args_buf.append(arg.value);
            } else {
                try args_buf.append(arg.value);
            }
        }
    }

    const template =
        \\{{
        \\{0s}
        \\        const __slots = [_]__zmpl.Data.Slot{{
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
    try writer.print(template, .{
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

fn generateSlots(self: Node, content: []const u8) !Slots {
    var slots_buf = std.ArrayList(u8).init(self.allocator);
    defer slots_buf.deinit();

    var slots_content_buf = std.ArrayList(u8).init(self.allocator);
    defer slots_content_buf.deinit();

    var slots_it = std.mem.splitScalar(u8, content, '\n');
    while (slots_it.next()) |slot| {
        if (util.strip(slot).len == 0) continue;

        const slot_name = try util.generateVariableNameAlloc(self.allocator);
        const slot_writer = try std.fmt.allocPrint(self.allocator, "{s}_writer", .{slot_name});

        try slots_content_buf.appendSlice(
            try std.fmt.allocPrint(self.allocator,
                \\var {0s}_buf = std.ArrayList(u8).init(allocator);
                \\const {0s}_writer = {0s}_buf.writer();
                \\
            , .{
                slot_name,
            }),
        );
        try self.renderHtml(
            util.strip(slot),
            .{ .zmpl_writer = slot_writer },
            slots_content_buf.writer(),
        );

        try slots_buf.appendSlice(try std.fmt.allocPrint(
            self.allocator,
            \\    __zmpl.Data.Slot{{ .data = {s}_buf.items }},
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

fn renderArgs(self: Node, writer: anytype) !void {
    _ = self;
    try writer.print(
        \\
    ,
        .{},
    );
}

fn renderExtend(self: Node, writer: anytype) !void {
    const extend = self.token.mode_line["@extend".len..];
    try writer.print(
        \\__extend = __zmpl.find({s});
        \\
    , .{try util.zigStringEscape(
        self.allocator,
        std.mem.trim(u8, util.strip(extend), "\""),
    )});
}

fn renderFor(self: Node, context: Context, content: []const u8, writer: anytype) !void {
    // If we have already rendered once, re-rendering the for loop makes no sense so we can just
    // write the remaining content directly. This can happen when a child node of the for loop
    // contains whitespace etc.
    if (context != .initial) return try self.renderHtml(content, .{}, writer);

    const expected_format_message = "Expected format `for (foo) |arg| { in {s}";
    const mode_line = self.token.mode_line["@for".len..];
    const for_args_start = std.mem.indexOfScalar(u8, mode_line, '(');
    const for_args_end = std.mem.lastIndexOfScalar(u8, mode_line, ')');
    if (for_args_start == null) {
        std.debug.print("{s}\n", .{expected_format_message});
        return error.ZmplSyntaxError;
    }
    if (for_args_end == null) {
        std.debug.print("{s}\n", .{expected_format_message});
        return error.ZmplSyntaxError;
    }
    const for_args = util.strip(mode_line[for_args_start.? + 1 .. for_args_end.?]);

    const rest = mode_line[for_args_end.? + 2 ..];
    const block_args_start = std.mem.indexOfScalar(u8, rest, '|');
    if (block_args_start == null) {
        std.debug.print("{s}\n", .{expected_format_message});
        return error.ZmplSyntaxError;
    }

    const block_args_end = std.mem.indexOfScalar(u8, rest[block_args_start.? + 1 ..], '|');
    if (block_args_end == null) {
        std.debug.print("{s}\n", .{expected_format_message});
        return error.ZmplSyntaxError;
    }

    const block_args = util.strip(rest[block_args_start.? + 1 .. block_args_end.? + 1]);

    var for_args_joined = std.ArrayList(u8).init(self.allocator);
    var for_args_writer = for_args_joined.writer();
    var for_args_it = std.mem.tokenizeScalar(u8, for_args, ',');
    while (for_args_it.next()) |arg| {
        if (std.mem.startsWith(u8, arg, ".") or std.mem.startsWith(u8, arg, "$.")) {
            try for_args_writer.print(
                "try zmpl.coerceArray({s}), ",
                .{try util.zigStringEscape(self.allocator, arg[1..])},
            );
        } else if (std.mem.containsAtLeast(u8, arg, 1, "..")) {
            try for_args_writer.print("{0s}, ", .{arg});
        } else {
            try for_args_writer.print(
                "if (comptime __zmpl.isZmplValue(@TypeOf({0s}))) {0s}.items(.array) else {0s}, ",
                .{arg},
            );
        }
    }

    try writer.print(
        \\for ({s}) |{s}| {{
        \\
    ,
        .{ try for_args_joined.toOwnedSlice(), block_args },
    );

    try self.renderHtml(content, .{}, writer);
}

fn parseZmpl(self: Node, content: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(self.allocator);
    const writer = buf.writer();
    var single_quoted = false;
    var double_quoted = false;
    var zmpl = false;
    for (content) |char| {
        switch (char) {
            '"' => {
                if (!single_quoted) {
                    double_quoted = !double_quoted;
                    try writer.writeByte(char);
                }
            },
            '\'' => {
                if (!double_quoted) {
                    single_quoted = !single_quoted;
                    try writer.writeByte(char);
                }
            },
            '$' => {
                if (double_quoted or single_quoted) {
                    try writer.writeByte(char);
                } else {
                    zmpl = true;
                    try writer.writeAll(
                        \\zmpl.ref("
                    );
                }
            },
            else => {
                if (zmpl) {
                    switch (char) {
                        ' ', '(', ')' => |chr| {
                            zmpl = false;
                            try writer.writeAll(
                                \\")
                            );
                            try writer.writeByte(chr);
                        },
                        else => {
                            try writer.writeByte(char);
                        },
                    }
                } else {
                    try writer.writeByte(char);
                }
            },
        }
    }
    return try buf.toOwnedSlice();
}

fn renderIf(self: Node, context: Context, content: []const u8, writer: anytype) !void {
    if (context == .initial) {
        // When we render nodes, we render child nodes that exist within their bounds as we work
        // through each node. We only want to render the initial `if` statement defined by this
        // node's args once. If we are on a `.secondary` render we just render any remaining
        // `@else if` and `@else` instructions and their contents.
        const input = self.token.args orelse return error.ZmplSyntaxError;
        const if_statement = try self.ifStatement(input);

        try if_statement.render(writer);
        try writer.writeAll(" {\n");
    }

    const content_end = util.indexOfWord(content, else_token) orelse content.len;
    // TODO: We should render for the mode scoped above us instead of assuming HTML.
    try self.renderHtml(content[0..content_end], .{}, writer);

    var it = ElseIterator{ .input = content, .index = 0, .node = self };
    while (try it.next()) |token| {
        try writer.writeAll("\n} else ");
        if (token.if_statement) |if_else_statement| {
            try if_else_statement.render(writer);
        }
        try writer.writeAll(" {\n");
        try self.renderHtml(token.content, .{}, writer);
    }
}

const ElseIterator = struct {
    input: []const u8,
    index: usize,
    node: Node,

    pub fn next(self: *ElseIterator) !?ElseToken {
        if (self.index >= self.input.len) return null;

        if (util.indexOfWord(self.input[self.index..], else_token)) |index| {
            const rest = self.input[self.index + index ..];
            const eol = std.mem.indexOfScalar(u8, rest, '\n') orelse {
                std.debug.print("Expected line break after `@else` directive.\n", .{});
                return error.ZmplSyntaxError;
            };
            if (util.indexOfWord(rest[0..eol], "if")) |if_index| {
                const if_statement = try self.node.ifStatement(rest[if_index + "if".len .. eol]);
                const end = util.indexOfWord(rest[eol..], else_token) orelse rest.len - eol;
                const content = rest[eol .. eol + end];
                self.index += eol + content.len;
                return .{ .content = content, .if_statement = if_statement };
            } else {
                self.index += rest.len + else_token.len;
                return .{ .content = rest[else_token.len..], .if_statement = null };
            }
        } else return null;
    }
};

const ElseToken = struct {
    content: []const u8,
    if_statement: ?IfStatement,
};

fn ifStatement(self: Node, input: []const u8) !IfStatement {
    const end = std.mem.lastIndexOfScalar(u8, input, '|') orelse
        std.mem.lastIndexOfScalar(u8, input, ')') orelse return error.ZmplSyntaxError;
    var ast = try IfStatement.parse(self.allocator, try self.parseZmpl(input[0 .. end + 1]));
    if (ast.errors.len > 0) {
        for (ast.errors) |err| {
            var buf: [1024]u8 = undefined;
            var stream = std.io.fixedBufferStream(&buf);
            const writer = stream.writer();
            try ast.renderError(err, writer);
            std.debug.print("Error parsing `@if` conditions: {s}\n", .{stream.getWritten()});
        }
        return error.ZmplSyntaxError;
    }

    return IfStatement.init(ast);
}

// Represents a name/value keypair OR a name/type keypair.
const Arg = struct {
    name: ?[]const u8,
    value: []const u8,
    default: ?[]const u8 = null,
};

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

fn renderWrite(
    self: Node,
    input: []const u8,
    writer_options: WriterOptions,
    writer: anytype,
) !void {
    return writer.print(
        \\_ = try {s}.write(zmpl.chomp({s}));
        \\
    ,
        .{ writer_options.zmpl_writer, try util.zigStringEscape(self.allocator, input) },
    );
}

fn renderRef(
    self: Node,
    input: []const u8,
    writer_options: WriterOptions,
    writer: anytype,
) !void {
    const stripped = util.strip(input);
    if (std.mem.startsWith(u8, stripped, ".") or std.mem.startsWith(u8, stripped, "$.")) {
        try self.renderDataRef(stripped[1..], writer_options, writer);
    } else if (std.mem.indexOfAny(u8, stripped, " \"+-/*{}!?()")) |_| {
        try self.renderZigLiteral(stripped, writer_options, writer);
    } else {
        try self.renderValueRef(stripped, writer_options, writer);
    }
}

fn renderDataRef(
    self: Node,
    input: []const u8,
    writer_options: WriterOptions,
    writer: anytype,
) !void {
    _ = self;
    try writer.print(
        \\try __zmpl.sanitize({s}, try zmpl.getValueString("{s}"));
        \\
    ,
        .{ writer_options.zmpl_writer, input },
    );
}

fn renderValueRef(
    self: Node,
    input: []const u8,
    writer_options: WriterOptions,
    writer: anytype,
) !void {
    var arg_name: [32]u8 = undefined;
    util.generateVariableName(&arg_name);
    var blk_label: [32]u8 = undefined;
    util.generateVariableName(&blk_label);
    var blk_arg: [32]u8 = undefined;
    util.generateVariableName(&blk_arg);
    var index_arg: [32]u8 = undefined;
    util.generateVariableName(&index_arg);

    if (std.mem.containsAtLeast(u8, input, 1, ".")) {
        const start = std.mem.indexOfScalar(u8, input, '.').?;
        try writer.print(
            \\_ = if (comptime __zmpl.isZmplValue(@TypeOf({1s})))
            \\       try __zmpl.sanitize({0s}, try zmpl.maybeRef({1s}, {2s}))
            \\    else if (comptime @TypeOf({3s}) == __zmpl.Data.LayoutContent)
            \\             try {0s}.write({3s}.data)
            \\         else
            \\             try __zmpl.sanitize({0s}, try zmpl.coerceString({3s}));
            \\
        ,
            .{
                writer_options.zmpl_writer,
                input[0..start],
                try util.zigStringEscape(self.allocator, input[start + 1 ..]),
                input,
            },
        );
    } else try writer.print(
        \\const {0s} = {1s};
        \\_ = if (comptime @TypeOf({0s}) == __zmpl.Data.Slot)
        \\        try {2s}.write({0s}.data)
        \\    else if (@TypeOf({0s}) == []const __zmpl.Data.Slot) {4s}: {{
        \\        for ({0s}, 0..) |{3s}, {5s}| {{
        \\          try {2s}.write({3s}.data);
        \\          if ({5s} + 1 < {0s}.len) try {2s}.write("\n");
        \\        }}
        \\        break :{4s} "";
        \\    }} else try __zmpl.sanitize({2s}, try zmpl.coerceString({0s}));
        \\
    ,
        .{ arg_name, input, writer_options.zmpl_writer, blk_label, blk_arg, index_arg },
    );
}

fn renderZigLiteral(
    self: Node,
    input: []const u8,
    writer_options: WriterOptions,
    writer: anytype,
) !void {
    _ = self;
    try writer.print(
        \\_ = try {s}.write({s});
        \\
    ,
        .{ writer_options.zmpl_writer, input },
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

fn isIdentifier(arg: []const u8) bool {
    const stripped = std.mem.trim(u8, arg, &std.ascii.whitespace);

    if (std.mem.indexOfScalar(u8, stripped, ' ')) |_| return false;
    if (arg.len > 0 and std.ascii.isAlphabetic(arg[0])) return true;

    return false;
}

fn debugPartialArgumentError(input: []const u8) void {
    std.debug.print("Error parsing partial arguments in: `{s}`\n", .{input});
}
