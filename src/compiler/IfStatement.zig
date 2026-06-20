const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;

ast: Ast,
if_ast: Ast.full.If,

const IfStatement = @This();

const present_open = "try __core.isPresent(";
const present_close = ")";

pub fn parse(allocator: Allocator, input: []const u8) !Ast {
    const source = try std.mem.concatWithSentinel(
        allocator,
        u8,
        &.{ "_ = if ", input, "{}" },
        0,
    );
    return Ast.parse(allocator, source, .zig);
}

pub fn init(ast: Ast) IfStatement {
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, index| {
        const node: Ast.Node.Index = @enumFromInt(index);
        if (tag == .if_simple) {
            const if_simple = ast.ifSimple(node);
            return .{ .ast = ast, .if_ast = if_simple };
        }
    }
    unreachable;
}

pub fn render(self: IfStatement, writer: *Writer) !void {
    const tags = self.ast.nodes.items(.tag);

    for (tags, 0..) |tag, index| {
        const node: Ast.Node.Index = @enumFromInt(index);
        if (tag == .if_simple) {
            try writer.writeAll("if (");
            const if_full = self.ast.ifSimple(node);

            const wrap_true = self.isWrapTrue(if_full.payload_token != null, if_full.ast.cond_expr);
            if (wrap_true) {
                try writer.writeAll(present_open);
                try self.writeNode(if_full.ast.cond_expr, writer);
                try writer.writeAll(present_close);
            } else {
                try self.writeNode(if_full.ast.cond_expr, writer);
            }

            try writer.writeAll(")");
            if (if_full.payload_token) |payload_token| {
                try writer.print(" |{s}|", .{self.ast.tokenSlice(payload_token)});
            }
            return;
        }
    }
    unreachable;
}

fn writeNode(self: IfStatement, node: Ast.Node.Index, writer: *Writer) !void {
    const main_tokens = self.ast.nodes.items(.main_token);
    const node_data = self.ast.nodeData(node);
    switch (self.ast.nodeTag(node)) {
        .bool_and, .bool_or => {
            const lhs = node_data.node_and_node[0];
            const rhs = node_data.node_and_node[1];
            const wrap_lhs = self.isWrapTrue(false, lhs);
            const wrap_rhs = self.isWrapTrue(false, rhs);

            if (wrap_lhs) try writer.writeAll(present_open);
            try self.writeNode(lhs, writer);
            if (wrap_lhs) try writer.writeAll(present_close);

            try writer.print(" {s} ", .{self.ast.tokenSlice(main_tokens[@intFromEnum(node)])});

            if (wrap_rhs) try writer.writeAll(present_open);
            try self.writeNode(rhs, writer);
            if (wrap_rhs) try writer.writeAll(present_close);
        },
        .bool_not => {
            try writer.writeAll("!(");
            try writer.writeAll(present_open);
            try self.writeNode(node_data.node, writer);
            try writer.writeAll(present_close);
            try writer.writeAll(")");
        },
        .equal_equal,
        .bang_equal,
        .greater_than,
        .less_than,
        .greater_or_equal,
        .less_or_equal,
        => |tag| {
            const lhs = node_data.node_and_node[0];
            const rhs = node_data.node_and_node[1];
            const operator = switch (tag) {
                .equal_equal, .bang_equal => "equal",
                .greater_than, .less_than, .greater_or_equal, .less_or_equal => |op| @tagName(op),
                else => unreachable,
            };

            try writer.print(
                "{s}try __core.compare(.{s}, ",
                .{
                    if (tag == .bang_equal) "!" else "",
                    operator,
                },
            );
            try self.writeNode(lhs, writer);
            try writer.writeAll(", ");
            try self.writeNode(rhs, writer);
            try writer.writeAll(")");
        },
        .grouped_expression => {
            try writer.writeByte('(');

            const sub_expression = self.ast.nodeData(node).node_and_token[0];
            const wrap_true = self.isWrapTrue(false, sub_expression);
            if (wrap_true) try writer.writeAll(present_open);
            try self.writeNode(sub_expression, writer);
            if (wrap_true) try writer.writeAll(present_close);

            try writer.writeByte(')');
        },
        .@"if" => {
            if (true) return; // TODO
            const full_if = self.ast.ifFull(node);
            try writer.writeAll("if (");

            const wrap_true = self.isWrapTrue(full_if.payload_token == null, full_if.ast.cond_expr);
            if (wrap_true) try writer.writeAll(present_open);
            try self.writeNode(full_if.ast.cond_expr, writer);
            if (wrap_true) try writer.writeAll(present_close);

            try writer.writeByte(')');
            try writer.writeByte(' ');
            try self.writeNode(full_if.ast.then_expr, writer);
            try writer.writeAll(" else ");
            try self.writeNode(full_if.ast.else_expr.unwrap().?, writer);
            try writer.writeByte(')');

            if (full_if.payload_token) |payload_token| {
                try writer.print(" |{s}| ", .{self.ast.tokenSlice(payload_token)});
            }
        },
        else => |tag| {
            if (comptime false) std.debug.print("tag: {s}\n", .{@tagName(tag)});
            const span = self.ast.nodeToSpan(node);
            try writer.writeAll(self.ast.source[span.start..span.end]);
        },
    }
}

inline fn isOperator(tag: Ast.Node.Tag) bool {
    return switch (tag) {
        .equal_equal,
        .bang_equal,
        .less_than,
        .less_or_equal,
        .greater_than,
        .greater_or_equal,
        => true,
        else => false,
    };
}

// Detect if a value should be coerced to boolean `true` by wrapping the value with `zmpl.compare`:
// ```
// try zmpl.compare(.equal, value, true)
// ```
// This allows (e.g.) a `ZmplValue` boolean to evaluate to a Zig boolean for use in a regular Zig
// `if` statement.
fn isWrapTrue(self: IfStatement, has_payload: bool, node: Ast.Node.Index) bool {
    return !has_payload and !isOperator(self.ast.nodeTag(node));
}

test "simple" {
    try expectIfStatement(
        "if (try __core.isPresent(try __core.isPresent(foo) and try __core.isPresent(bar)))",
        "_ = if (foo and bar) {}",
    );
}

test "equal" {
    try expectIfStatement(
        "if (try __core.compare(.equal, foo, bar))",
        "_ = if (foo == bar) {}",
    );
}

test "not equal" {
    try expectIfStatement(
        "if (!try __core.compare(.equal, foo, bar))",
        "_ = if (foo != bar) {}",
    );
}

test "greater than" {
    try expectIfStatement(
        "if (try __core.compare(.greater_than, foo, bar))",
        "_ = if (foo > bar) {}",
    );
}

test "greater than or equal" {
    try expectIfStatement(
        "if (try __core.compare(.greater_or_equal, foo, bar))",
        "_ = if (foo >= bar) {}",
    );
}

test "less than" {
    try expectIfStatement(
        "if (try __core.compare(.less_than, foo, bar))",
        "_ = if (foo < bar) {}",
    );
}

test "less than or equal" {
    try expectIfStatement(
        "if (try __core.compare(.less_or_equal, foo, bar))",
        "_ = if (foo <= bar) {}",
    );
}

test "and with equal" {
    try expectIfStatement(
        "if (try __core.isPresent(try __core.compare(.equal, foo, 1) and try __core.compare(.equal, bar, 2)))",
        "_ = if (foo == 1 and bar == 2) {}",
    );
}

test "or with equal" {
    try expectIfStatement(
        "if (try __core.isPresent(try __core.compare(.equal, foo, 1) or try __core.compare(.equal, bar, 2)))",
        "_ = if (foo == 1 or bar == 2) {}",
    );
}

test "nested if" {
    try expectIfStatement(
        "if (try __core.isPresent(try __core.isPresent((try __core.compare(.equal, foo, ))) or try __core.compare(.equal, bar, 2)))",
        "_ = if ((foo == if (true) 1 else 0) or bar == 2) {}",
    );
}

test "if with capture" {
    try expectIfStatement(
        "if (foo) |capture|",
        "_ = if (foo) |capture| {}",
    );
}

test "simple if without capture" {
    try expectIfStatement(
        "if (try __core.isPresent(foo))",
        "_ = if (foo) {}",
    );
}

fn expectIfStatement(expected: []const u8, input: [:0]const u8) !void {
    var ast = try Ast.parse(std.testing.allocator, input, .zig);
    defer ast.deinit(std.testing.allocator);

    const if_statement: IfStatement = .init(ast);

    var buf: Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();

    try if_statement.render(&buf.writer);
    const output = try buf.toOwnedSlice();
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings(expected, output);
}
