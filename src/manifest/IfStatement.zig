const std = @import("std");

ast: std.zig.Ast,
if_ast: std.zig.Ast.full.If,

const IfStatement = @This();

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
        const node: std.zig.Ast.Node.Index = @intCast(index);
        if (tag == .if_simple) {
            const if_simple = ast.ifSimple(node);
            return .{ .ast = ast, .if_ast = if_simple };
        }
    }
    unreachable;
}

pub fn render(self: IfStatement, writer: anytype) !void {
    const tags = self.ast.nodes.items(.tag);
    const data = self.ast.nodes.items(.data);

    for (tags, 0..) |tag, index| {
        const node: std.zig.Ast.Node.Index = @intCast(index);
        if (tag == .if_simple) {
            try writer.writeAll("if (");
            try self.writeNode(data[node].lhs, writer);
            try writer.writeAll(")");
            const components = self.ast.ifSimple(node);
            if (components.payload_token) |payload_token| {
                try writer.print(" |{s}|", .{self.ast.tokenSlice(payload_token)});
            }
            return;
        }
    }
    unreachable;
}

fn writeNode(self: IfStatement, node: std.zig.Ast.Node.Index, writer: anytype) !void {
    const tags = self.ast.nodes.items(.tag);
    const main_tokens = self.ast.nodes.items(.main_token);
    const data = self.ast.nodes.items(.data);
    switch (tags[node]) {
        .bool_and, .bool_or => {
            try self.writeNode(data[node].lhs, writer);
            try writer.print(" {s} ", .{self.ast.tokenSlice(main_tokens[node])});
            try self.writeNode(data[node].rhs, writer);
        },
        .equal_equal,
        .bang_equal,
        .greater_than,
        .less_than,
        .greater_or_equal,
        .less_or_equal,
        => |tag| {
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
            try self.writeNode(data[node].lhs, writer);
            try writer.writeAll(", ");
            try self.writeNode(data[node].rhs, writer);
            try writer.writeAll(")");
        },
        .grouped_expression => {
            try writer.writeByte('(');
            try self.writeNode(data[node].lhs, writer);
            try writer.writeByte(')');
        },
        .@"if" => {
            try writer.writeAll("if (");
            try self.writeNode(data[node].lhs, writer);
            try writer.writeByte(')');
            const extra = self.ast.extraData(data[node].rhs, std.zig.Ast.Node.If);
            try writer.writeByte(' ');
            try self.writeNode(extra.then_expr, writer);
            try writer.writeAll(" else ");
            try self.writeNode(extra.else_expr, writer);
            try writer.writeByte(')');

            const components = self.ast.ifFull(node);
            if (components.payload_token) |payload_token| {
                try writer.print(" |{s}| ", .{self.ast.tokenSlice(payload_token)});
            }
        },
        else => |tag| {
            if (false) std.debug.print("tag: {s}\n", .{@tagName(tag)});
            const span = self.ast.nodeToSpan(node);
            try writer.writeAll(self.ast.source[span.start..span.end]);
        },
    }
}

test "simple" {
    try expectIfStatement(
        "if (foo and bar)",
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
        "if (try zmpl.compare(.equal, foo, 1) and try zmpl.compare(.equal, bar, 2))",
        "_ = if (foo == 1 and bar == 2) {}",
    );
}

test "or with equal" {
    try expectIfStatement(
        "if (try zmpl.compare(.equal, foo, 1) or try zmpl.compare(.equal, bar, 2))",
        "_ = if (foo == 1 or bar == 2) {}",
    );
}

test "nested if" {
    try expectIfStatement(
        "if ((try zmpl.compare(.equal, foo, if (true) 1 else 0))) or try zmpl.compare(.equal, bar, 2))",
        "_ = if ((foo == if (true) 1 else 0) or bar == 2) {}",
    );
}

test "if with capture" {
    try expectIfStatement(
        "if (foo) |capture|",
        "_ = if (foo) |capture| {}",
    );
}

fn expectIfStatement(expected: []const u8, input: [:0]const u8) !void {
    var ast = try std.zig.Ast.parse(std.testing.allocator, input, .zig);
    defer ast.deinit(std.testing.allocator);

    const if_statement = IfStatement.init(ast);

    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();

    try if_statement.render(buf.writer());

    try std.testing.expectEqualStrings(expected, buf.items);
}
