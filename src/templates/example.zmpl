if (std.mem.eql(u8, "zmpl is simple", "zmpl" ++ " is " ++ "simple")) {
  // Add comments using Zig syntax.
  <div>Email: {.user.email}</div>
  <div>Token: {.auth.token}</div>

  // Render a partial named `users/_mailto.zmpl`:
  <div>{^users/mailto}</div>

  // Pass arguments to a partial:
  <div>{^users/mailto(subject: zmpl.string("Welcome to Jetzig!"))}</div>

  <>Use fragment tags when you want to output content without a specific HTML tag</>

  <#>
  Use multi-line raw text tags to bypass Zmpl syntax.
  <code>Some example code with curly braces {} etc.</code>
  </#>

  <span>Escape curly braces {{like this}}</span>
}
