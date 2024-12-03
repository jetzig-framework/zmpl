<!-- Zig mode for template logic -->

@zig {
  if (std.mem.eql(u8, "zmpl is simple", "zmpl" ++ " is " ++ "simple")) {
    <span>Zmpl is simple!</span>
  }
}

<!-- Easy data lookup syntax -->
<div>Email: {{$.user.email}}</div>
<div>Token: {{$.auth.token}}</div>

<!-- Partials -->
@partial example_partial

<!-- Partials with positional args -->
@partial mailto(.user.email, "Welcome to Jetzig!")

<!-- Partials with keyword args -->
@partial mailto(email: $.user.email, subject: "Welcome to Jetzig!")

<!-- Partials with slots -->
@partial mailto(email: $.user.email, subject: "Welcome to Jetzig!") {
  <a href="https://example.com/auth/{{$.auth.token}}">Sign in</a>
  <a href="https://example.com/unsubscribe/{{$.auth.token}}">Unsubscribe</a>
}

@markdown {
  # Built-in markdown support

  * [jetzig.dev](https://www.jetzig.dev/)
}
