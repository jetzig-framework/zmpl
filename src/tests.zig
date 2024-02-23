const std = @import("std");
const zmpl = @import("zmpl");
const allocator = std.testing.allocator;
const manifest = @import("templates/zmpl.manifest.zig");

test "readme example" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var body = try data.object();
    var user = try data.object();
    var auth = try data.object();

    try user.put("email", data.string("user@example.com"));
    try auth.put("token", data.string("abc123-456-def"));

    try body.put("user", user);
    try body.put("auth", auth);

    const output = try manifest.templates.example.render(&data);
    defer allocator.free(output);

    try std.testing.expectEqualStrings(
        \\  <div>Email: user@example.com</div>
        \\  <div>Token: abc123-456-def</div>
        \\
    , output);
}

test "template with if statement" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var object = try data.object();
    try object.put("foo", data.string("bar"));

    const output = try manifest.templates.example_with_if_statement.render(&data);
    defer allocator.free(output);

    try std.testing.expectEqualStrings("  <div>Hi!</div>\n", output);
}

test "template with quotes" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    const output = try manifest.templates.example_with_quotes.render(&data);
    defer allocator.free(output);

    try std.testing.expectEqualStrings("<div>\"Hello!\"</div>\n", output);
}

test "template with nested data lookup" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var object = try data.object();
    var nested_object = try data.object();
    try nested_object.put("bar", data.integer(10));
    try object.put("foo", nested_object);

    const output = try manifest.templates.example_with_nested_data_lookup.render(&data);
    defer allocator.free(output);

    try std.testing.expectEqualStrings("<div>Hello 10!</div>\n", output);
}

test "template with array data lookup" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var object = try data.object();
    var nested_array = try data.array();
    try nested_array.append(data.string("nested array value"));
    try object.put("foo", nested_array);

    const output = try manifest.templates.example_with_array_data_lookup.render(&data);
    defer allocator.free(output);

    try std.testing.expectEqualStrings("<div>Hello nested array value!</div>\n", output);
}

test "template with root array" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var array = try data.array();
    try array.append(data.string("root array value"));

    const output = try manifest.templates.example_with_root_array.render(&data);
    defer allocator.free(output);

    try std.testing.expectEqualStrings("<div>Hello root array value!</div>\n", output);
}

test "template with deep nesting" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var object = try data.object();
    var nested_object = try data.object();
    var double_nested_object = try data.object();
    var triple_nested_object = try data.object();
    try triple_nested_object.put("qux", data.string(":))"));
    try double_nested_object.put("baz", triple_nested_object);
    try nested_object.put("bar", double_nested_object);
    try object.put("foo", nested_object);

    const output = try manifest.templates.example_with_deep_nesting.render(&data);
    defer allocator.free(output);

    try std.testing.expectEqualStrings("<div>Hello :))</div>\n", output);
}

test "template with iteration" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var object = try data.object();
    var array = try data.array();
    try array.append(data.string("yay"));
    try array.append(data.string("hooray"));
    try object.put("foo", array);

    const output = try manifest.templates.example_with_iteration.render(&data);
    defer allocator.free(output);

    try std.testing.expectEqualStrings("  <span>yay</span>\n  <span>hooray</span>\n", output);
}

test "template with local variable reference" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    const output = try manifest.templates.example_with_local_variable_reference.render(&data);
    defer allocator.free(output);

    try std.testing.expectEqualStrings("<div>Hello there!</div>\n", output);
}

test "template with [slug]" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    const output = try manifest.templates.example_with_slug.render(&data);
    defer allocator.free(output);

    try std.testing.expectEqualStrings("<div>A template with a slug</div>\n", output);
}

test "template with string literal" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    const output = try manifest.templates.example_with_string_literal.render(&data);
    defer allocator.free(output);

    try std.testing.expectEqualStrings(
        \\<button>
        \\  <span>bar</span>
        \\</button>
        \\
    , output);
}

test "template with Zig literal" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    const output = try manifest.templates.example_with_zig_literal.render(&data);
    defer allocator.free(output);

    try std.testing.expectEqualStrings("<span>false</span>\n", output);
}

test "template with complex content" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var array = try data.array();
    try array.append(data.string("hello"));
    try array.append(data.string("hi"));
    try array.append(data.string("howdy"));
    try array.append(data.string("hiya"));
    try array.append(data.string("good day"));
    const output = try manifest.templates.example_with_complex_content.render(&data);
    defer allocator.free(output);

    try std.testing.expectEqualStrings(output,
        \\<html>
        \\    <div>Hi</div>
        \\  <div style="background-color: #ff0000">
        \\    <ol>
        \\        <li>This is item number 1, one</li>
        \\        <li>This is item number 2, two</li>
        \\        <li>This is item number 3, three</li>
        \\        <li>This is item number 4, four</li>
        \\        <li>This is item number 5, five</li>
        \\        <li>This is item number 6, six</li>
        \\        <li>This is item number 7, seven</li>
        \\        <li>This is item number 8, eight</li>
        \\        <li>This is item number 9, nine</li>
        \\    </ol>
        \\  </div>
        \\  <ol>
        \\        <div>hello</div>
        \\        <div>hi</div>
        \\        <div>howdy</div>
        \\        <div>hiya</div>
        \\        <div>good day</div>
        \\  </ol>
        \\  <span></span>
        \\  <span>hello</span>
        \\  <span>hi</span>
        \\  <span>howdy</span>
        \\  <span>hiya</span>
        \\  <span>good day</span>
        \\</html>
        \\
    );
}

test "template with fragment tag" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    const output = try manifest.templates.example_with_fragment_tag.render(&data);
    defer allocator.free(output);

    try std.testing.expectEqualStrings(output,
        \\<div>
        \\  <pre><code class="language-zig">
        \\    pub fn main() void {
        \\      std.debug.print("Hello, World!\n", .{});
        \\    }
        \\  </code></pre>
        \\</div>
        \\
    );
}

test "toJson" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var object = try data.object();
    var nested_object = try data.object();
    try nested_object.put("bar", data.integer(10));
    try object.put("foo", nested_object);

    const json = try data.toJson();
    defer allocator.free(json);

    try std.testing.expectEqualStrings(json,
        \\{"foo":{"bar":10}}
    );
}

test "toJson with no data" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();
    const json = try data.toJson();
    defer allocator.free(json);

    try std.testing.expectEqualStrings(json, "");
}

test "fromJson simple" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    const input =
        \\{"foo":"bar"}
    ;
    try data.fromJson(input);

    const json = try data.toJson();
    defer allocator.free(json);
    try std.testing.expectEqualStrings(json,
        \\{"foo":"bar"}
    );
}

test "fromJson complex" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    const input =
        \\{"foo":{"bar":["baz",10],"qux":{"quux":1.4123,"corge":true}}}
    ;
    try data.fromJson(input);

    const json = try data.toJson();
    defer allocator.free(json);
    try std.testing.expectEqualStrings(json,
        \\{"foo":{"bar":["baz",10],"qux":{"quux":1.4123e+00,"corge":true}}}
    );
}

test "reset" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    const input =
        \\{"foo":"bar"}
    ;
    try data.fromJson(input);

    const json = try data.toJson();
    defer allocator.free(json);
    try std.testing.expectEqualStrings(json,
        \\{"foo":"bar"}
    );
    data.reset();
    const more_json = try data.toJson();
    defer allocator.free(more_json);
    try std.testing.expectEqualStrings(more_json, ""); // Maybe this should raise an error or return null ?
}

test "read-only access (simpler interface after casting to const pointers/values)" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var things = try data.array();
    try things.append(data.string("foo"));

    if (data.value) |value| {
        switch (value.*) {
            .array => |array| {
                if (array.get(0)) |item| {
                    switch (item.*) {
                        .string => |string| try std.testing.expectEqualStrings(string.value, "foo"),
                        else => unreachable,
                    }
                }
            },
            else => unreachable,
        }
    } else unreachable;
}

test "appending to an array after insertion into object (regression)" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var object = try data.object();
    var array = try data.array();

    try array.append(data.string("bar"));
    try object.put("foo", array);
    try array.append(data.string("baz"));

    const json = try data.toJson();
    defer allocator.free(json);

    try std.testing.expectEqualStrings(json,
        \\{"foo":["bar","baz"]}
    );
}

test "inserting to an object after insertion into array (regression)" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var array = try data.array();
    var object = try data.object();

    try object.put("bar", data.string("baz"));
    try array.append(object);
    try object.put("qux", data.string("quux"));

    const json = try data.toJson();
    defer allocator.free(json);

    try std.testing.expectEqualStrings(json,
        \\[{"bar":"baz","qux":"quux"}]
    );
}
