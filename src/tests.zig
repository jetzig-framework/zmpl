const std = @import("std");
const zmpl = @import("zmpl");
const allocator = std.testing.allocator;
const manifest = @import("templates/manifest.zig");

test "auto-loaded template file with data" {
    var buf = std.ArrayList(u8).init(allocator);
    const writer = buf.writer();
    defer buf.deinit();

    var data = zmpl.Data.init(allocator);
    defer data.deinit();
    var object = try data.object();
    try object.add("foo", data.string("bar"));

    var context = zmpl.Context{ .allocator = allocator, .writer = writer, .data = &data };
    try manifest.templates.example.render(&context);

    try std.testing.expectEqualStrings("  <div>Hi!</div>\n", buf.items);
}

test "template with quotes" {
    var buf = std.ArrayList(u8).init(allocator);
    const writer = buf.writer();
    defer buf.deinit();

    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var context = zmpl.Context{ .allocator = allocator, .writer = writer, .data = &data };
    try manifest.templates.example_with_quotes.render(&context);

    try std.testing.expectEqualStrings("<div>\"Hello!\"</div>\n", buf.items);
}

test "template with nested data lookup" {
    var buf = std.ArrayList(u8).init(allocator);
    const writer = buf.writer();
    defer buf.deinit();

    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var object = try data.object();

    var nested_object = try data.object();
    try nested_object.add("bar", data.integer(10));
    try object.add("foo", nested_object.*);

    var context = zmpl.Context{ .allocator = allocator, .writer = writer, .data = &data };
    try manifest.templates.example_with_nested_data_lookup.render(&context);

    try std.testing.expectEqualStrings("<div>Hello 10!</div>\n", buf.items);
}

test "template with array data lookup" {
    var buf = std.ArrayList(u8).init(allocator);
    const writer = buf.writer();
    defer buf.deinit();

    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var object = try data.object();

    var nested_array = try data.array();
    try nested_array.append(data.string("nested array value"));
    try object.add("foo", nested_array.*);

    var context = zmpl.Context{ .allocator = allocator, .writer = writer, .data = &data };
    try manifest.templates.example_with_array_data_lookup.render(&context);

    try std.testing.expectEqualStrings("<div>Hello nested array value!</div>\n", buf.items);
}

test "template with root array" {
    var buf = std.ArrayList(u8).init(allocator);
    const writer = buf.writer();
    defer buf.deinit();

    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var array = try data.array();
    try array.append(data.string("root array value"));

    var context = zmpl.Context{ .allocator = allocator, .writer = writer, .data = &data };
    try manifest.templates.example_with_root_array.render(&context);

    try std.testing.expectEqualStrings("<div>Hello root array value!</div>\n", buf.items);
}

test "template with deep nesting" {
    var buf = std.ArrayList(u8).init(allocator);
    const writer = buf.writer();
    defer buf.deinit();

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

    var context = zmpl.Context{ .allocator = allocator, .writer = writer, .data = &data };
    try manifest.templates.example_with_deep_nesting.render(&context);

    try std.testing.expectEqualStrings("<div>Hello :))</div>\n", buf.items);
}

test "template with iteration" {
    var buf = std.ArrayList(u8).init(allocator);
    const writer = buf.writer();
    defer buf.deinit();

    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var object = try data.object();
    var array = try data.array();
    try array.append(data.string("yay"));
    try array.append(data.string("hooray"));
    try object.add("foo", array.*);

    var context = zmpl.Context{ .allocator = allocator, .writer = writer, .data = &data };
    try manifest.templates.example_with_iteration.render(&context);

    try std.testing.expectEqualStrings("  <span>yay</span>\n  <span>hooray</span>\n", buf.items);
}
