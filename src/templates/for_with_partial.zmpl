@for ($.things) |thing| {
  @partial thing(thing.foo, thing.bar)
  @partial thing2(thing)
}
