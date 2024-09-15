@for (.foo) |item| {
  <div>{{item}}</div>
}

@for (.bar) |item| {
  <div>{{item}}</div>
}

@zig {
  const baz = [_][]const u8{"waldo", "fred", "plugh"};
}

@for (baz) |item| {
  <div>{{item}}</div>
}

@for (.foo, 0..) |item, index| {
  <div>{{index}}: {{item}}</div>
}

@for (.objects) |item| {
  <div>{{item.foo}}</div>
}

@zig {
  const Thing = struct { foo: []const u8 };
  const structs = [_]Thing{ .{ .foo = "bar" }, .{ .foo = "baz" } };
}

@for (structs) |item| {
  <div>{{item.foo}}</div>
}
