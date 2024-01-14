const std = @import("std");
const zmpl = @import("zmpl");
const allocator = std.testing.allocator;
const manifest = @import("templates/manifest.zig");

test "readme example" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var body = try data.object();
    var user = try data.object();
    var auth = try data.object();

    try user.add("email", data.string("user@example.com"));
    try auth.add("token", data.string("abc123-456-def"));

    try body.add("user", user.*);
    try body.add("auth", auth.*);

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
    try object.add("foo", data.string("bar"));

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
    try nested_object.add("bar", data.integer(10));
    try object.add("foo", nested_object.*);

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
    try object.add("foo", nested_array.*);

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
    try triple_nested_object.add("qux", data.string(":))"));
    try double_nested_object.add("baz", triple_nested_object.*);
    try nested_object.add("bar", double_nested_object.*);
    try object.add("foo", nested_object.*);

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
    try object.add("foo", array.*);

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
