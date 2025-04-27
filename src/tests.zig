const std = @import("std");
const zmpl = @import("zmpl");
const jetcommon = @import("jetcommon");

const Context = struct { foo: []const u8 = "default" };

test "readme example" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var body = try data.object();
    var user = try data.object();
    var auth = try data.object();

    try user.put("email", data.string("user@example.com"));
    try auth.put("token", data.string("abc123-456-def"));

    try body.put("user", user);
    try body.put("auth", auth);

    if (zmpl.find("example")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});

        try std.testing.expectEqualStrings(
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
            \\<div><h1>Built-in markdown support</h1>
            \\<ul><li><a href="https://www.jetzig.dev/">jetzig.dev</a></li></ul></div>
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "complex example" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var body = try data.object();
    var user = try data.object();
    var auth = try data.object();

    try user.put("email", data.string("user@example.com"));
    try auth.put("token", data.string("abc123-456-def"));

    try body.put("class", data.string("my-css-class"));
    try body.put("user", user);
    try body.put("auth", auth);

    if (zmpl.find("complex_example")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});

        try std.testing.expectEqualStrings(
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
            \\            baz"></div><div><ul><li>foo</li><li>bar</li><li>user@example.com</li></ul></div>      <span>hello</span>
            \\Bar partial content
            \\
            \\
            \\hello
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "direct rendering of slots (render [][]const u8 as line-separated string)" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("slots")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
            \\<div>
            \\<h2>Slots:</h2>
            \\<span>slot 1</span>
            \\<span>slot 2</span>
            \\<span>slot 3</span>
            \\</div>
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "javascript" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("javascript")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
            \\
            \\  <span>{ is my favorite character</span>
            \\  <script>
            \\    function foobar() {
            \\      console.log("hello");
            \\    }
            \\  </script>
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "partials without blocks" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("partials_without_blocks")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
            \\    <span>Blah partial content</span>
            \\      <div>bar</div>    <span>Blah partial content</span>
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "custom delimiters" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("custom_delimiters")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
            \\<div><h1>Built-in markdown support</h1>
            \\<ul><li><a href="https://www.jetzig.dev/">jetzig.dev</a></li></ul></div>
            \\        <script>
            \\          const foo = () => {
            \\            console.log("hello");
            \\          };
            \\        </script>
            \\     
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test ".md.zmpl extension" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("markdown_extension")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
            \\<div><h1>Hello</h1>
            \\</div>
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "default partial arguments" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("default_partial_arguments")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
            \\bar, default value
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "escaping (HTML and backslash escaping" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("escaping")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
            \\<div><pre class="language-html" style="font-family: Monospace;"><code>&lt;div&gt;
            \\  @partial foo("bar")
            \\&lt;/div&gt;</code></pre></div>
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "references combined with markdown" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var object = try data.object();
    try object.put("url", data.string("https://jetzig.dev/"));
    try object.put("title", data.string("jetzig.dev"));

    if (zmpl.find("references_markdown")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
            \\<div><h1>Test</h1>
            \\
            \\<p>  <a href="https://jetzig.dev/">jetzig.dev</a></p>
            \\</div>
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "partial arg type coercion" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var object = try data.object();
    try object.put("foo", data.integer(100));
    try object.put("bar", data.float(123.456));
    try object.put("baz", data.string("qux"));

    if (zmpl.find("partial_arg_type_coercion")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
            \\100
            \\123.456
            \\qux
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "inheritance" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("inheritance_child")) |template| {
        const output = try template.render(
            &data,
            Context,
            .{},
            &.{},
            .{ .layout = zmpl.find("inheritance_parent3") },
        );
        try std.testing.expectEqualStrings(
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
    } else {
        try std.testing.expect(false);
    }
}

test "root init" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var root = try data.root(.object);
    var user = try data.object();
    var auth = try data.object();

    try user.put("email", data.string("user@example.com"));
    try auth.put("token", data.string("abc123-456-def"));

    try root.put("user", user);
    try root.put("auth", auth);

    if (zmpl.find("example")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});

        try std.testing.expectEqualStrings(
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
            \\<div><h1>Built-in markdown support</h1>
            \\<ul><li><a href="https://www.jetzig.dev/">jetzig.dev</a></li></ul></div>
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "reference stripping" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var root = try data.root(.object);
    try root.put("message", data.string("hello"));

    if (zmpl.find("reference_with_spaces")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});

        try std.testing.expectEqualStrings(
            \\<div>hello</div>
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "inferred type in put/append" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    const TestEnum = enum { field_a, field_b };
    const StructC = struct {
        a: i32,
        @"enum": TestEnum,
    };
    const TestStruct = struct {
        a: f64,
        nested_struct: *StructC,
    };
    var nested_struct = StructC{
        .a = 5,
        .@"enum" = TestEnum.field_b,
    };
    const test_struct = TestStruct{
        .a = 2e0,
        .nested_struct = &nested_struct,
    };
    const optional: ?i32 = null;

    var root = try data.root(.object);
    try root.put("foo", "hello");
    try root.put("bar", 10);
    try root.put("baz", 100.0);
    try root.put("qux", true);
    try root.put("test_struct", test_struct);
    try root.put("optional", optional);

    if (zmpl.find("basic")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});

        try std.testing.expectEqualStrings(
            \\hello
            \\10
            \\100
            \\2
            \\5
            \\field_b    <span>qux was true</span>
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "getT(.array, ...) and getT(.object, ...)" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();
    var root = try data.root(.object);
    var obj = try data.object();
    var arr = try data.array();
    try arr.append(1);
    try arr.append(2);

    try obj.put("a", 1);
    try obj.put("b", 2e0);

    try root.put("test_struct", obj);
    try root.put("test_list", arr);

    const res_arr = root.getT(.array, "test_list").?;
    const res_obj = root.getT(.object, "test_struct").?;
    try std.testing.expectEqual(&arr.array, res_arr);
    try std.testing.expectEqual(&obj.object, res_obj);
}

test "object.remove(...)" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();
    var obj = try data.object();

    try obj.put("a", try data.object());
    try obj.put("b", try data.object());

    try std.testing.expect(obj.object.remove("a"));
    try std.testing.expectEqual(null, obj.getT(.object, "a"));
    try std.testing.expect(obj.getT(.object, "b") != null);
}

test "getStruct from object" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();
    var root = try data.root(.object);
    var obj = try data.object();
    var nested_obj = try data.object();

    const TestEnum = enum {
        option_a,
        option_b,
    };
    const NestedObj = struct { c: i128 };
    const TestStruct = struct {
        fied_a: i128,
        field_b: f128,
        enum_val: TestEnum,
        str: []const u8,
        nested_obj: NestedObj,
    };

    try obj.put("fied_a", 1);
    try obj.put("field_b", 2e0);
    try obj.put("enum_val", "option_a");
    try obj.put("str", "fdfs");
    try nested_obj.put("c", 1);
    try obj.put("nested_obj", nested_obj);
    try root.put("test_struct", obj);

    const tested_struct = root.getT(.object, "test_struct").?.getStruct(TestStruct);

    const nested_struct = NestedObj{ .c = 1 };
    const expected = TestStruct{
        .fied_a = 1,
        .field_b = 2,
        .enum_val = TestEnum.option_a,
        .str = "fdfs",
        .nested_obj = nested_struct,
    };
    try std.testing.expectEqual(expected, tested_struct.?);
}

test "Array.items()" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();
    var array = try data.array();
    try array.append("foo");
    try array.append("bar");

    for (array.array.items(), &[_][]const u8{ "foo", "bar" }) |item, expected| {
        try std.testing.expectEqualStrings(item.string.value, expected);
    }
}

test "Object.items()" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();
    var object = try data.object();
    try object.put("foo", "bar");
    try object.put("baz", "qux");

    for (
        object.object.items(),
        &[_][]const u8{ "foo", "baz" },
        &[_][]const u8{ "bar", "qux" },
    ) |item, expected_key, expected_value| {
        try std.testing.expectEqualStrings(item.key, expected_key);
        try std.testing.expectEqualStrings(item.value.string.value, expected_value);
    }
}

test "toJson()" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();
    var object = try data.object();
    try object.put("foo", "bar");
    try object.put("baz", "qux");

    try std.testing.expectEqualStrings(
        try data.toJson(),
        \\{"foo":"bar","baz":"qux"}
        \\
        ,
    );
}

test "put slice" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();
    var root = try data.root(.object);

    const T = struct { foo: []const u8, bar: []const u8 };
    var array = std.ArrayList(T).init(std.testing.allocator);
    try array.append(.{ .foo = "abc", .bar = "def" });
    try array.append(.{ .foo = "ghi", .bar = "jkl" });

    const slice = try array.toOwnedSlice();
    defer std.testing.allocator.free(slice);

    try root.put("slice", slice);

    try std.testing.expectEqualStrings((data.ref("slice.0.foo")).?.string.value, "abc");
    try std.testing.expectEqualStrings((data.ref("slice.0.bar")).?.string.value, "def");
    try std.testing.expectEqualStrings((data.ref("slice.1.foo")).?.string.value, "ghi");
    try std.testing.expectEqualStrings((data.ref("slice.1.bar")).?.string.value, "jkl");
}

test "iteration" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var root = try data.root(.object);
    var array = try data.array();
    for ([_][]const u8{ "baz", "qux", "quux" }) |item| try array.append(data.string(item));

    try root.put("foo", array);
    try root.put("bar", [_][]const u8{ "corge", "grault", "garply" });

    var objects = try data.array();
    try objects.append(.{ .foo = "bar" });
    try objects.append(.{ .foo = "corge" });
    try root.put("objects", objects);

    if (zmpl.find("iteration")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
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
    } else {
        try std.testing.expect(false);
    }
}

test "datetime format" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var root = try data.root(.object);

    try root.put("foo", "2024-09-24T19:30:35Z");
    var bar = try data.array();
    try bar.append(.{ .baz = "2024-09-27T20:19:14Z" });
    try root.put("bar", bar);

    if (zmpl.find("datetime_format")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
            \\<div>Tue Sep 24 19:30:35 2024</div>
            \\<div>2024-09-24</div>
            \\
            \\  <div>Fri Sep 27 20:19:14 2024</div>
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "datetime" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var root = try data.root(.object);
    const datetime = try jetcommon.types.DateTime.parse("2024-09-27T21:29:51Z");
    try root.put("foo", datetime);
    const foo = root.getT(.datetime, "foo") orelse return std.testing.expect(false);
    try std.testing.expect(datetime.eql(foo));
}

test "for with partial" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var root = try data.root(.object);
    var array = try root.put("things", .array);
    try array.append(.{ .foo = "foo1", .bar = "bar1" });
    try array.append(.{ .foo = "foo2", .bar = "bar2" });

    if (zmpl.find("for_with_partial")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
            \\foo1: bar1
            \\<div>foo1</div>
            \\<div>bar1</div>
            \\foo2: bar2
            \\<div>foo2</div>
            \\<div>bar2</div>
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "error union" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var root = try data.root(.object);

    try root.put("foo", std.fmt.parseInt(u8, "16", 10));
    try std.testing.expectEqual(16, root.get("foo").?.integer.value);
}

test "xss sanitization/raw formatter" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var root = try data.root(.object);
    try root.put("foo", "<script>alert(':)');</script>");

    if (zmpl.find("xss")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
            \\&lt;script&gt;alert(&#039;:)&#039;);&lt;/script&gt;
            \\<script>alert(':)');</script>
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "if/else" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var root = try data.root(.object);

    var foo = try root.put("foo", .object);
    try foo.put("bar", 1);
    try foo.put("baz", 3);

    var qux = try foo.put("qux", .object);
    try qux.put("quux", 4);

    try foo.put("corge", "I am corge");
    try foo.put("truthy", true);
    try foo.put("falsey", false);

    if (zmpl.find("if_else")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
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
            \\  corge says "I am corge"
            \\
            \\  corge confirms "I am corge"
            \\
            \\  expected: else
            \\
            \\  bar is 1
            \\
            \\  expected truth
            \\
            \\  another expected truth
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "for with zmpl value" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var root = try data.root(.object);

    var foo = try root.put("foo", .array);
    try foo.append("bar");
    try foo.append("baz");
    try foo.append("qux");

    if (zmpl.find("for_with_zmpl_value_main")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
            \\
            \\    bar
            \\    baz
            \\    qux
            \\    bar
            \\    baz
            \\    qux
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "comments" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("comments")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
            \\
            \\
            \\<div>uncommented</div>
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "for with if" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var root = try data.object();
    try root.put("foo", true);
    var things = try root.put("things", .array);
    try things.append(.{ .foo = "baz", .bar = "qux", .time = "2024-11-24T18:50:23Z" });
    try things.append(.{ .foo = "quux", .bar = "corge", .time = "2024-11-24T18:51:23Z" });

    if (zmpl.find("for_with_if")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
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
    } else {
        try std.testing.expect(false);
    }
}

test "mix mardown and zig" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var root = try data.object();
    try root.put("foo", true);
    var things = try root.put("things", .array);
    try things.append(.{ .foo = "baz", .bar = "qux", .time = "2024-11-24T18:50:23Z" });
    try things.append(.{ .foo = "quux", .bar = "corge", .time = "2024-11-24T18:51:23Z" });

    // FIXME: This doesn't work exactly how we want - the for loop now correctly reverts back to
    // markdown (i.e. the parent's mode) but the list gets broken into three parts intsead of a
    // single list.
    if (zmpl.find("mix_markdown_and_zig")) |template| {
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try std.testing.expectEqualStrings(
            \\<div><h1>Header</h1>
            \\<ul><li>list item 1</li><li>list item 2</li></ul></div><div><ul><li>qux</li><li>   </li></ul></div><div><ul><li>corge</li><li>   </li></ul></div><div><ul><li>last item</li><li>qux</li></ul></div>
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "blocks" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("blocks")) |template| {
        const output = try template.render(
            &data,
            Context,
            .{},
            &.{},
            .{ .layout = zmpl.find("blocks_layout") },
        );
        try std.testing.expectEqualStrings(
            \\<html>
            \\    <head>            <link rel="stylesheet" href="https://www.example.com/styles.css" />            <link rel="stylesheet" href="https://www.example.com/styles.css" />            <link rel="stylesheet" href="https://www.example.com/styles.css" />            <link rel="stylesheet" href="https://www.example.com/styles.css" />            <link rel="stylesheet" href="https://www.example.com/styles.css" />            <link rel="stylesheet" href="https://www.example.com/styles.css" />            <link rel="stylesheet" href="https://www.example.com/styles.css" />            <link rel="stylesheet" href="https://www.example.com/styles.css" />            <link rel="stylesheet" href="https://www.example.com/styles.css" />    </head>
            \\</html>
        , output);
    } else {
        try std.testing.expect(false);
    }
}
