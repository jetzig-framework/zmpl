const std = @import("std");

const jetcommon = @import("jetcommon");

const Node = @import("Node.zig");
const util = @import("util.zig");

const Template = @This();

pub const TemplateMap = std.StringHashMap([]const u8);

allocator: std.mem.Allocator,
templates_path: []const u8,
name: []const u8,
prefix: []const u8,
path: []const u8,
input: []const u8,
template_type: TemplateType,
state: enum { initial, tokenized, parsed, compiled } = .initial,
tokens: std.ArrayList(Token),
root_node: *Node = undefined,
index: usize = 0,
args: ?[]const u8 = null,
partial: bool,
template_map: std.StringHashMap(TemplateMap),
templates_paths_map: std.StringHashMap([]const u8),

const end_token = "@end";

/// A mode pragma and its content in the input buffer. Stores args if present.
/// e.g.:
/// ```
/// @zig {
///     // some zig
/// }
/// ```
///
/// ```
/// @partial foo {
///     <div>some HTML</div>
/// }
/// ```
pub const Token = struct {
    mode: Mode,
    delimiter: Delimiter,
    start: usize,
    end: usize,
    mode_line: []const u8,
    index: usize,
    depth: usize,
    args: ?[]const u8 = null,
    path: []const u8,

    pub fn startOfContent(self: Token) usize {
        return self.start + self.mode_line.len;
    }

    pub fn endOfContent(self: Token) usize {
        return self.end - switch (self.delimiter) {
            .eof, .none => 0,
            .string => |string| string.len,
            .brace => 1,
        };
    }
};

/// Initialize a new template.
pub fn init(
    allocator: std.mem.Allocator,
    name: []const u8,
    templates_path: []const u8,
    prefix: []const u8,
    path: []const u8,
    templates_paths_map: std.StringHashMap([]const u8),
    input: []const u8,
    template_map: std.StringHashMap(TemplateMap),
) Template {
    return .{
        .allocator = allocator,
        .templates_path = templates_path,
        .prefix = prefix,
        .name = name,
        .path = path,
        .template_type = templateType(path),
        .input = util.normalizeInput(allocator, input),
        .tokens = std.ArrayList(Token).init(allocator),
        .partial = std.mem.startsWith(u8, std.fs.path.basename(path), "_"),
        .template_map = template_map,
        .templates_paths_map = templates_paths_map,
    };
}

/// Free memory allocated by the template compilation.
pub fn deinit(self: *Template) void {
    self.tokens.deinit();
}

/// Compile a template into a Zig code which can then be written out and compiled by Zig.
pub fn compile(self: *Template, comptime options: type) ![]const u8 {
    if (self.state != .initial) unreachable;

    try self.tokenize();
    try self.parse();

    var buf = std.ArrayList(u8).init(self.allocator);
    defer buf.deinit();

    var writer = Node.Writer{ .buf = &buf, .token = self.tokens.items[0] };

    try self.renderHeader(writer, options);
    try self.root_node.compile(self.input, &writer, options);
    try self.renderFooter(writer);

    self.state = .compiled;

    const with_sentinel = try std.mem.concatWithSentinel(self.allocator, u8, &.{buf.items}, 0);
    var ast = try std.zig.Ast.parse(self.allocator, with_sentinel, .zig);
    return if (ast.errors.len > 0)
        try buf.toOwnedSlice()
    else
        ast.render(self.allocator);
}

/// Here for compatibility with `Template` only - manifest generates random names for templates
/// and stores path in template definition + ComptimeStringMap instead.
pub fn identifier(self: *Template) ![]const u8 {
    _ = self;
    return "";
}

const Mode = enum { html, zig, partial, args, markdown, extend, @"for", @"if" };
const Delimiter = union(enum) {
    string: []const u8,
    eof: void,
    none: void,
    brace: void,
};

const DelimitedMode = struct {
    mode: Mode,
    delimiter: Delimiter,
    delimiter_string: ?[]const u8 = null,
};

const Context = struct {
    mode: Mode,
    delimiter: Delimiter,
    start: usize,
    depth: isize = 1,
    mode_line: ?[]const u8 = null,

    pub fn delimiterLen(self: Context) usize {
        return switch (self.delimiter) {
            .string => |string| string.len,
            .brace => 1,
            .eof, .none => 0,
        };
    }
};

// Tokenize template into (possibly nested) sections, where each section is a mode declaration
// and its content, specified by start and end markers.
fn tokenize(self: *Template) !void {
    if (self.state != .initial) unreachable;

    var stack = std.ArrayList(Context).init(self.allocator);
    defer stack.deinit();
    try stack.append(.{ .mode = self.defaultMode(), .depth = 1, .start = 0, .delimiter = .eof });

    var line_it = std.mem.splitScalar(u8, self.input, '\n');
    var cursor: usize = 0;
    var depth: usize = 0;
    var line_index: usize = 0;

    while (line_it.next()) |line| : (cursor += line.len + 1) {
        line_index += 1;

        if (getDelimitedMode(line)) |delimited_mode| {
            const context: Context = .{
                .mode = delimited_mode.mode,
                .delimiter = delimited_mode.delimiter,
                .start = cursor,
                .depth = 1,
                .mode_line = line,
            };

            if (context.delimiter == .none) {
                try self.appendToken(context, cursor + line.len, depth + 1);
            } else {
                try stack.append(context);
                depth += 1;
            }
            continue;
        }

        resolveNesting(line, stack); // Modifies the `depth` field of the last value in the stack.

        if (stack.items.len > 0 and stack.items[stack.items.len - 1].depth == 0) {
            const context = stack.pop();
            const end = switch (context.delimiter) {
                .none => unreachable, // Handled above - we don't push a context for .none
                .eof => cursor + line.len,
                // We want a crash here if delimiter index not found as it means `resolveNesting`
                // is broken.
                .brace => cursor + std.mem.indexOfScalar(u8, line, '}').?,
                .string => |string| cursor + std.mem.indexOf(u8, line, string).? + string.len - 1,
            };

            try self.appendToken(context, end, depth);

            if (depth == 0) {
                self.debugError(line, line_index);
                return error.ZmplSyntaxError;
            } else {
                depth -= 1;
            }
        }
    }

    if (depth > 0) {
        std.debug.print("Error resolving block delimiters in `{s}`\n", .{self.path});
        return error.ZmplSyntaxError;
    }
    try self.appendRootToken();

    // for (self.tokens.items) |token| self.debugToken(token, false);

    self.state = .tokenized;
}

// Append a new token. Note that tokens are not ordered in any meaningful way - use
// `TokensIterator` to iterate through tokens in an appropriate order.
fn appendToken(self: *Template, context: Context, end: usize, depth: usize) !void {
    if (context.mode_line) |mode_line| {
        var args = std.mem.trim(u8, mode_line, &std.ascii.whitespace);
        args = switch (context.delimiter) {
            .none, .eof => args,
            .string => |delimiter_string| std.mem.trimRight(u8, args, delimiter_string),
            .brace => std.mem.trimRight(u8, args, "}"),
        };
        const args_start = @tagName(context.mode).len + 1;
        args = if (args_start <= args.len)
            std.mem.trim(u8, args[args_start..], &std.ascii.whitespace)
        else
            "";
        try self.tokens.append(.{
            .mode = context.mode,
            .start = context.start,
            .delimiter = context.delimiter,
            .end = end,
            .mode_line = mode_line,
            .args = if (args.len > 0) args else null,
            .index = self.tokens.items.len,
            .depth = depth,
            .path = self.path,
        });
    } else unreachable;
}

// Append a root token with the default mode that covers the entire input.
fn appendRootToken(self: *Template) !void {
    try self.tokens.append(.{
        .mode = self.defaultMode(),
        .delimiter = .eof,
        .start = 0,
        .end = self.input.len,
        .mode_line = "",
        .args = &.{},
        .index = self.tokens.items.len,
        .depth = 0,
        .path = self.path,
    });
}

// Recursively parse tokens into an AST.
fn parse(self: *Template) !void {
    if (self.state != .tokenized) unreachable;

    const root_token = getRootToken(self.tokens.items);
    self.root_node = try self.createNode(root_token);

    try self.parseChildren(self.root_node);

    // debugTree(self.root_node, 0, self.path);

    self.state = .parsed;
}

// Parse tokenized input by offloading to the relevant parser for each token's assigned mode.
fn parseChildren(self: *Template, node: *Node) !void {
    var tokens_it = self.tokensIterator(node.token);
    while (tokens_it.next()) |token| {
        const child_node = try self.createNode(token);
        try node.children.append(child_node);
        try self.parseChildren(child_node);
    }
}

// Create an AST node.
fn createNode(self: Template, token: Token) !*Node {
    const node = try self.allocator.create(Node);
    node.* = .{
        .allocator = self.allocator,
        .token = token,
        .children = std.ArrayList(*Node).init(self.allocator),
        .generated_template_name = self.name,
        .template_map = self.template_map,
        .templates_path = self.templates_path,
        .template_prefix = self.prefix,
        .templates_paths_map = self.templates_paths_map,
    };
    return node;
}

// Iterates through tokens in an appropriate order for parsing.
const TokensIterator = struct {
    index: usize,
    tokens: []Token,
    root_token: Token,

    /// Create a new token iterator for a given root token. Yields child and sibling tokens that
    /// exist within the bounds of the given root token.
    pub fn init(tokens: []Token, maybe_root_token: ?Token) TokensIterator {
        const root_token = maybe_root_token orelse getRootToken(tokens);
        return .{ .tokens = tokens, .root_token = root_token, .index = root_token.index };
    }

    /// Return the next token for the given root token.
    pub fn next(self: *TokensIterator) ?Token {
        if (self.tokens.len == 0) return null;

        self.index = self.getNextChildTokenIndex() orelse return null;

        return self.tokens[self.index];
    }

    // Identify the next token that exists at one depth level higher than the root token.
    fn getNextChildTokenIndex(self: TokensIterator) ?usize {
        var current_index: ?usize = null;

        for (self.tokens) |token| {
            // Do not yield tokens that are not immediate children
            if (token.depth != self.root_token.depth + 1) continue;
            // Do not yield the last-matched token or the root token
            if (token.index == self.index or token.index == self.root_token.index) continue;
            // Do not yield tokens that exist outside the bounds of the root token
            if (token.start < self.root_token.start or token.end > self.root_token.end) continue;
            // Do not yield tokens that begin before the last-matched token
            if (token.start < self.tokens[self.index].start) continue;

            // Set an initial value once all criteria are met
            if (current_index == null) {
                current_index = token.index;
                continue;
            }

            // Match the top-most token in the input (updates on each iteration)
            if (token.start < self.tokens[current_index.?].start) {
                current_index = token.index;
            }
        }

        if (current_index == null) return null;

        return current_index;
    }
};

// Return an iterator that yields tokens in an order appropriate for parsing (i.e. root node,
// then modal sections within the root node, modal sections within each modal section, etc.).
fn tokensIterator(self: Template, token: ?Token) TokensIterator {
    return TokensIterator.init(self.tokens.items, token);
}

// Given an input line, identify a mode sigil (`@`) and, if present, return the specified mode.
// Since `@` is also used in Zig code, we do not fail if an unrecognized mode is specified.
fn getDelimitedMode(line: []const u8) ?DelimitedMode {
    const stripped = std.mem.trim(u8, line, &std.ascii.whitespace);

    if (!std.mem.startsWith(u8, stripped, "@") or stripped.len < 2) return null;
    const end_of_first_word = std.mem.indexOfAny(u8, stripped, &std.ascii.whitespace);
    if (end_of_first_word == null) return null;

    const first_word = stripped[1..end_of_first_word.?];

    inline for (std.meta.fields(Mode)) |field| {
        if (std.mem.eql(u8, field.name, first_word)) {
            const mode: Mode = @enumFromInt(field.value);
            const maybe_delimiter: ?Delimiter = switch (mode) {
                .args, .extend => .none,
                .html,
                .zig,
                .partial,
                .markdown,
                .@"for",
                => getBlockDelimiter(mode, first_word, stripped[end_of_first_word.?..]),
                .@"if" => .{ .string = end_token },
            };
            if (maybe_delimiter) |delimiter| {
                return .{ .mode = mode, .delimiter = delimiter };
            } else {
                return null;
            }
        }
    }

    return null;
}

fn getBlockDelimiter(mode: Mode, first_word: []const u8, line: []const u8) ?Delimiter {
    var parenthesis_depth: usize = 0;
    var escaped = false;
    var double_quoted = false;
    var single_quoted = false;

    for (line, 0..) |char, index| {
        if (char == '\\' and !escaped) {
            escaped = true;
        } else if (char == '\\' and escaped) {
            escaped = false;
        } else if (char == '"' and !double_quoted and !single_quoted) {
            double_quoted = true;
        } else if (char == '"' and double_quoted and !single_quoted) {
            double_quoted = false;
        } else if (char == '\'' and !double_quoted and !single_quoted) {
            single_quoted = true;
        } else if (char == '\'' and !double_quoted and single_quoted) {
            single_quoted = false;
        } else if (mode != .@"for" and char == '(') {
            parenthesis_depth += 1;
        } else if (mode != .@"for" and char == ')') {
            parenthesis_depth -= 1;
            if (parenthesis_depth == 0) {
                if (index < line.len - 1) {
                    return delimiterFromString(util.strip(line[index + 1 ..]));
                } else return .none;
            }
        }
    }

    const stripped = util.strip(line);
    if (std.mem.lastIndexOfScalar(u8, stripped, ' ')) |index| {
        // Guaranteed to not be last character as we already stripped whitespace so no bounds
        // check needed.
        const last_word = stripped[index + 1 ..];
        return if (std.mem.eql(u8, first_word, last_word)) null else delimiterFromString(last_word);
    } else {
        return switch (mode) {
            .partial, .args, .extend => .none,
            .html, .zig, .markdown, .@"for" => delimiterFromString(stripped),
            .@"if" => .{ .string = end_token },
        };
    }
}

fn delimiterFromString(string: []const u8) Delimiter {
    return if (std.mem.eql(u8, string, "{"))
        .brace
    else
        .{ .string = string };
}

// When the current context's mode is `zig`, evaluate open and close braces to determine the
// current nesting depth. For other modes, ignore braces except for a closing brace as the
// leading character on the given line.
fn resolveNesting(line: []const u8, stack: std.ArrayList(Context)) void {
    if (stack.items.len == 0) return;

    const current_context = stack.items[stack.items.len - 1];

    switch (current_context.delimiter) {
        .eof => {},
        .none => {
            stack.items[stack.items.len - 1].depth = 0;
        },
        .brace => {
            const brace_depth: isize = getBraceDepth(current_context.mode, line);
            const current_depth = current_context.depth;
            stack.items[stack.items.len - 1].depth = current_depth + brace_depth;
        },
        .string => |delimiter_string| {
            if (util.startsWithIgnoringWhitespace(line, delimiter_string)) {
                stack.items[stack.items.len - 1].depth = 0;
            }
        },
    }
}

// Count unescaped and unquoted braces opens and closes (+1 for open, -1 for close).
fn getBraceDepth(mode: Mode, line: []const u8) isize {
    return switch (mode) {
        .zig => blk: {
            var single_quoted = false;
            var double_quoted = false;
            var escaped = false;
            var depth: isize = 0;
            for (line) |char| {
                if (char == '\\' and !escaped) {
                    escaped = true;
                } else if (escaped) {
                    escaped = false;
                } else if (char == '\'' and !single_quoted and !double_quoted) {
                    single_quoted = true;
                } else if (char == '\'' and single_quoted and !double_quoted) {
                    single_quoted = false;
                } else if (char == '"' and !single_quoted and !double_quoted) {
                    double_quoted = true;
                } else if (char == '"' and !single_quoted and double_quoted) {
                    double_quoted = false;
                } else if (char == '{') {
                    depth += 1;
                } else if (char == '}') {
                    depth -= 1;
                }
            }
            break :blk depth;
        },
        .html, .partial, .markdown, .args, .extend, .@"for" => blk: {
            if (util.firstMeaningfulChar(line)) |char| {
                if (char == '}') break :blk -1;
            }
            break :blk 0;
        },
        .@"if" => if (util.indexOfIgnoringWhitespace(line, end_token)) |index|
            @intCast(index)
        else
            0,
    };
}

// Render the function definiton and inject any provided constants.
fn renderHeader(self: *Template, writer: anytype, options: type) !void {
    var decls_buf = std.ArrayList(u8).init(self.allocator);
    defer decls_buf.deinit();

    if (@hasDecl(options, "template_constants")) {
        inline for (std.meta.fields(options.template_constants)) |field| {
            const type_str = switch (field.type) {
                []const u8, i128, f128, bool => @typeName(field.type),
                else => @compileError("Unsupported template constant type: " ++ @typeName(field.type)),
            };

            const decl_string = "const " ++ field.name ++ ": " ++ type_str ++ " = try zmpl.getConst(" ++ type_str ++ ", \"" ++ field.name ++ "\");\n"; // :(

            try decls_buf.appendSlice("    " ++ decl_string);
            try decls_buf.appendSlice("    zmpl.noop(" ++ type_str ++ ", " ++ field.name ++ ");\n");
        }
    }

    for (self.tokens.items) |token| {
        if (token.mode != .args) continue;
        if (self.args != null) {
            std.debug.print("@args pragma can only be used once per template.\n", .{});
            return error.ZmplSyntaxError;
        }
        // Force (optional) parentheses to satisfy args parser.
        const args_mode_line = try std.fmt.allocPrint(
            self.allocator,
            "({s})",
            .{util.trimParentheses(util.strip(token.mode_line["@args".len..]))},
        );

        const args = try self.root_node.parsePartialArgs(args_mode_line);
        var args_buf = std.ArrayList(u8).init(self.allocator);
        const args_writer = args_buf.writer();

        for (args) |arg| {
            if (arg.name == null) {
                std.debug.print("Error parsing `@args` pragma: `{s}`\n", .{token.mode_line});
                return error.ZmplSyntaxError;
            }
            try args_writer.print("{0s}: {1s}, ", .{ arg.name.?, arg.value });
        }
        self.args = try args_buf.toOwnedSlice();
    }

    const args = try std.mem.concat(
        self.allocator,
        u8,
        &[_][]const u8{ "slots: []const __zmpl.Data.Slot, ", self.args orelse "" },
    );
    const header = try std.fmt.allocPrint(
        self.allocator,
        \\pub fn {0s}_render{1s}(zmpl: *__zmpl.Data, Context: type, context: Context, {2s}) anyerror![]const u8 {{
        \\{3s}
        \\    var data = zmpl;
        \\    zmpl.noop(**__zmpl.Data, &data);
        \\    zmpl.noop(Context, context);
        \\    const allocator = zmpl.allocator;
        \\    var __extend: ?__Manifest.Template = null;
        \\    if (__extend) |*__capture| zmpl.noop(*__Manifest.Template, __capture);
        \\    zmpl.noop(std.mem.Allocator, allocator);
        \\    {4s}
        \\
    ,
        .{
            self.name,
            if (self.partial) "Partial" else "",
            if (self.partial) args else "",
            decls_buf.items,
            if (self.partial) "zmpl.noop([]const __zmpl.Data.Slot, slots);" else "",
        },
    );
    defer self.allocator.free(header);

    try writer.writeAll(header);
}

// Render the final component of the template function.
fn renderFooter(self: Template, writer: anytype) !void {
    try writer.writeAll(
        \\
        \\    if (__extend) |__capture| {
        \\        const __inner_content = try allocator.dupe(u8, zmpl.output_buf.items);
        \\        zmpl.content = .{ .data = zmpl.strip(__inner_content) };
        \\        zmpl.output_buf.clearRetainingCapacity();
        \\        const __content = try __capture.render(zmpl, Context, context, .{});
        \\        return __content;
        \\    } else {
        \\        return zmpl.chomp(zmpl.output_buf.items);
        \\    }
        \\}
        \\
    );
    if (self.partial) {
        try writer.writeAll(try std.fmt.allocPrint(
            self.allocator,
            \\pub fn {0s}_renderWithLayout(
            \\    layout: __zmpl.Manifest.Template,
            \\    zmpl: *__zmpl.Data,
            \\    Context: type,
            \\    context: Context,
            \\) anyerror![]const u8 {{
            \\    _ = layout;
            \\    _ = zmpl;
            \\    _ = context;
            \\    std.debug.print("Rendering a partial with a layout is not supported.\n", .{{}});
            \\    return error.ZmplError;
            \\}}
            \\
        ,
            .{self.name},
        ));
    } else {
        try writer.writeAll(try std.fmt.allocPrint(
            self.allocator,
            \\pub fn {0s}_renderWithLayout(
            \\    layout: __zmpl.Manifest.Template,
            \\    zmpl: *__zmpl.Data,
            \\    Context: type,
            \\    context: Context,
            \\) anyerror![]const u8 {{
            \\    const __inner_content = try zmpl.allocator.dupe(
            \\        u8, try {0s}_render(zmpl, Context, context)
            \\    );
            \\    zmpl.content = .{{ .data = zmpl.strip(__inner_content) }};
            \\    zmpl.output_buf.clearRetainingCapacity();
            \\    const __content = try layout.render(zmpl, Context, context, .{{}});
            \\    return zmpl.strip(__content);
            \\}}
            \\
        ,
            .{self.name},
        ));
    }
}

// Identify the token with the widest span. This token should start at zero and end at
// self.input.len
fn getRootToken(tokens: []Token) Token {
    var root_token_index: usize = 0;

    for (tokens, 0..) |token, index| {
        const root_token = tokens[root_token_index];
        if (token.start <= root_token.start and token.end > root_token.end) {
            root_token_index = index;
        }
    }

    return tokens[root_token_index];
}

fn defaultMode(self: Template) Mode {
    return switch (self.template_type) {
        .html => .html,
        .markdown => .markdown,
    };
}

const TemplateType = enum { html, markdown };

// Identify template type - currently either `html` or `markdown`.
fn templateType(path: []const u8) TemplateType {
    if (std.mem.endsWith(u8, path, ".md.zmpl")) return .markdown;
    if (std.mem.endsWith(u8, path, ".html.zmpl")) return .html;
    if (std.mem.endsWith(u8, path, ".zmpl")) return .html;

    unreachable;
}

fn debugError(self: Template, line: []const u8, line_index: usize) void {
    std.debug.print(
        "[zmpl] Error resolving braces in `{s}:{}` \n    {s}\n",
        .{ self.path, line_index, line },
    );
}

// Output information about a given token and its content to stderr.
fn debugToken(self: Template, token: Token, print_content: bool) void {
    std.debug.print("[{s}] |{}| {}->{} [{?s}]\n", .{
        @tagName(token.mode),
        token.depth,
        token.start,
        token.end,
        token.args,
    });
    if (print_content) std.debug.print("{s}\n", .{self.input[token.start..token.end]});
}

// Output a parsed tree with indentation to stderr.
fn debugTree(node: *Node, level: usize, path: []const u8) void {
    if (level == 0) {
        std.debug.print("tree: {s}\n", .{path});
    }
    for (0..level + 1) |_| std.debug.print(" ", .{});
    std.debug.print("{s} {}->{}\n", .{ @tagName(node.token.mode), node.token.start, node.token.end });
    for (node.children.items) |child_node| {
        debugTree(child_node, level + 1, path);
    }
}
