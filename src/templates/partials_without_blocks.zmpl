@html {
  @partial blah
  @zig {
    if (true) {
      <div>bar</div>
    } else {
      <div>baz</div>
    }
  }
  @partial blah
}
