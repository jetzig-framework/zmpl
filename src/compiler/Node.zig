const std = @import("std");
const Writer = std.Io.Writer;
const builtin = @import("builtin");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMapUnmanaged;

const zmd = @import("zmd");
const ZmdNode = zmd.Node;
const ZmdConfig = zmd.Config;

const core = @import("core");
const Config = core.Config;

const Template = @import("Template.zig");
const Token = Template.Token;
const Mode = Template.Mode;
const TemplateMap = Template.TemplateMap;
const util = @import("util.zig");
const IfStatement = @import("IfStatement.zig");

token: Token,
children: ArrayList(*Node),
parent: ?*const Node,
generated_template_name: []const u8,
allocator: Allocator,
io: std.Io,
template_map: StringHashMap(TemplateMap),
templates_paths_map: StringHashMap([]const u8),
templates_path: []const u8,
template_prefix: []const u8,
template_func_name: []const u8,
block_writer: *Writer,
block_map: *StringHashMap(ArrayList(Block)),

const else_token = "@else";

const Node = @This();

const WriterOptions = struct { zmpl_writer: []const u8 = "data_struct.interface.output_writer" };

pub const Block = struct {
    name: []const u8,
    func: []const u8,
};

pub fn compile(self: Node, input: []const u8, writer: *Writer, comptime config: Config) !void {
    if (self.token.mode == .partial and self.children.items.len > 0) {
        std.log.err(
            "Partial slots cannot contain mode blocks:\n{s}",
            .{input[self.token.start - self.token.mode_line.len .. self.token.end]},
        );
        return error.ZmplSyntaxError;
    }

    // Write chunks for current token between child token boundaries, rendering child token
    // immediately after.
    var start: usize = self.token.startOfContent();
    var initial = true;
    for (self.children.items) |child_node| {
        if (start < child_node.token.start) {
            const content = input[start .. child_node.token.start - 1];
            try self.render(
                if (initial) .initial else .secondary,
                content,
                config,
                writer,
            );
            initial = false;
        }

        start = child_node.token.end + 1;
        try child_node.compile(input, writer, config);
    }

    if (self.children.items.len == 0) {
        const content = input[self.token.startOfContent()..self.contentEnd(input)];
        try self.render(.initial, content, config, writer);
    } else {
        const last_child = self.children.items[self.children.items.len - 1];
        if (last_child.token.end + 1 < self.contentEnd(input)) {
            const content = input[last_child.token.end + 1 .. self.contentEnd(input)];
            try self.render(.secondary, content, config, writer);
        }
    }
    try self.renderClose(writer);
}

// End offset of this node's content. For block modes the closing delimiter (`@end` / `}`) sits on
// its own line; `endOfContent` lands inside that line's leading indentation, so back up over the
// trailing horizontal whitespace to exclude the closing line from the rendered content.
fn contentEnd(self: Node, input: []const u8) usize {
    var end = self.token.endOfContent();
    switch (self.token.delimiter) {
        // A `.string` (`@end` / custom delimiter) or `.brace` (`}`) close sits on its own line;
        // back up over its leading indentation so it isn't emitted as trailing content whitespace.
        .string, .brace => {
            const start = self.token.startOfContent();
            while (end > start and (input[end - 1] == ' ' or input[end - 1] == '\t')) : (end -= 1) {}
        },
        .none, .eof => {},
    }
    return end;
}

const Context = enum { initial, secondary };

fn render(
    self: Node,
    context: Context,
    content: []const u8,
    comptime config: Config,
    writer: *Writer,
) !void {
    // `@//` comment lines are stripped from the whole source up front (see
    // `main.zig`), so `content` is already comment-free here.
    try self.renderMode(
        self.token.mode,
        context,
        content,
        config.zmd,
        if (self.hasBlockParent()) self.block_writer else writer,
    );
}

fn renderMode(self: Node, mode: Mode, context: Context, content: []const u8, config: ZmdConfig, writer: *Writer) !void {
    switch (mode) {
        .zig => try self.renderZig(content, writer),
        .html => try self.renderHtml(content, .{}, writer),
        .markdown => try self.renderHtml(
            try self.renderMarkdown(content, config),
            .{},
            writer,
        ),
        .partial => try self.renderPartial(content, writer),
        .args => try self.renderArgs(writer),
        .extend => try self.renderExtend(writer),
        .@"for" => try self.renderFor(context, content, writer, config),
        .@"if" => try self.renderIf(context, content, writer, config),
        .block => try self.writeBlock(context, content, config, writer),
        .define => try self.writeDefine(context, content, config),
        .blocks => {},
    }
}

fn renderClose(self: Node, writer: *Writer) !void {
    const close_writer = switch (self.token.mode) {
        .block, .define => self.block_writer,
        else => writer,
    };
    switch (self.token.mode) {
        .@"for", .@"if", .define => try close_writer.writeAll("\n}\n"),
        // `.none` is the `@block name(args)` call form — no `{` body, so nothing to close.
        .block => if (self.token.delimiter != .none) try close_writer.writeAll("\n}\n"),
        .zig, .html, .markdown, .partial, .args, .extend, .blocks => {},
    }
}

fn renderZig(self: Node, content: []const u8, writer: *Writer) !void {
    var html_it = self.htmlIterator(content);

    while (html_it.next()) |line| {
        const mode = getHtmlLineMode(line);
        switch (mode) {
            .html => try self.renderHtml(line, .{}, writer),
            .zig => try writer.print("{s}\n", .{line}),
        }
    }
}

fn hasBlockParent(self: Node) bool {
    const parent = self.parent orelse return false;
    return switch (parent.token.mode) {
        .block, .define => true,
        else => parent.hasBlockParent(),
    };
}

const HtmlIterator = struct {
    allocator: Allocator,
    content: []const u8,
    index: usize = 0,

    pub fn init(allocator: Allocator, content: []const u8) HtmlIterator {
        return .{ .allocator = allocator, .content = content };
    }

    pub fn next(self: *HtmlIterator) ?[]const u8 {
        if (self.content.len == 0 or self.index >= self.content.len - 1) return null;

        const start = self.index;

        if (util.ignore_whitespace.firstChar(self.content[start..])) |char| {
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
    return .init(self.allocator, content);
}
fn getHtmlLineMode(line: []const u8) enum { html, zig } {
    return if (util.ignore_whitespace.startsWith(line, Syntax.tag_open))
        .html
    else if (util.ignore_whitespace.startsWith(line, Syntax.ref_open))
        .html
    else
        .zig;
}

// returns allocated string
fn renderMarkdown(self: Node, content: []const u8, config: ZmdConfig) ![]const u8 {
    return zmd.parseAlloc(self.allocator, content, config);
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
    writer: *Writer,
) !void {
    var index: usize = 0;

    var ref_buf: ArrayList(u8) = .empty;
    defer ref_buf.deinit(self.allocator);
    var html_buf: ArrayList(u8) = .empty;
    defer html_buf.deinit(self.allocator);
    var ref_open = false;
    var escaped = false;

    while (index < content.len) : (index += 1) {
        const char = content[index];

        if (std.mem.startsWith(u8, content[index..], Syntax.ref_open)) {
            try self.renderWrite(html_buf.items, writer_options, writer);
            html_buf.clearAndFree(self.allocator);
            index += Syntax.ref_open.len - 1;
            ref_open = true;
        } else if (ref_open and std.mem.startsWith(u8, content[index..], Syntax.ref_close)) {
            index += Syntax.ref_close.len - 1;
            ref_open = false;
            try self.renderRef(ref_buf.items, writer_options, writer);
            ref_buf.clearAndFree(self.allocator);
        } else if (ref_open) {
            try ref_buf.append(self.allocator, char);
        } else if (char == '\\' and !escaped) {
            escaped = true;
        } else {
            escaped = false;
            try html_buf.append(self.allocator, char);
        }
    }

    if (html_buf.items.len > 0) {
        if (std.mem.eql(u8, writer_options.zmpl_writer, "zmpl.*.output_writer")) {
            try html_buf.append(self.allocator, '\n');
        }
        try self.renderWrite(html_buf.items, writer_options, writer);
    }
}

fn renderPartial(self: Node, content: []const u8, writer: *Writer) !void {
    if (self.token.args == null) {
        std.log.err(
            "Expected `@partial` with name, no name was given [{}->{}]: '{s}'",
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
    const prefixed_partial_name = std.mem.trim(u8, args[0..partial_name_end], &std.ascii.whitespace);
    const partial_args = try self.parsePartialArgs(args[partial_name_end..]);

    const prefix_end_index = std.mem.indexOfScalar(u8, prefixed_partial_name, ':');
    const partial_name = if (prefix_end_index) |index|
        prefixed_partial_name[index + 1 ..]
    else
        prefixed_partial_name;
    const prefix = if (prefix_end_index) |index|
        prefixed_partial_name[0..index]
    else
        self.template_prefix;

    var some_keyword = false;
    var some_positional = false;

    for (partial_args) |arg| {
        if (arg.name == null) some_positional = true else some_keyword = true;
    }

    if (some_positional and some_keyword) {
        std.log.err(
            "Partial args must be either all keyword or all positional, found: {s}",
            .{args},
        );
        return error.ZmplSyntaxError;
    }

    const expected_partial_args = try self.getPartialArgsSignature(prefix, partial_name);

    var reordered_args: ArrayList(Arg) = .empty;
    defer reordered_args.deinit(self.allocator);

    outer: for (expected_partial_args, 0..) |expected_arg, expected_arg_index| {
        for (partial_args, 0..) |actual_arg, actual_arg_index| {
            if (actual_arg.name == null) {
                if (actual_arg_index == expected_arg_index) {
                    try reordered_args.append(self.allocator, actual_arg);
                    continue :outer;
                } else continue;
            }
            if (expected_arg.name == null) {
                std.log.err("Error parsing @args pragma for partial `{s}`", .{partial_name});
                return error.ZmplSyntaxError;
            }
            if (std.mem.eql(u8, actual_arg.name.?, expected_arg.name.?)) {
                try reordered_args.append(self.allocator, actual_arg);
            }
        }
    }

    for (expected_partial_args, 0..) |expected_arg, index| {
        if (index + 1 > reordered_args.items.len) {
            if (expected_arg.default) |default| try reordered_args.append(
                self.allocator,
                .{ .name = expected_arg.name, .value = default },
            );
        }
    }

    if (reordered_args.items.len != expected_partial_args.len) {
        std.log.err("Expected args for partial `{s}`: ", .{partial_name});
        for (expected_partial_args, 0..) |arg, index| std.log.err(
            "{s}{s}",
            .{ arg.name.?, if (index + 1 < expected_partial_args.len) ", " else "\n" },
        );
        std.log.err("Found: ", .{});
        for (partial_args, 0..) |arg, index| std.log.err(
            "{s}{s}",
            .{ arg.name orelse "[]", if (index + 1 < partial_args.len) ", " else "\n" },
        );
        return error.ZmplSyntaxError;
    }

    const prefix_map = self.template_map.get(prefix) orelse {
        std.log.warn("Failed detecting Zmpl prefix directory: `{s}` in partial `{s}`", .{ prefix, partial_name });
        return;
    };
    const generated_partial_name = prefix_map.get(
        try util.templatePathFetch(self.allocator, partial_name, true),
    );

    if (generated_partial_name == null) {
        std.log.err("Partial not found: {s}", .{partial_name});
        return error.ZmplSyntaxError;
    }

    const slots = try self.generateSlots(content);

    var args_buf: ArrayList([]const u8) = .empty;
    defer args_buf.deinit(self.allocator);

    for (reordered_args.items) |arg| {
        // Partial args are plain Zig expressions; `$.`/`.` are shorthand for the render `context`.
        if (std.mem.startsWith(u8, arg.value, "$.")) {
            try args_buf.append(
                self.allocator,
                try std.fmt.allocPrint(self.allocator, "data{s}", .{arg.value[1..]}),
            );
        } else if (std.mem.startsWith(u8, arg.value, ".")) {
            try args_buf.append(
                self.allocator,
                try std.fmt.allocPrint(self.allocator, "data{s}", .{arg.value}),
            );
        } else {
            try args_buf.append(self.allocator, arg.value);
        }
    }

    const template =
        \\{{
        \\{[generators]s}
        \\        const __slots = [_]__core.Slot{{
        \\{[items]s}
        \\        }};
        \\        var __partial_data = @TypeOf(data_struct.*).init(data_struct.interface.io, allocator, data_struct.context);
        \\        defer __partial_data.deinit();
        \\
        \\    const __partial_output = try @import("partial/{[name]s}").renderPartial(&__partial_data, &__slots, {[content]s});
        \\    defer allocator.free(__partial_output);
        \\    try data_struct.interface.write(__partial_output);
        \\}}
        \\
    ;
    try writer.print(template, .{
        .generators = slots.content_generators,
        .items = slots.items,
        .name = partial_name,
        .content = try std.mem.join(self.allocator, ", ", args_buf.items),
    });
}

const Slots = struct {
    content_generators: []const u8,
    items: []const u8,
};

fn generateSlots(self: Node, content: []const u8) !Slots {
    var slots_buf: ArrayList(u8) = .empty;
    defer slots_buf.deinit(self.allocator);

    var slots_content_buf: ArrayList(u8) = .empty;
    defer slots_content_buf.deinit(self.allocator);

    var slots_it = std.mem.splitScalar(u8, content, '\n');
    while (slots_it.next()) |slot| {
        if (util.strip(slot).len == 0) continue;

        const slot_name = try util.generateTempVariableNameAlloc(self.allocator);
        const slot_writer = try std.fmt.allocPrint(self.allocator, "{s}_writer", .{slot_name});

        try slots_content_buf.appendSlice(
            self.allocator,
            try std.fmt.allocPrint(self.allocator,
                \\var {0s}_buf: std.Io.Writer.Allocating = .init(allocator);
                \\defer {0s}_buf.deinit();
                \\const {0s}_writer = &{0s}_buf.writer;
                \\
            , .{
                slot_name,
            }),
        );
        var aw: std.Io.Writer.Allocating = .fromArrayList(self.allocator, &slots_content_buf);
        defer aw.deinit();
        try self.renderHtml(
            util.strip(slot),
            .{ .zmpl_writer = slot_writer },
            &aw.writer,
        );
        slots_content_buf = aw.toArrayList();

        try slots_buf.appendSlice(self.allocator, try std.fmt.allocPrint(
            self.allocator,
            \\    __core.Slot{{ .data = try {s}_buf.toOwnedSlice() }},
            \\
        ,
            .{slot_name},
        ));
    }

    return Slots{
        .content_generators = try slots_content_buf.toOwnedSlice(self.allocator),
        .items = try slots_buf.toOwnedSlice(self.allocator),
    };
}

fn renderArgs(self: Node, writer: *Writer) !void {
    _ = self;
    try writer.print(
        \\
    ,
        .{},
    );
}

fn renderExtend(self: Node, writer: *Writer) !void {
    // `@extend` is resolved at compile time by `Template.renderFooter`, which renders the parent
    // template module directly. Nothing needs to be emitted at the pragma's position.
    _ = self;
    _ = writer;
}

fn renderFor(self: Node, context: Context, content: []const u8, writer: *Writer, config: ZmdConfig) !void {
    // If we have already rendered once, re-rendering the for loop makes no sense so we can just
    // write the remaining content directly. This can happen when a child node of the for loop
    // contains whitespace etc.
    if (context != .initial) {
        if (self.parent) |parent| {
            switch (parent.contentRenderMode()) {
                .zig => try self.renderZig(content, writer),
                .html => try self.renderHtml(content, .{}, writer),
                .markdown => try self.renderHtml(
                    try self.renderMarkdown(content, config),
                    .{},
                    writer,
                ),
            }
        }
        return;
    }

    const expected_format_message = "Expected format `for (foo) |arg| { in {s}";
    const mode_line = self.token.mode_line["@for".len..];
    const for_args_start = std.mem.indexOfScalar(u8, mode_line, '(');
    const for_args_end = std.mem.lastIndexOfScalar(u8, mode_line, ')');
    if (for_args_start == null) {
        std.log.err("{s}", .{expected_format_message});
        return error.ZmplSyntaxError;
    }
    if (for_args_end == null) {
        std.log.err("{s}", .{expected_format_message});
        return error.ZmplSyntaxError;
    }
    const for_args = util.strip(mode_line[for_args_start.? + 1 .. for_args_end.?]);

    const rest = mode_line[for_args_end.? + 2 ..];
    const block_args_start = std.mem.indexOfScalar(u8, rest, '|');
    if (block_args_start == null) {
        std.log.err("{s}", .{expected_format_message});
        return error.ZmplSyntaxError;
    }

    const block_args_end = std.mem.indexOfScalar(u8, rest[block_args_start.? + 1 ..], '|');
    if (block_args_end == null) {
        std.log.err("{s}", .{expected_format_message});
        return error.ZmplSyntaxError;
    }

    const block_args = util.strip(rest[block_args_start.? + 1 .. block_args_end.? + 1]);

    var for_args_joined: std.Io.Writer.Allocating = .init(self.allocator);
    var for_args_writer = &for_args_joined.writer;
    var for_args_it = std.mem.tokenizeScalar(u8, for_args, ',');
    while (for_args_it.next()) |raw_arg| {
        const arg = util.strip(raw_arg);
        if (std.mem.startsWith(u8, arg, "$.")) {
            try for_args_writer.print("data{s}, ", .{arg[1..]});
        } else if (std.mem.startsWith(u8, arg, ".")) {
            try for_args_writer.print("data{s}, ", .{arg});
        } else {
            try for_args_writer.print("{s}, ", .{arg});
        }
    }

    try writer.print(
        \\for ({s}) |{s}| {{
        \\
    ,
        .{ try for_args_joined.toOwnedSlice(), block_args },
    );

    if (self.parent) |parent| {
        switch (parent.contentRenderMode()) {
            .zig => try self.renderZig(content, writer),
            .html => try self.renderHtml(content, .{}, writer),
            .markdown => try self.renderHtml(
                try self.renderMarkdown(content, config),
                .{},
                writer,
            ),
        }
    }
}

fn parseZmpl(self: Node, content: []const u8) ![]const u8 {
    var buf: std.Io.Writer.Allocating = .init(self.allocator);
    defer buf.deinit();
    const writer = &buf.writer;
    var single_quoted = false;
    var double_quoted = false;
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
                    // `$` is shorthand for the render data root, e.g. `$.foo` => `data.foo`.
                    try writer.writeAll("data");
                }
            },
            else => try writer.writeByte(char),
        }
    }
    return buf.toOwnedSlice();
}

fn renderIf(self: Node, context: Context, content: []const u8, writer: *Writer, config: ZmdConfig) !void {
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
    // Render content using the parent's render mode
    switch (self.contentRenderMode()) {
        .html => try self.renderHtml(content[0..content_end], .{}, writer),
        .zig => try self.renderZig(content[0..content_end], writer),
        .markdown => try self.renderHtml(
            try self.renderMarkdown(content[0..content_end], config),
            .{},
            writer,
        ),
    }

    var it = ElseIterator{ .input = content, .index = 0, .node = self };
    while (try it.next()) |token| {
        try writer.writeAll("\n} else");
        if (token.if_statement) |if_else_statement| {
            try writer.writeAll(" ");
            try if_else_statement.render(writer);
        }
        try writer.writeAll(" {\n");

        // Render else/else-if content using the parent's render mode
        switch (self.contentRenderMode()) {
            .html => try self.renderHtml(token.content, .{}, writer),
            .zig => try self.renderZig(token.content, writer),
            .markdown => try self.renderHtml(
                try self.renderMarkdown(token.content, config),
                .{},
                writer,
            ),
        }
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
                std.log.err("Expected line break after `@else` directive.", .{});
                return error.ZmplSyntaxError;
            };
            if (util.indexOfWord(rest[0..eol], "if")) |if_index| {
                const if_statement = try self.node.ifStatement(rest[if_index + "if".len .. eol]);
                const end = util.indexOfWord(rest[eol..], else_token) orelse rest.len - eol;
                const content = rest[eol .. eol + end];
                self.index += index + eol + content.len;
                return .{ .content = content, .if_statement = if_statement };
            } else {
                const end = util.indexOfWord(rest[eol..], else_token) orelse rest.len - eol;
                const content = rest[eol .. eol + end];
                self.index += index + eol + content.len;
                return .{ .content = content, .if_statement = null };
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
            var writer: std.Io.Writer = .fixed(&buf);
            // var stream = std.Io.fixedBufferStream(&buf);
            try ast.renderError(err, &writer);
            std.log.err("Error parsing `@if` conditions: {s}", .{writer.buffered()});
        }
        return error.ZmplSyntaxError;
    }

    return .init(ast);
}

// Write a `@block` definition - note that we write to a different output buffer here - each
// block is compiled into a separate function which is written after the main manifest body.
fn writeBlock(self: Node, context: Context, content: []const u8, config: ZmdConfig, out_writer: *Writer) !void {
    if (context == .initial) {
        const args = self.token.args orelse {
            std.log.err("Missing argument to `@block` mode: `{s}`", .{self.token.mode_line});
            return error.ZmplSyntaxError;
        };
        // `@block name(args)` (no `{` body) is a CALL to a `@define`d block: render it in place.
        if (self.token.delimiter == .none) return self.writeBlockCall(args, out_writer);
        const name_end = std.mem.indexOf(u8, args, self.token.delimiter.toString(.open)) orelse {
            std.log.err("Missing delimiter `@block` mode: `{s}`", .{self.token.mode_line});
            return error.ZmplSyntaxError;
        };
        const raw_name = std.mem.trim(
            u8,
            args[0..name_end],
            &std.ascii.whitespace,
        );

        try self.block_writer.writeAll(
            \\ pub fn 
        );
        try util.sanitizeKey(raw_name, self.block_writer);
        try self.block_writer.writeAll(
            \\(data_struct: anytype) !void {
            \\  const data = data_struct.context;
            \\  _ = &data;
            \\  const zmpl = &data_struct.interface;
            \\  _ = &zmpl;
            \\
        );
        try out_writer.writeAll("try ");
        try util.sanitizeKey(raw_name, out_writer);
        try out_writer.writeAll("(data_struct);\n");
    }

    const writer = self.block_writer;
    if (self.parent) |parent| {
        switch (parent.token.mode) {
            .zig => try self.renderZig(content, writer),
            .html => try self.renderHtml(content, .{}, writer),
            .markdown => try self.renderHtml(
                try self.renderMarkdown(content, config),
                .{},
                writer,
            ),
            .partial => try self.renderPartial(content, writer),
            .args => try self.renderArgs(writer),
            .extend => try self.renderExtend(writer),
            .@"for" => try self.renderFor(context, content, writer, config),
            .@"if" => try self.renderIf(context, content, writer, config),
            .block => try self.writeBlock(context, content, config, writer),
            .define => try self.writeDefine(context, content, config),
            .blocks => {},
        }
    } else {
        try self.renderHtml(content, .{}, writer);
    }
}

// `@define name(arg: T, ...) { body }` — define a reusable `pub fn name(data_struct, arg: T, ...)` on the
// template module. Unlike `@block`, it is NOT rendered in place; invoke with `@block name(args)` or
// directly in a `@zig` block via `try name(data_struct, args)`.
fn writeDefine(self: Node, context: Context, content: []const u8, config: ZmdConfig) anyerror!void {
    if (context == .initial) {
        const args = self.token.args orelse {
            std.log.err("Missing argument to `@define` mode: `{s}`", .{self.token.mode_line});
            return error.ZmplSyntaxError;
        };
        const body_at = std.mem.indexOf(u8, args, self.token.delimiter.toString(.open)) orelse args.len;
        const paren_at = std.mem.indexOfScalar(u8, args[0..body_at], '(') orelse body_at;
        const raw_name = std.mem.trim(u8, args[0..paren_at], &std.ascii.whitespace);

        // Build the typed parameter list from the `(name: type, ...)` signature.
        try self.block_writer.writeAll(
            \\pub fn 
        );
        try util.sanitizeKey(raw_name, self.block_writer);
        try self.block_writer.writeAll("(data_struct: anytype");
        if (paren_at < body_at) {
            for (try self.parsePartialArgs(args[paren_at..body_at])) |arg| {
                if (arg.name == null) {
                    std.log.err("`@define {s}` params must be `name: type`: `{s}`", .{ raw_name, self.token.mode_line });
                    return error.ZmplSyntaxError;
                }
                try self.block_writer.print(", {s}: {s}", .{ arg.name.?, arg.value });
            }
        }
        try self.block_writer.writeAll(
            \\) !void {
            \\  const data = data_struct.context;
            \\  _ = &data;
            \\  const zmpl = &data_struct.interface;
            \\  _ = &zmpl;
            \\
        );
    }

    const writer = self.block_writer;
    if (self.parent) |parent| {
        switch (parent.token.mode) {
            .zig => try self.renderZig(content, writer),
            .html => try self.renderHtml(content, .{}, writer),
            .markdown => try self.renderHtml(try self.renderMarkdown(content, config), .{}, writer),
            .partial => try self.renderPartial(content, writer),
            .args => try self.renderArgs(writer),
            .extend => try self.renderExtend(writer),
            .@"for" => try self.renderFor(context, content, writer, config),
            .@"if" => try self.renderIf(context, content, writer, config),
            .block => try self.writeBlock(context, content, config, writer),
            .define => try self.writeDefine(context, content, config),
            .blocks => {},
        }
    } else {
        try self.renderHtml(content, .{}, writer);
    }
}

// `@block name(args)` — call a `@define`d block and render its output in place.
fn writeBlockCall(self: Node, args: []const u8, writer: *Writer) !void {
    const paren_at = std.mem.indexOfScalar(u8, args, '(') orelse args.len;
    const raw_name = std.mem.trim(u8, args[0..paren_at], &std.ascii.whitespace);

    try writer.writeAll("try ");
    try util.sanitizeKey(raw_name, writer);
    try writer.writeAll("(data_struct");
    if (paren_at < args.len) {
        for (try self.parsePartialArgs(args[paren_at..])) |arg|
            try writer.print(", {s}", .{arg.value});
    }
    try writer.writeAll(");\n");
}

// Represents a name/value keypair OR a name/type keypair.
const Arg = struct {
    name: ?[]const u8,
    value: []const u8,
    default: ?[]const u8 = null,
};

pub fn parsePartialArgs(self: Node, input: []const u8) ![]Arg {
    var args: ArrayList(Arg) = .empty;
    defer args.deinit(self.allocator);

    const first_token = std.mem.indexOfScalar(u8, input, '(');
    const last_token = std.mem.lastIndexOfScalar(u8, input, ')');
    if (first_token == null or last_token == null) return args.toOwnedSlice(self.allocator);
    if (first_token.? + 1 >= last_token.?) return args.toOwnedSlice(self.allocator);

    var chunks: ArrayList([]const u8) = .empty;
    defer chunks.deinit(self.allocator);
    defer for (chunks.items) |chunk| self.allocator.free(chunk);

    var chunk_buf: ArrayList(u8) = .empty;
    defer chunk_buf.deinit(self.allocator);

    var quote_open = false;
    var escape = false;

    for (input[first_token.? + 1 .. last_token.?]) |char| {
        if (char == '\\' and !escape) {
            escape = true;
        } else if (escape) {
            try chunk_buf.append(self.allocator, '\\');
            try chunk_buf.append(self.allocator, char);
            escape = false;
        } else if (char == '"' and !quote_open) {
            quote_open = true;
            try chunk_buf.append(self.allocator, char);
        } else if (char == '"' and quote_open) {
            quote_open = false;
            try chunk_buf.append(self.allocator, char);
        } else if (char == ',' and !quote_open) {
            try chunks.append(self.allocator, try self.allocator.dupe(u8, util.strip(chunk_buf.items)));
            chunk_buf.clearAndFree(self.allocator);
        } else {
            try chunk_buf.append(self.allocator, char);
        }
    }

    if (util.strip(chunk_buf.items).len > 0) {
        try chunks.append(self.allocator, try self.allocator.dupe(u8, util.strip(chunk_buf.items)));
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

        try args.append(self.allocator, .{
            .name = if (name) |capture| try self.allocator.dupe(u8, capture) else null,
            .value = try self.allocator.dupe(u8, value),
            .default = if (default) |capture| try self.allocator.dupe(u8, capture) else null,
        });
    }

    return args.toOwnedSlice(self.allocator);
}

fn renderWrite(
    self: Node,
    input: []const u8,
    writer_options: WriterOptions,
    writer: *Writer,
) !void {
    return writer.print(
        \\try {s}.writeAll(data_struct.interface.chomp({s}));
        \\
    ,
        .{ writer_options.zmpl_writer, try util.zigStringEscape(self.allocator, input) },
    );
}

fn renderRef(
    self: Node,
    input: []const u8,
    writer_options: WriterOptions,
    writer: *Writer,
) !void {
    const stripped = util.strip(input);
    if (std.mem.startsWith(u8, stripped, "$.")) {
        // `$.foo` shorthand => `context.foo`
        const expr = try std.fmt.allocPrint(self.allocator, "data{s}", .{stripped[1..]});
        try self.renderValueRef(expr, writer_options, writer);
    } else if (std.mem.startsWith(u8, stripped, ".")) {
        // `.foo` shorthand => `context.foo`
        const expr = try std.fmt.allocPrint(self.allocator, "data{s}", .{stripped});
        try self.renderValueRef(expr, writer_options, writer);
    } else if (std.mem.indexOfAny(u8, stripped, " \"+-/*{}!?()")) |_| {
        try self.renderZigLiteral(stripped, writer_options, writer);
    } else {
        try self.renderValueRef(stripped, writer_options, writer);
    }
}

fn renderValueRef(
    self: Node,
    input: []const u8,
    writer_options: WriterOptions,
    writer: *Writer,
) !void {
    _ = self;
    var value_buf: [32]u8 = undefined;
    const value = util.generateTempVariableName(&value_buf);
    var item_buf: [32]u8 = undefined;
    const item = util.generateTempVariableName(&item_buf);
    var index_buf: [32]u8 = undefined;
    const index = util.generateTempVariableName(&index_buf);

    // `input` is a Zig expression (e.g. `context.foo`). Render a slot, a list of slots, layout
    // content, or coerce the value to a string.
    try writer.print(
        \\const {[value]s} = {[input]s};
        \\if (comptime @TypeOf({[value]s}) == __core.Slot) {{
        \\    try {[writer]s}.writeAll({[value]s}.data);
        \\}} else if (@TypeOf({[value]s}) == []const __core.Slot) {{
        \\    for ({[value]s}, 0..) |{[item]s}, {[index]s}| {{
        \\        try {[writer]s}.writeAll({[item]s}.data);
        \\        if ({[index]s} + 1 < {[value]s}.len) try {[writer]s}.writeAll("\n");
        \\    }}
        \\}} else if (comptime @TypeOf({[value]s}) == __core.LayoutContent) {{
        \\    try {[writer]s}.writeAll({[value]s}.data);
        \\}} else {{
        \\    try __core.sanitize({[writer]s}, try data_struct.interface.coerceString({[value]s}));
        \\}}
        \\
    , .{
        .value = value,
        .input = input,
        .writer = writer_options.zmpl_writer,
        .item = item,
        .index = index,
    });
}

fn renderZigLiteral(
    self: Node,
    input: []const u8,
    writer_options: WriterOptions,
    writer: *Writer,
) !void {
    _ = self;
    var value_buf: [32]u8 = undefined;
    const value = util.generateTempVariableName(&value_buf);
    // The expression may evaluate to a plain `[]const u8`, an error union (e.g.
    // `zmpl.fmt.raw(...)`), or an optional. Resolve it before writing. The switch is
    // comptime-pruned so only the matching prong is compiled.
    try writer.print(
        \\const {[value]s} = {[input]s};
        \\try {[writer]s}.writeAll(switch (comptime @typeInfo(@TypeOf({[value]s}))) {{
        \\    .error_union => try {[value]s},
        \\    .optional => {[value]s} orelse "",
        \\    else => {[value]s},
        \\}});
        \\
    , .{ .value = value, .input = input, .writer = writer_options.zmpl_writer });
}

// Parse a target partial's `@args` pragma in order to re-order keyword args if needed.
// We need to read direct from the file here because we can't guarantee that the target partial
// has been parsed yet.
fn getPartialArgsSignature(self: Node, prefix: []const u8, partial_name: []const u8) ![]Arg {
    const fetch_name = try util.templatePathFetch(self.allocator, partial_name, true);
    std.mem.replaceScalar(u8, fetch_name, '/', std.fs.path.sep);
    const with_extension = try std.mem.concat(self.allocator, u8, &[_][]const u8{ fetch_name, ".zmpl" });
    defer self.allocator.free(with_extension);
    const templates_path = self.templates_paths_map.get(prefix) orelse {
        std.log.err(
            "Error locating templates path for prefix `{s}`",
            .{prefix},
        );
        return error.ZmplSyntaxError;
    };
    const path = try std.fs.path.join(self.allocator, &[_][]const u8{ templates_path, with_extension });
    defer self.allocator.free(path);
    const content = util.readFile(self.allocator, self.io, std.Io.Dir.cwd(), path) catch return &.{};
    defer self.allocator.free(content);
    var it = std.mem.splitScalar(u8, content, '\n');

    var args: ?[]Arg = null;

    while (it.next()) |line| {
        if (util.ignore_whitespace.startsWith(line, "@args")) {
            const normalized = try std.mem.concat(
                self.allocator,
                u8,
                &[_][]const u8{ "(", util.trimParentheses(util.strip(line)["@args".len..]), ")" },
            );
            defer self.allocator.free(normalized);
            args = try self.parsePartialArgs(normalized);
        }
    }

    if (args) |capture|
        return capture;
    return &.{};
}

const ContentRenderMode = enum { html, zig, markdown };
fn contentRenderMode(self: Node) ContentRenderMode {
    return switch (self.token.mode) {
        .html => .html,
        .zig => .zig,
        .markdown => .markdown,
        else => if (self.parent) |parent| parent.contentRenderMode() else .html,
    };
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
