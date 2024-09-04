const std = @import("std");
const zmpl = @import("zmpl");

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
        const output = try template.render(&data);
        defer std.testing.allocator.free(output);

        try std.testing.expectEqualStrings(
            \\<!-- Zig mode for template logic -->
            \\    <span>Zmpl is simple!</span>
            \\
            \\
            \\<!-- Easy data lookup syntax -->
            \\<div>Email: user@example.com</div>
            \\<div>Token: abc123-456-def</div>
            \\
            \\<!-- Partials -->
            \\<span>An example partial</span>
            \\<!-- Partials with positional args -->
            \\<a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>
            \\<!-- Partials with keyword args --->
            \\<a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>
            \\<!-- Partials with slots --->
            \\<a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>
            \\        <div class="slot-0"><a href="https://example.com/auth/abc123-456-def">Sign in</a></div>
            \\        <div class="slot-1"><a href="https://example.com/unsubscribe/abc123-456-def">Unsubscribe</a></div>
            \\
            \\<div><h1>Built-in markdown support</h1>
            \\<ul><li><a href="https://www.jetzig.dev/">jetzig.dev</a></li></ul></div>
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
        const output = try template.render(&data);
        defer std.testing.allocator.free(output);

        try std.testing.expectEqualStrings(
            \\<div>hello</div>
            \\    <span class="foo
            \\                 bar
            \\                 baz qux"
            \\    >
            \\      user@example.com    </span>
            \\<h2>Some slots:</h2>
            \\<div>
            \\Slots count: 2
            \\bar: 100
            \\baz: positional
            \\qux: true
            \\
            \\
            \\      qux was true !
            \\   
            \\
            \\
            \\    <span><div>slot 1</div></span>
            \\    <span><div>slot 2</div></span>
            \\
            \\</div><h2>Some slots:</h2>
            \\<div>
            \\Slots count: 2
            \\bar: 10
            \\baz: hello
            \\qux: true
            \\
            \\
            \\      qux was true !
            \\   
            \\
            \\
            \\    <span><div>slot 3</div></span>
            \\    <span><div>slot 4</div></span>
            \\
            \\</div><h2>Some slots:</h2>
            \\<div>
            \\Slots count: 3
            \\bar: 5
            \\baz: goodbye
            \\qux: false
            \\
            \\
            \\      qux was false :(
            \\   
            \\
            \\
            \\    <span><div>slot 5</div></span>
            \\    <span><div>slot 6</div></span>
            \\    <span><div>user@example.com</div></span>
            \\
            \\</div>
            \\
            \\<span>Blah partial content</span>
            \\
            \\<div class="foo
            \\            bar
            \\            my-css-class
            \\            baz"></div>
            \\<div><ul><li>foo</li><li>bar</li><li>user@example.com</li></ul></div>
            \\      <span>hello</span>
            \\
            \\
            \\Bar partial content
            \\
            \\hello
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "direct rendering of slots (render [][]const u8 as line-separated string)" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("slots")) |template| {
        const output = try template.render(&data);
        defer std.testing.allocator.free(output);
        try std.testing.expectEqualStrings(
            \\<div>
            \\<h2>Slots:</h2>
            \\<span>slot 1</span>
            \\<span>slot 2</span>
            \\<span>slot 3</span>
            \\</div>
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "javascript" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("javascript")) |template| {
        const output = try template.render(&data);
        defer std.testing.allocator.free(output);
        try std.testing.expectEqualStrings(
            \\<span>{ is my favorite character</span>
            \\  <script>
            \\    function foobar() {
            \\      console.log("hello");
            \\    }
            \\  </script>
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "partials without blocks" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("partials_without_blocks")) |template| {
        const output = try template.render(&data);
        defer std.testing.allocator.free(output);
        try std.testing.expectEqualStrings(
            \\<span>Blah partial content</span>      <div>bar</div>
            \\<span>Blah partial content</span>
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "custom delimiters" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("custom_delimiters")) |template| {
        const output = try template.render(&data);
        defer std.testing.allocator.free(output);
        try std.testing.expectEqualStrings(
            \\<div><h1>Built-in markdown support</h1>
            \\<ul><li><a href="https://www.jetzig.dev/">jetzig.dev</a></li></ul></div>
            \\
            \\        <script>
            \\          const foo = () => {
            \\            console.log("hello");
            \\          };
            \\        </script>
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test ".md.zmpl extension" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("markdown_extension")) |template| {
        const output = try template.render(&data);
        defer std.testing.allocator.free(output);
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
        const output = try template.render(&data);
        defer std.testing.allocator.free(output);
        try std.testing.expectEqualStrings(
            \\bar, default value
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "escaping (HTML and backslash escaping" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("escaping")) |template| {
        const output = try template.render(&data);
        defer std.testing.allocator.free(output);
        try std.testing.expectEqualStrings(
            \\<div><pre class="language-html" style="font-family: Monospace;"><code>&lt;div&gt;
            \\  @partial foo("bar")
            \\&lt;/div&gt;</code></pre></div>
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
        const output = try template.render(&data);
        defer std.testing.allocator.free(output);
        try std.testing.expectEqualStrings(
            \\<div><h1>Test</h1>
            \\
            \\<p>  <a href="https://jetzig.dev/">jetzig.dev</a></p>
            \\</div>
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
        const output = try template.render(&data);
        defer std.testing.allocator.free(output);
        try std.testing.expectEqualStrings(
            \\100
            \\123.456
            \\qux
        , output);
    } else {
        try std.testing.expect(false);
    }
}

test "inheritance" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    if (zmpl.find("inheritance_child")) |template| {
        const output = try template.renderWithOptions(
            &data,
            .{ .layout = zmpl.find("inheritance_parent3") },
        );
        defer std.testing.allocator.free(output);
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
        const output = try template.render(&data);
        defer std.testing.allocator.free(output);

        try std.testing.expectEqualStrings(
            \\<!-- Zig mode for template logic -->
            \\    <span>Zmpl is simple!</span>
            \\
            \\
            \\<!-- Easy data lookup syntax -->
            \\<div>Email: user@example.com</div>
            \\<div>Token: abc123-456-def</div>
            \\
            \\<!-- Partials -->
            \\<span>An example partial</span>
            \\<!-- Partials with positional args -->
            \\<a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>
            \\<!-- Partials with keyword args --->
            \\<a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>
            \\<!-- Partials with slots --->
            \\<a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>
            \\        <div class="slot-0"><a href="https://example.com/auth/abc123-456-def">Sign in</a></div>
            \\        <div class="slot-1"><a href="https://example.com/unsubscribe/abc123-456-def">Unsubscribe</a></div>
            \\
            \\<div><h1>Built-in markdown support</h1>
            \\<ul><li><a href="https://www.jetzig.dev/">jetzig.dev</a></li></ul></div>
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
        const output = try template.render(&data);
        defer std.testing.allocator.free(output);

        try std.testing.expectEqualStrings(
            \\<div>hello</div>
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
        const output = try template.render(&data);
        defer std.testing.allocator.free(output);

        try std.testing.expectEqualStrings(
            \\hello
            \\10
            \\100
            \\2
            \\5
            \\field_b    <span>qux was true</span>
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

test "Data.Value.Object to struct" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();
    var root = try data.root(.object);
    var obj_test_struct = try data.object();

    try obj_test_struct.put("a", 1);
    try obj_test_struct.put("b", 2e0);
    // try obj_test_struct.put("baz", 100.0);
    // try obj_test_struct.put("qux", true);

    try root.put("test_struct", obj_test_struct);

    const TestStruct = struct {
        a: i128,
        b: f128,
    };
    // const test_struct: TestStruct = undefined;

    std.debug.print("x: {s} \n", .{try root.get("test_struct").?.toJson()});
    const x = root.getT(.object, "test_struct");
    const tested_struct = try x.?.getStruct(TestStruct);
    const expected = TestStruct{
        .a = 1,
        .b = 2,
    };
    try std.testing.expectEqual(expected, tested_struct.?);
}
