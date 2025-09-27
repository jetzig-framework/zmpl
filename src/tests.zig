const std = @import("std");
const ArrayList = std.ArrayList;
const zmpl = @import("zmpl");
const jetcommon = @import("jetcommon");
const expect = std.testing.expect;
const allocator = std.testing.allocator;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqual = std.testing.expectEqual;

const Context = struct { foo: []const u8 = "default" };

test "readme example" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var body = try data.object();
    var user = try data.object();
    var auth = try data.object();

    try user.put("email", data.string("user@example.com"));
    try auth.put("token", data.string("abc123-456-def"));

    try body.put("user", user);
    try body.put("auth", auth);

    const template = zmpl.find("example") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});

    return expectEqualStrings(
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
}

test "object passing to partial" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var root = try data.root(.object);
    var user = try data.object();

    try user.put("email", data.string("john@example.com"));
    try user.put("name", data.string("John Doe"));

    try root.put("user", user);

    const template = zmpl.find("object_root_layout") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});

    return expectEqualStrings(
        \\<h1>User</h1>
        \\<div>User email: john@example.com</div>
        \\<div>User name: John Doe</div>
        \\
    , output);
}

test "complex example" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var body = try data.object();
    var user = try data.object();
    var auth = try data.object();

    try user.put("email", data.string("user@example.com"));
    try auth.put("token", data.string("abc123-456-def"));

    try body.put("class", data.string("my-css-class"));
    try body.put("user", user);
    try body.put("auth", auth);

    const template = zmpl.find("complex_example") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});

    return expectEqualStrings(
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
}

test "direct rendering of slots (render [][]const u8 as line-separated string)" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    const template = zmpl.find("slots") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
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
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    const template = zmpl.find("javascript") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
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
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    const template = zmpl.find("partials_without_blocks") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
        \\    <span>Blah partial content</span>
        \\      <div>bar</div>    <span>Blah partial content</span>
        \\
    , output);
}

test "custom delimiters" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    const template = zmpl.find("custom_delimiters") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
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
}

test ".md.zmpl extension" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    const template = zmpl.find("markdown_extension") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
        \\<div><h1>Hello</h1>
        \\</div>
    , output);
}

test "default partial arguments" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    const template = zmpl.find("default_partial_arguments") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
        \\bar, default value
        \\
    , output);
}

test "escaping (HTML and backslash escaping" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    const template = zmpl.find("escaping") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    try expectEqualStrings(
        \\<div><pre class="language-html" style="font-family: Monospace;"><code>&lt;div&gt;
        \\  @partial foo("bar")
        \\&lt;/div&gt;</code></pre></div>
        \\
    , output);
}

test "references combined with markdown" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var object = try data.object();
    try object.put("url", data.string("https://jetzig.dev/"));
    try object.put("title", data.string("jetzig.dev"));

    const template = zmpl.find("references_markdown") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
        \\<div><h1>Test</h1>
        \\
        \\<p>  <a href="https://jetzig.dev/">jetzig.dev</a></p>
        \\</div>
        \\
    , output);
}

test "partial arg type coercion" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var object = try data.object();
    try object.put("foo", data.integer(100));
    try object.put("bar", data.float(123.456));
    try object.put("baz", data.string("qux"));

    const template = zmpl.find("partial_arg_type_coercion") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
        \\100
        \\123.456
        \\qux
        \\
    , output);
}

test "inheritance" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    const template = zmpl.find("inheritance_child") orelse
        return expect(false);
    const output = try template.render(
        &data,
        Context,
        .{},
        &.{},
        .{ .layout = zmpl.find("inheritance_parent3") },
    );
    return expectEqualStrings(
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
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var root = try data.root(.object);
    var user = try data.object();
    var auth = try data.object();

    try user.put("email", data.string("user@example.com"));
    try auth.put("token", data.string("abc123-456-def"));

    try root.put("user", user);
    try root.put("auth", auth);
    const template = zmpl.find("example") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});

    return expectEqualStrings(
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
}

test "reference stripping" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var root = try data.root(.object);
    try root.put("message", data.string("hello"));

    const template = zmpl.find("reference_with_spaces") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});

    return expectEqualStrings(
        \\<div>hello</div>
        \\
    , output);
}

test "inferred type in put/append" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

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
    const template = zmpl.find("basic") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});

    return expectEqualStrings(
        \\hello
        \\10
        \\100
        \\2
        \\5
        \\field_b    <span>qux was true</span>
        \\
    , output);
}

test "getT(.array, ...) and getT(.object, ...)" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);
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
    try expectEqual(&arr.array, res_arr);
    try expectEqual(&obj.object, res_obj);
}

test "object.remove(...)" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);
    var obj = try data.object();

    try obj.put("a", try data.object());
    try obj.put("b", try data.object());

    try expect(obj.object.remove("a"));
    try expectEqual(null, obj.getT(.object, "a"));
    try expect(obj.getT(.object, "b") != null);
}

test "getStruct from object" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);
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
    return expectEqual(expected, tested_struct.?);
}

test "Array.items()" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);
    var array = try data.array();
    try array.append("foo");
    try array.append("bar");

    for (array.array.items(), &[_][]const u8{ "foo", "bar" }) |item, expected|
        try expectEqualStrings(item.string, expected);
}

test "Object.items()" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);
    var object = try data.object();
    try object.put("foo", "bar");
    try object.put("baz", "qux");

    for (
        object.object.items(),
        &[_][]const u8{ "foo", "baz" },
        &[_][]const u8{ "bar", "qux" },
    ) |item, expected_key, expected_value| {
        try expectEqualStrings(item.key, expected_key);
        try expectEqualStrings(item.value.string, expected_value);
    }
}

test "toJson()" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);
    var object = try data.object();
    try object.put("foo", "bar");
    try object.put("baz", "qux");

    return expectEqualStrings(
        try data.toJson(),
        \\{"foo":"bar","baz":"qux"}
        \\
        ,
    );
}

test "put slice" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);
    var root = try data.root(.object);

    const T = struct { foo: []const u8, bar: []const u8 };
    var array: ArrayList(T) = .empty;
    defer array.deinit(allocator);
    try array.append(allocator, .{ .foo = "abc", .bar = "def" });
    try array.append(allocator, .{ .foo = "ghi", .bar = "jkl" });

    const slice = try array.toOwnedSlice(allocator);
    defer allocator.free(slice);

    try root.put("slice", slice);

    try expectEqualStrings((data.ref("slice.0.foo")).?.string, "abc");
    try expectEqualStrings((data.ref("slice.0.bar")).?.string, "def");
    try expectEqualStrings((data.ref("slice.1.foo")).?.string, "ghi");
    try expectEqualStrings((data.ref("slice.1.bar")).?.string, "jkl");
}

test "iteration" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var root = try data.root(.object);
    var array = try data.array();
    for ([_][]const u8{ "baz", "qux", "quux" }) |item| try array.append(data.string(item));

    try root.put("foo", array);
    try root.put("bar", [_][]const u8{ "corge", "grault", "garply" });

    var objects = try data.array();
    try objects.append(.{ .foo = "bar" });
    try objects.append(.{ .foo = "corge" });
    try root.put("objects", objects);

    const template = zmpl.find("iteration") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
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

test "datetime format" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var root = try data.root(.object);

    try root.put("foo", "2024-09-24T19:30:35Z");
    var bar = try data.array();
    try bar.append(.{ .baz = "2024-09-27T20:19:14Z" });
    try root.put("bar", bar);

    const template = zmpl.find("datetime_format") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
        \\<div>Tue Sep 24 19:30:35 2024</div>
        \\<div>2024-09-24</div>
        \\
        \\  <div>Fri Sep 27 20:19:14 2024</div>
        \\
    , output);
}

test "datetime" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var root = try data.root(.object);
    const datetime = try jetcommon.types.DateTime.parse("2024-09-27T21:29:51Z");
    try root.put("foo", datetime);
    const foo = root.getT(.datetime, "foo") orelse return expect(false);
    try expect(datetime.eql(foo));
}

test "for with partial" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var root = try data.root(.object);
    var array = try root.put("things", .array);
    try array.append(.{ .foo = "foo1", .bar = "bar1" });
    try array.append(.{ .foo = "foo2", .bar = "bar2" });
    const template = zmpl.find("for_with_partial") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
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

test "error union" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var root = try data.root(.object);

    try root.put("foo", std.fmt.parseInt(u8, "16", 10));
    try expectEqual(16, root.get("foo").?.integer);
}

test "xss sanitization/raw formatter" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var root = try data.root(.object);
    try root.put("foo", "<script>alert(':)');</script>");

    const template = zmpl.find("xss") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
        \\&lt;script&gt;alert(&#039;:)&#039;);&lt;/script&gt;
        \\<script>alert(':)');</script>
        \\
    , output);
}

test "if/else" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var root = try data.root(.object);

    var foo = try root.put("foo", .object);
    try foo.put("bar", 1);
    try foo.put("baz", 3);

    var qux = try foo.put("qux", .object);
    try qux.put("quux", 4);

    try foo.put("corge", "I am corge");
    try foo.put("truthy", true);
    try foo.put("falsey", false);

    const template = zmpl.find("if_else") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
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
}

test "for with zmpl value" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var root = try data.root(.object);

    var foo = try root.put("foo", .array);
    try foo.append("bar");
    try foo.append("baz");
    try foo.append("qux");
    const template = zmpl.find("for_with_zmpl_value_main") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
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
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);
    const template = zmpl.find("comments") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
        \\
        \\
        \\<div>uncommented</div>
        \\
    , output);
}

test "for with if" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var root = try data.object();
    try root.put("foo", true);
    var things = try root.put("things", .array);
    try things.append(.{ .foo = "baz", .bar = "qux", .time = "2024-11-24T18:50:23Z" });
    try things.append(.{ .foo = "quux", .bar = "corge", .time = "2024-11-24T18:51:23Z" });

    const template = zmpl.find("for_with_if") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
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
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var root = try data.object();
    try root.put("foo", true);
    var things = try root.put("things", .array);
    try things.append(.{ .foo = "baz", .bar = "qux", .time = "2024-11-24T18:50:23Z" });
    try things.append(.{ .foo = "quux", .bar = "corge", .time = "2024-11-24T18:51:23Z" });

    // FIXME: This doesn't work exactly how we want - the for loop now correctly reverts back to
    // markdown (i.e. the parent's mode) but the list gets broken into three parts intsead of a
    // single list.
    const template = zmpl.find("mix_markdown_and_zig") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
        \\<div><h1>Header</h1>
        \\<ul><li>list item 1</li><li>list item 2</li></ul></div><div><ul><li>qux</li><li>   </li></ul></div><div><ul><li>corge</li><li>   </li></ul></div><div><ul><li>last item</li><li>qux</li></ul></div>
        \\
    , output);
}

test "nullable if" {
    // Test for nullable if statements:
    // - null and empty strings should be falsey
    // - non-empty strings should be truthy

    // Test with null value - should be falsey
    {
        var data: zmpl.Data = try .init(allocator);
        defer data.deinit(allocator);

        var clip = try data.object();
        try clip.put("notes", null);

        var root = try data.root(.object);
        try root.put("clip", clip);

        const template = zmpl.find("nullable_if") orelse
            return expect(false);
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try expectEqualStrings("\nThe value is null\n", output);
    }

    // Test with non-null, non-empty string - should be truthy
    {
        var data: zmpl.Data = try .init(allocator);
        defer data.deinit(allocator);

        var clip = try data.object();
        try clip.put("notes", "Some notes");

        var root = try data.root(.object);
        try root.put("clip", clip);

        const template = zmpl.find("nullable_if") orelse
            return expect(false);
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        // Non-empty string should correctly evaluate as truthy
        try expectEqualStrings("\nThe value is not null\n", output);
    }

    // Test with empty string - should be falsey like null
    {
        var data: zmpl.Data = try .init(allocator);
        defer data.deinit(allocator);

        var clip = try data.object();
        try clip.put("notes", "");

        var root = try data.root(.object);
        try root.put("clip", clip);

        const template = zmpl.find("nullable_if") orelse
            return expect(false);
        const output = try template.render(&data, Context, .{}, &.{}, .{});
        try expectEqualStrings("\nThe value is null\n", output);
    }
}

test "if statement with indented HTML - if branch" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var root = try data.root(.object);
    var user = try data.object();
    try user.put("is_logged_in", true);
    try user.put("display_name", "TestUser");
    try root.put("user", user);

    const template = zmpl.find("if_indented_html") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
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
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var root = try data.root(.object);
    var user = try data.object();
    try user.put("is_logged_in", false);
    try root.put("user", user);

    const template = zmpl.find("if_indented_html") orelse
        return expect(false);
    const output = try template.render(&data, Context, .{}, &.{}, .{});
    return expectEqualStrings(
        \\
        \\                <div class="d-none d-md-flex align-items-center ms-2">
        \\                    <a href="/login" class="btn btn-outline-secondary btn-sm">Log in</a>
        \\                    <a href="/register" class="btn btn-primary btn-sm ms-2">Sign up</a>
        \\                </div>
        \\
    , output);
}

test "blocks" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    const template = zmpl.find("blocks") orelse
        return expect(false);
    const output = try template.render(
        &data,
        Context,
        .{},
        &.{},
        .{ .layout = zmpl.find("blocks_layout") },
    );
    return expectEqualStrings(
        \\<html>
        \\    <head>            <link rel="stylesheet" href="https://www.example.com/styles.css" />            <link rel="stylesheet" href="https://www.example.com/styles.css" />            <link rel="stylesheet" href="https://www.example.com/styles.css" />            <link rel="stylesheet" href="https://www.example.com/styles.css" />            <link rel="stylesheet" href="https://www.example.com/styles.css" />            <link rel="stylesheet" href="https://www.example.com/styles.css" />            <link rel="stylesheet" href="https://www.example.com/styles.css" />            <link rel="stylesheet" href="https://www.example.com/styles.css" />            <link rel="stylesheet" href="https://www.example.com/styles.css" />    </head>
        \\</html>
    , output);
}

test "append struct with []const []const u8 field" {
    var data: zmpl.Data = try .init(allocator);
    defer data.deinit(allocator);

    var root = try data.root(.object);
    const Foo = struct {
        bar: []const u8,
        baz: []const []const u8,
        qux: []const usize,
    };

    try root.put("foo", Foo{ .bar = "bar", .baz = &.{ "baz", "qux" }, .qux = &.{ 1, 2, 3 } });

    const foo = root.get("foo").?;
    const baz = foo.get("baz").?;
    const baz_items = baz.items(.array);

    try expectEqual(baz_items.len, 2);

    const expected_baz: []const []const u8 = &.{ "baz", "qux" };

    for (baz_items, 0..) |item, index|
        try expectEqualStrings(expected_baz[index], item.string);

    const qux = foo.get("qux").?;
    const qux_items = qux.items(.array);

    try expectEqual(qux_items.len, 3);

    const expected_qux: []const usize = &.{ 1, 2, 3 };

    for (qux_items, 0..) |item, index|
        try expectEqual(expected_qux[index], item.integer);
}
