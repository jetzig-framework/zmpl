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
