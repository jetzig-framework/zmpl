@for (.things) |thing| {
  @partial thing(thing.foo, thing.bar)
}
