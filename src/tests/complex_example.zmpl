@zig {
  if (true) {
    <div>hello</div>
    <span class="foo
                 bar
                 baz qux"
    >
      {{.user.email}}
    </span>

    @partial foo(100, "positional", true) {
      <div>slot 1</div>
      <div>slot 2</div>
    }

    @partial foo(bar: 10, baz: "hello", qux: true) {
      <div>slot 3</div>
      <div>slot 4</div>
    }

    @partial foo(baz: "goodbye", qux: false, bar: 5) {
      <div>slot 5</div>
      <div>slot 6</div>
      <div>{{.user.email}}</div>
    }
  }
}

@html {
  @partial blah
}

<div class="foo
            bar
            {{.class}}
            baz"></div>
@markdown {
  * foo
  * bar
  * {{.user.email}}
  @zig {
    if (true) {
      <span>{{"hello"}}</span>
    }
  }
}

@partial bar {
  <div>slot</div>
}

hello
