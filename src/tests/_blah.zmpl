@zig {
  if (true) {
    <span>Blah partial content</span>
    for (slots) |slot| {
      {{slot}}
    }
  }
}
