const std = @import("std");

ast: std.zig.Ast,
if_ast: std.zig.Ast.full.If,

const IfStatement = @This();

const wrap_eql_open = "try zmpl.compare(.equal, ";
const wrap_eql_close_true = ", true)";
const wrap_eql_close_false = ", false)";

pub fn parse(allocator: std.mem.Allocator, input: []const u8) !std.zig.Ast {
    const source = try std.mem.concatWithSentinel(
        allocator,
        u8,
        &.{ "_ = if ", input, "{}" },
        0,
    );
    return try std.zig.Ast.parse(allocator, source, .zig);
}

pub fn init(ast: std.zig.Ast) IfStatement {
    const tags = ast.nodes.items(.tag);

    for (tags, 0..) |tag, index| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(index);
        if (tag == .if_simple) {
            const if_simple = ast.ifSimple(node);
            return .{ .ast = ast, .if_ast = if_simple };
        }
    }
    unreachable;
}

pub fn render(self: IfStatement, writer: anytype) !void {
    const tags = self.ast.nodes.items(.tag);

    for (tags, 0..) |tag, index| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(index);
        if (tag == .if_simple) {
            try writer.writeAll("if (");
            const if_full = self.ast.ifSimple(node);

            const wrap_true = self.isWrapTrue(if_full.payload_token != null, if_full.ast.cond_expr);
            if (wrap_true) {
                try writer.writeAll(wrap_eql_open);
                try self.writeNode(if_full.ast.cond_expr, writer);
                try writer.writeAll(wrap_eql_close_true);
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

fn writeNode(self: IfStatement, node: std.zig.Ast.Node.Index, writer: anytype) !void {
    const main_tokens = self.ast.nodes.items(.main_token);
    const node_data = self.ast.nodeData(node);
    switch (self.ast.nodeTag(node)) {
        .bool_and, .bool_or => {
            const lhs = node_data.node_and_node[0];
            const rhs = node_data.node_and_node[1];
            const wrap_lhs = self.isWrapTrue(false, lhs);
            const wrap_rhs = self.isWrapTrue(false, rhs);

            if (wrap_lhs) try writer.writeAll(wrap_eql_open);
            try self.writeNode(lhs, writer);
            if (wrap_lhs) try writer.writeAll(wrap_eql_close_true);

            try writer.print(" {s} ", .{self.ast.tokenSlice(main_tokens[@intFromEnum(node)])});

            if (wrap_rhs) try writer.writeAll(wrap_eql_open);
            try self.writeNode(rhs, writer);
            if (wrap_rhs) try writer.writeAll(wrap_eql_close_true);
        },
        .bool_not => {
            try writer.writeAll(wrap_eql_open);
            try self.writeNode(node_data.node, writer);
            try writer.writeAll(wrap_eql_close_false);
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
                "{s}try zmpl.compare(.{s}, ",
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
            if (wrap_true) try writer.writeAll(wrap_eql_open);
            try self.writeNode(sub_expression, writer);
            if (wrap_true) try writer.writeAll(wrap_eql_close_true);

            try writer.writeByte(')');
        },
        .@"if" => {
            if (true) return; // TODO
            const full_if = self.ast.ifFull(node);
            try writer.writeAll("if (");

            const wrap_true = self.isWrapTrue(full_if.payload_token == null, full_if.ast.cond_expr);
            if (wrap_true) try writer.writeAll(wrap_eql_open);
            try self.writeNode(full_if.ast.cond_expr, writer);
            if (wrap_true) try writer.writeAll(wrap_eql_close_true);

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

inline fn isOperator(tag: std.zig.Ast.Node.Tag) bool {
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
fn isWrapTrue(self: IfStatement, has_payload: bool, node: std.zig.Ast.Node.Index) bool {
    if (has_payload or isOperator(self.ast.nodeTag(node))) return false;

    return true;
}

test "simple" {
    try expectIfStatement(
        "if (try zmpl.compare(.equal, try zmpl.compare(.equal, foo, true) and try zmpl.compare(.equal, bar, true), true))",
        "_ = if (foo and bar) {}",
    );
}

test "equal" {
    try expectIfStatement(
        "if (try zmpl.compare(.equal, foo, bar))",
        "_ = if (foo == bar) {}",
    );
}

test "not equal" {
    try expectIfStatement(
        "if (!try zmpl.compare(.equal, foo, bar))",
        "_ = if (foo != bar) {}",
    );
}

test "greater than" {
    try expectIfStatement(
        "if (try zmpl.compare(.greater_than, foo, bar))",
        "_ = if (foo > bar) {}",
    );
}

test "greater than or equal" {
    try expectIfStatement(
        "if (try zmpl.compare(.greater_or_equal, foo, bar))",
        "_ = if (foo >= bar) {}",
    );
}

test "less than" {
    try expectIfStatement(
        "if (try zmpl.compare(.less_than, foo, bar))",
        "_ = if (foo < bar) {}",
    );
}

test "less than or equal" {
    try expectIfStatement(
        "if (try zmpl.compare(.less_or_equal, foo, bar))",
        "_ = if (foo <= bar) {}",
    );
}

test "and with equal" {
    try expectIfStatement(
        "if (try zmpl.compare(.equal, try zmpl.compare(.equal, foo, 1) and try zmpl.compare(.equal, bar, 2), true))",
        "_ = if (foo == 1 and bar == 2) {}",
    );
}

test "or with equal" {
    try expectIfStatement(
        "if (try zmpl.compare(.equal, try zmpl.compare(.equal, foo, 1) or try zmpl.compare(.equal, bar, 2), true))",
        "_ = if (foo == 1 or bar == 2) {}",
    );
}

test "nested if" {
    try expectIfStatement(
        "if (try zmpl.compare(.equal, try zmpl.compare(.equal, (try zmpl.compare(.equal, foo, )), true) or try zmpl.compare(.equal, bar, 2), true))",
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
        "if (try zmpl.compare(.equal, foo, true))",
        "_ = if (foo) {}",
    );
}

fn expectIfStatement(expected: []const u8, input: [:0]const u8) !void {
    var ast = try std.zig.Ast.parse(std.testing.allocator, input, .zig);
    defer ast.deinit(std.testing.allocator);

    const if_statement = IfStatement.init(ast);

    var buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer buf.deinit();

    try if_statement.render(buf.writer());

    try std.testing.expectEqualStrings(expected, buf.items);
}
