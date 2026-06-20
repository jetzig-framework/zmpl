@args bar: usize, baz: []const u8, qux: bool
<h2>Some slots:</h2>
<div>
Slots count: {{slots.len}}
bar: {{bar}}
baz: {{baz}}
qux: {{qux}}

@zig {
  if (qux) {
    @html {
      qux was true !
    }
  } else {
    @html {
      qux was false :(
    }
  }
}

@zig {
  for (slots) |slot| {
    <span>{{slot}}</span>
  }
}
</div>
