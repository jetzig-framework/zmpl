const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const Data = @import("core").Data;

/// Direct module imports of the compiled test templates (`tests/<name>`), replacing the old
/// generated manifest aggregator. Each is a normal Zig module exposing `render` / `renderWithLayout`.
const templates = struct {
    pub const example = @import("tests/example");
    pub const object_root_layout = @import("tests/object_root_layout");
    pub const complex_example = @import("tests/complex_example");
    pub const slots = @import("tests/slots");
    pub const javascript = @import("tests/javascript");
    pub const partials_without_blocks = @import("tests/partials_without_blocks");
    pub const custom_delimiters = @import("tests/custom_delimiters");
    pub const markdown_extension = @import("tests/markdown_extension");
    pub const default_partial_arguments = @import("tests/default_partial_arguments");
    pub const escaping = @import("tests/escaping");
    pub const references_markdown = @import("tests/references_markdown");
    pub const partial_arg_type_coercion = @import("tests/partial_arg_type_coercion");
    pub const inheritance_child = @import("tests/inheritance_child");
    pub const inheritance_parent3 = @import("tests/inheritance_parent3");
    pub const reference_with_spaces = @import("tests/reference_with_spaces");
    pub const basic = @import("tests/basic");
    pub const iteration = @import("tests/iteration");
    pub const for_with_partial = @import("tests/for_with_partial");
    pub const xss = @import("tests/xss");
    pub const if_else = @import("tests/if_else");
    pub const for_with_zmpl_value_main = @import("tests/for_with_zmpl_value_main");
    pub const comments = @import("tests/comments");
    pub const for_with_if = @import("tests/for_with_if");
    pub const mix_markdown_and_zig = @import("tests/mix_markdown_and_zig");
    pub const nullable_if = @import("tests/nullable_if");
    pub const if_indented_html = @import("tests/if_indented_html");
    pub const blocks = @import("tests/blocks");
    pub const define = @import("tests/define");
};

const UserContext = struct {
    user: struct {
        name: []const u8,
        email: []const u8,
    },
};

const AuthContext = struct {
    user: struct { email: []const u8 },
    auth: struct { token: []const u8 },
};

const Context = struct { foo: []const u8 = "default" };

const t = std.testing;
test "readme example" {
    var data: Data(AuthContext) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    data.context.user.email = "user@example.com";
    data.context.auth.token = "abc123-456-def";

    const output = try templates.example.render(&data);

    try expectEqualStrings(
        \\<!-- Zig mode for template logic -->
        \\    <span>Zmpl is simple!</span>
        \\
        \\<!-- Easy data lookup syntax -->
        \\<div>Email: user@example.com</div>
        \\<div>Token: abc123-456-def</div>
        \\
        \\<!-- Partials --><span>An example partial</span>
        \\
        \\<!-- Partials with positional args --><a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>
        \\
        \\<!-- Partials with keyword args --><a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>
        \\
        \\<!-- Partials with slots --><a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>
        \\        <div class="slot-0"><a href="https://example.com/auth/abc123-456-def">Sign in</a></div>        <div class="slot-1"><a href="https://example.com/unsubscribe/abc123-456-def">Unsubscribe</a></div>
        \\
        \\<div>
        \\<h1>Built-in markdown support</h1>
        \\<ul>
        \\  <li><a href="https://www.jetzig.dev/">jetzig.dev</a></li>
        \\</ul>
        \\</div>
        \\
    , output);
}

test "object passing to partial" {
    var data: Data(UserContext) = .init(t.io, t.allocator, .{
        .user = .{
            .name = "John Doe",
            .email = "john@example.com",
        },
    });
    defer data.deinit();

    const output = try templates.object_root_layout.render(&data);

    try expectEqualStrings(
        \\<h1>User</h1>
        \\<div>User email: john@example.com</div>
        \\<div>User name: John Doe</div>
        \\
    , output);
}

test "complex example" {
    var data: Data(struct {
        user: struct { email: []const u8 },
        auth: struct { token: []const u8 },
        class: []const u8,
    }) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    data.context.user.email = "user@example.com";
    data.context.auth.token = "abc123-456-def";
    data.context.class = "my-css-class";

    const output = try templates.complex_example.render(&data);

    try expectEqualStrings(
        \\    <div>hello</div>    <span class="foo
        \\                 bar
        \\                 baz qux"
        \\    >      user@example.com    </span><h2>Some slots:</h2>
        \\<div>
        \\Slots count: 2
        \\bar: 100
        \\baz: positional
        \\qux: true
        \\
        \\      qux was true !
        \\
        \\    <span><div>slot 1</div></span>    <span><div>slot 2</div></span>
        \\</div>
        \\<h2>Some slots:</h2>
        \\<div>
        \\Slots count: 2
        \\bar: 10
        \\baz: hello
        \\qux: true
        \\
        \\      qux was true !
        \\
        \\    <span><div>slot 3</div></span>    <span><div>slot 4</div></span>
        \\</div>
        \\<h2>Some slots:</h2>
        \\<div>
        \\Slots count: 3
        \\bar: 5
        \\baz: goodbye
        \\qux: false
        \\
        \\      qux was false :(
        \\
        \\    <span><div>slot 5</div></span>    <span><div>slot 6</div></span>    <span><div>user@example.com</div></span>
        \\</div>
        \\
        \\    <span>Blah partial content</span>
        \\
        \\
        \\<div class="foo
        \\            bar
        \\            my-css-class
        \\            baz"></div><div>
        \\<ul>
        \\  <li>foo</li>
        \\  <li>bar</li>
        \\  <li>user@example.com</li>
        \\</ul>
        \\</div>
        \\      <span>hello</span>
        \\Bar partial content
        \\
        \\
        \\hello
        \\
    , output);
}

test "direct rendering of slots (render [][]const u8 as line-separated string)" {
    var data: Data(struct {}) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    const output = try templates.slots.render(&data);

    try expectEqualStrings(
        \\<div>
        \\<h2>Slots:</h2>
        \\<span>slot 1</span>
        \\<span>slot 2</span>
        \\<span>slot 3</span>
        \\</div>
        \\
    , output);
}

test "javascript" {
    var data: Data(struct {}) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    const output = try templates.javascript.render(&data);
    try expectEqualStrings(
        \\
        \\  <span>{ is my favorite character</span>
        \\  <script>
        \\    function foobar() {
        \\      console.log("hello");
        \\    }
        \\  </script>
        \\
    , output);
}

test "partials without blocks" {
    var data: Data(struct {}) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    const output = try templates.partials_without_blocks.render(&data);
    try expectEqualStrings(
        \\    <span>Blah partial content</span>
        \\      <div>bar</div>    <span>Blah partial content</span>
        \\
    , output);
}

test "custom delimiters" {
    var data: Data(struct {}) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    const output = try templates.custom_delimiters.render(&data);
    try expectEqualStrings(
        \\<div>
        \\<h1>Built-in markdown support</h1>
        \\<ul>
        \\  <li><a href="https://www.jetzig.dev/">jetzig.dev</a></li>
        \\</ul>
        \\</div>
        \\
        \\        <script>
        \\          const foo = () => {
        \\            console.log("hello");
        \\          };
        \\        </script>
        \\
    , output);
}

test ".md.zmpl extension" {
    var data: Data(struct {}) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    const output = try templates.markdown_extension.render(&data);
    try expectEqualStrings(
        \\<div>
        \\<h1>Hello</h1>
        \\</div>
        \\
    , output);
}

test "default partial arguments" {
    var data: Data(struct {}) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    const output = try templates.default_partial_arguments.render(&data);
    try expectEqualStrings(
        \\bar, default value
        \\
    , output);
}

test "escaping (HTML and backslash escaping" {
    var data: Data(struct {}) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    const output = try templates.escaping.render(&data);
    try expectEqualStrings(
        \\<div>
        \\<pre style="font-family: Monospace;" class="language-html">
        \\<code>
        \\&lt;div&gt;
        \\  @partial foo("bar")
        \\&lt;/div&gt;
        \\</code>
        \\</pre>
        \\</div>
        \\
    , output);
}

test "references combined with markdown" {
    var data: Data(struct {
        url: []const u8,
        title: []const u8,
    }) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    data.context.url = "https://jetzig.dev/";
    data.context.title = "jetzig.dev";

    const output = try templates.references_markdown.render(&data);
    try expectEqualStrings(
        \\<div>
        \\<h1>Test</h1>
        \\<p>  <a href="https://jetzig.dev/">jetzig.dev</a></p>
        \\</div>
        \\
    , output);
}

test "partial arg type coercion" {
    var data: Data(struct {
        foo: u16,
        bar: f32,
        baz: []const u8,
    }) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    data.context.foo = 100;
    data.context.bar = 123.456;
    data.context.baz = "qux";

    const output = try templates.partial_arg_type_coercion.render(&data);
    try expectEqualStrings(
        \\100
        \\123.456
        \\qux
        \\
    , output);
}

test "inheritance" {
    var data: Data(struct {}) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    const output = try templates.inheritance_child.renderWithLayout(
        templates.inheritance_parent3,
        &data,
    );
    try expectEqualStrings(
        \\<h2>Parent 1</h2>
        \\<div class="content-1">
        \\  <h2>Parent 2</h2>
        \\<div class="content-2">
        \\  <h3>Parent 3</h3>
        \\<div class="content-3">
        \\  <span>Content</span>
        \\</div>
        \\</div>
        \\</div>
    , output);
}

test "root init" {
    var data: Data(AuthContext) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    data.context.user.email = "user@example.com";
    data.context.auth.token = "abc123-456-def";

    const output = try templates.example.render(&data);

    try expectEqualStrings(
        \\<!-- Zig mode for template logic -->
        \\    <span>Zmpl is simple!</span>
        \\
        \\<!-- Easy data lookup syntax -->
        \\<div>Email: user@example.com</div>
        \\<div>Token: abc123-456-def</div>
        \\
        \\<!-- Partials --><span>An example partial</span>
        \\
        \\<!-- Partials with positional args --><a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>
        \\
        \\<!-- Partials with keyword args --><a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>
        \\
        \\<!-- Partials with slots --><a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>
        \\        <div class="slot-0"><a href="https://example.com/auth/abc123-456-def">Sign in</a></div>        <div class="slot-1"><a href="https://example.com/unsubscribe/abc123-456-def">Unsubscribe</a></div>
        \\
        \\<div>
        \\<h1>Built-in markdown support</h1>
        \\<ul>
        \\  <li><a href="https://www.jetzig.dev/">jetzig.dev</a></li>
        \\</ul>
        \\</div>
        \\
    , output);
}

test "reference stripping" {
    var data: Data(struct {
        message: []const u8,
    }) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    data.context.message = "hello";

    const output = try templates.reference_with_spaces.render(&data);

    try expectEqualStrings(
        \\<div>hello</div>
        \\
    , output);
}

test "inferred type in put/append" {
    const TestEnum = enum { field_a, field_b };

    const StructC = struct {
        a: i32,
        enum_val: TestEnum,
    };

    const TestStruct = struct {
        a: f64,
        nested_struct: *StructC,
    };

    var nested_struct = StructC{
        .a = 5,
        .enum_val = TestEnum.field_b,
    };

    var data: Data(struct {
        foo: []const u8 = "hello",
        bar: i128 = 10,
        baz: f128 = 100.0,
        qux: bool = true,
        test_struct: TestStruct,
        optional: ?i32 = null,
    }) = .init(t.io, t.allocator, .{
        .test_struct = .{
            .a = 2e0,
            .nested_struct = &nested_struct,
        },
    });
    defer data.deinit();

    const output = try templates.basic.render(&data);
    try expectEqualStrings(
        \\hello
        \\10
        \\100
        \\2
        \\5
        \\field_b    <span>qux was true</span>
        \\
    , output);
}

test "toJson()" {
    var data: Data(struct {
        foo: []const u8 = "bar",
        baz: []const u8 = "qux",
    }) = .init(t.io, t.allocator, .{});
    defer data.deinit();

    const json = try data.interface.toJsonAlloc(data.context, .{ .whitespace = .minified });
    try expectEqualStrings(
        \\{"foo":"bar","baz":"qux"}
    , json);
}

test "iteration" {
    var data: Data(struct {
        foo: []const []const u8,
        bar: []const []const u8,
        objects: []const struct { foo: []const u8 },
    }) = .init(t.io, t.allocator, .{
        .foo = &.{ "baz", "qux", "quux" },
        .bar = &.{ "corge", "grault", "garply" },
        .objects = &.{ .{ .foo = "bar" }, .{ .foo = "corge" } },
    });
    defer data.deinit();

    const output = try templates.iteration.render(&data);
    try expectEqualStrings(
        \\
        \\  <div>baz</div>
        \\  <div>qux</div>
        \\  <div>quux</div>
        \\
        \\  <div>corge</div>
        \\  <div>grault</div>
        \\  <div>garply</div>
        \\
        \\
        \\  <div>waldo</div>
        \\  <div>fred</div>
        \\  <div>plugh</div>
        \\
        \\  <div>0: baz</div>
        \\  <div>1: qux</div>
        \\  <div>2: quux</div>
        \\
        \\  <div>bar</div>
        \\  <div>corge</div>
        \\
        \\
        \\  <div>bar</div>
        \\  <div>baz</div>
        \\
    , output);
}

// test "datetime format" {
//     var data: Data(struct {}) = .init(t.io, t.allocator, undefined);
//     defer data.deinit();
//
//     var root = try data.root(.object);
//
//     try root.put("foo", "2024-09-24T19:30:35Z");
//     var bar = try data.array();
//     try bar.append(.{ .baz = "2024-09-27T20:19:14Z" });
//     try root.put("bar", bar);
//
//     const template = zmpl.find("datetime_format") orelse return expect(false);
//     const output = try template.render(&data, &.{}, .{});
//     try expectEqualStrings(
//         \\<div>Tue Sep 24 19:30:35 2024</div>
//         \\<div>2024-09-24</div>
//         \\
//         \\  <div>Fri Sep 27 20:19:14 2024</div>
//         \\
//     , output);
// }
//
// test "datetime" {
//     var data: Data(struct {}) = .init(t.io, t.allocator, undefined);
//     defer data.deinit();
//
//     var root = try data.root(.object);
//     const datetime = try jetcommon.types.DateTime.parse("2024-09-27T21:29:51Z");
//     try root.put("foo", datetime);
//     const foo = root.getT(.datetime, "foo") orelse return std.testing.expect(false);
//     try expect(datetime.eql(foo));
// }

test "for with partial" {
    var data: Data(struct {
        things: []const struct { foo: []const u8, bar: []const u8 },
    }) = .init(t.io, t.allocator, .{
        .things = &.{
            .{ .foo = "foo1", .bar = "bar1" },
            .{ .foo = "foo2", .bar = "bar2" },
        },
    });
    defer data.deinit();

    const output = try templates.for_with_partial.render(&data);
    try expectEqualStrings(
        \\foo1: bar1
        \\<div>foo1</div>
        \\<div>bar1</div>
        \\foo2: bar2
        \\<div>foo2</div>
        \\<div>bar2</div>
        \\
    , output);
}

test "xss sanitization/raw formatter" {
    var data: Data(struct {
        foo: []const u8,
    }) = .init(t.io, t.allocator, .{
        .foo = "<script>alert(':)');</script>",
    });
    defer data.deinit();

    const output = try templates.xss.render(&data);
    try expectEqualStrings(
        \\&lt;script&gt;alert(&#039;:)&#039;);&lt;/script&gt;
        \\<script>alert(':)');</script>
        \\
    , output);
}

test "if/else" {
    var data: Data(struct {
        foo: struct {
            bar: i64,
            baz: i64,
            qux: struct { quux: i64 },
            captured: ?[]const u8,
            corge: []const u8,
            truthy: bool,
            falsey: bool,
            missing: ?[]const u8,
            nonexistent: ?[]const u8,
            optional: ?i64,
        },
    }) = .initContext(t.io, t.allocator, .{
        .foo = .{
            .bar = 1,
            .baz = 3,
            .qux = .{ .quux = 4 },
            .captured = "value",
            .corge = "I am corge",
            .truthy = true,
            .falsey = false,
            .missing = null,
            .nonexistent = null,
            .optional = 42,
        },
    });
    defer data.deinit();

    const output = try templates.if_else.render(&data);
    try expectEqualStrings(
        \\
        \\    expected here
        \\        nested expected here
        \\        foo.bar is 1
        \\            double nested expected here
        \\            foo.qux.quux is 4
        \\
        \\
        \\
        \\
        \\  expected: `missing` is not here
        \\
        \\  expected: captured value
        \\
        \\
        \\  corge says "I am corge"
        \\
        \\  corge confirms "I am corge"
        \\
        \\  expected: else
        \\
        \\  bar is 1
        \\
        \\  optional is 42
        \\
        \\  expected truth
        \\
        \\  another expected truth
        \\
    , output);
}

test "for with zmpl value" {
    var data: Data(struct {
        foo: []const []const u8,
    }) = .init(t.io, t.allocator, .{
        .foo = &.{ "bar", "baz", "qux" },
    });
    defer data.deinit();

    const output = try templates.for_with_zmpl_value_main.render(&data);
    try expectEqualStrings(
        \\
        \\    bar
        \\    baz
        \\    qux
        \\    bar
        \\    baz
        \\    qux
        \\
    , output);
}

test "comments" {
    var data: Data(struct {}) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    const output = try templates.comments.render(&data);
    try expectEqualStrings(
        \\
        \\
        \\<div>uncommented</div>
        \\
    , output);
}

test "for with if" {
    var data: Data(struct {
        foo: bool,
        things: []const struct { foo: []const u8, bar: []const u8, time: []const u8 },
    }) = .init(t.io, t.allocator, .{
        .foo = true,
        .things = &.{
            .{ .foo = "baz", .bar = "qux", .time = "2024-11-24T18:50:23Z" },
            .{ .foo = "quux", .bar = "corge", .time = "2024-11-24T18:51:23Z" },
        },
    });
    defer data.deinit();

    const output = try templates.for_with_if.render(&data);
    try expectEqualStrings(
        \\<div>foo: bar
        \\
        \\    <hr/>
        \\    <table class="table-auto">
        \\        <tbody>
        \\            <tr>
        \\                <td>baz: qux
        \\                </td>
        \\                <td>qux: baz
        \\
        \\                </td>
        \\            </tr>
        \\
        \\            <tr>
        \\                <td>quux: corge
        \\                </td>
        \\                <td>corge: quux
        \\
        \\                </td>
        \\            </tr>
        \\
        \\        </tbody>
        \\    </table>
        \\</div>
        \\
    , output);
}

test "mix mardown and zig" {
    var data: Data(struct {
        foo: bool,
        things: []const struct { foo: []const u8, bar: []const u8, time: []const u8 },
    }) = .init(t.io, t.allocator, .{
        .foo = true,
        .things = &.{
            .{ .foo = "baz", .bar = "qux", .time = "2024-11-24T18:50:23Z" },
            .{ .foo = "quux", .bar = "corge", .time = "2024-11-24T18:51:23Z" },
        },
    });
    defer data.deinit();

    // FIXME: This doesn't work exactly how we want - the for loop now correctly reverts back to
    // markdown (i.e. the parent's mode) but the list gets broken into three parts intsead of a
    // single list.
    const output = try templates.mix_markdown_and_zig.render(&data);
    try expectEqualStrings(
        \\<div>
        \\<h1>Header</h1>
        \\<ul>
        \\  <li>list item 1</li>
        \\  <li>list item 2</li>
        \\</ul>
        \\</div>
        \\<div>
        \\<ul>
        \\  <li>qux</li>
        \\</ul>
        \\</div>
        \\<div>
        \\<ul>
        \\  <li>corge</li>
        \\</ul>
        \\</div>
        \\<div>
        \\<ul>
        \\  <li>last item</li>
        \\  <li>qux</li>
        \\</ul>
        \\</div>
        \\
    , output);
}

test "nullable if" {
    // Test for nullable if statements:
    // - null and empty strings should be falsey
    // - non-empty strings should be truthy

    // Test with null value - should be falsey
    {
        var data: Data(struct {
            clip: struct { notes: ?[]const u8 },
        }) = .init(t.io, t.allocator, .{ .clip = .{ .notes = null } });
        defer data.deinit();

        const output = try templates.nullable_if.render(&data);
        try expectEqualStrings("\nThe value is null\n", output);
    }

    // Test with non-null, non-empty string - should be truthy
    {
        var data: Data(struct {
            clip: struct { notes: ?[]const u8 },
        }) = .init(t.io, t.allocator, .{ .clip = .{ .notes = "Some notes" } });
        defer data.deinit();

        const output = try templates.nullable_if.render(&data);
        // Non-empty string should correctly evaluate as truthy
        try expectEqualStrings("\nThe value is not null\n", output);
    }

    // Test with empty string - should be falsey like null
    {
        var data: Data(struct {
            clip: struct { notes: ?[]const u8 },
        }) = .init(t.io, t.allocator, .{ .clip = .{ .notes = "" } });
        defer data.deinit();

        const output = try templates.nullable_if.render(&data);
        try expectEqualStrings("\nThe value is null\n", output);
    }
}

test "if statement with indented HTML - if branch" {
    var data: Data(struct {
        user: struct { is_logged_in: bool, display_name: []const u8 = "" },
    }) = .init(t.io, t.allocator, .{
        .user = .{ .is_logged_in = true, .display_name = "TestUser" },
    });
    defer data.deinit();

    const output = try templates.if_indented_html.render(&data);
    try expectEqualStrings(
        \\
        \\                <div class="d-none d-md-block ms-2 dropdown">
        \\                    <button class="btn btn-outline-secondary btn-sm dropdown-toggle" type="button" id="userMenuDropdown" data-bs-toggle="dropdown" aria-expanded="false">
        \\                        TestUser
        \\                    </button>
        \\                    <ul class="dropdown-menu dropdown-menu-end" aria-labelledby="userMenuDropdown">
        \\                        <li><a class="dropdown-item" href="/profile"><i class="bi bi-person me-2"></i>Profile</a></li>
        \\                        <li><hr class="dropdown-divider"></li>
        \\                        <li><a class="dropdown-item" href="/logout"><i class="bi bi-box-arrow-right me-2"></i>Log out</a></li>
        \\                    </ul>
        \\                </div>
        \\
    , output);
}

test "if statement with indented HTML - else branch" {
    var data: Data(struct {
        user: struct { is_logged_in: bool, display_name: []const u8 = "" },
    }) = .init(t.io, t.allocator, .{
        .user = .{ .is_logged_in = false },
    });
    defer data.deinit();

    const output = try templates.if_indented_html.render(&data);
    try expectEqualStrings(
        \\
        \\                <div class="d-none d-md-flex align-items-center ms-2">
        \\                    <a href="/login" class="btn btn-outline-secondary btn-sm">Log in</a>
        \\                    <a href="/register" class="btn btn-primary btn-sm ms-2">Sign up</a>
        \\                </div>
        \\
    , output);
}

test "blocks" {
    var data: Data(struct {}) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    // `@block head { ... }` now renders in place in its own template and is exposed as a
    // `pub fn head(data_struct)` on the module (no more layout-pull / manifest aggregator).
    try std.testing.expect(@hasDecl(templates.blocks, "head"));

    const output = try templates.blocks.render(&data);
    try expectEqual(9, std.mem.count(u8, output, "<link rel=\"stylesheet\""));
}

test "define + block call" {
    var data: Data(struct {}) = .init(t.io, t.allocator, undefined);
    defer data.deinit();

    // `@define greeting(name) { ... }` becomes a `pub fn greeting(data_struct, name)`; `@block
    // greeting("World")` calls it and renders in place, reusable with different args.
    try std.testing.expect(@hasDecl(templates.define, "greeting"));

    const output = try templates.define.render(&data);
    try std.testing.expect(std.mem.indexOf(u8, output, "Hi World!") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Hi Zmpl!") != null);
}
