@zig {
  const foo = 100;
  const bar = (try zmpl.getValue("test")).?;
  const MyThing = struct {
      pub fn format(self: @This(), actual_fmt: []const u8, options: anytype, writer: anytype) !void {
          _ = self;
          _ = actual_fmt;
          _ = options;
          try writer.writeAll("hello");
      }
  };

  const my_thing = MyThing{};

  {{my_thing}}

  {{bar}}

  for (0..10) |index| {
    <span>{{index}}</span>
    <span>{{foo}}</span>
    <span>{{.user.email}}</span>
  }
}
