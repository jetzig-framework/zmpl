![Zmpl logo](public/zmpl.png)

_Zmpl_ is a templating language for [Zig](https://ziglang.org/) :lizard:

* Use _Zig_ code directly in templates for control flow.
* Simple and intuitive DSL for building flexible, _JSON_-compatible data objects.
* Compiles to _Zig_ code for syntax and type validation.
* Used by the [Jetzig](https://github.com/bobf/jetzig) web framework.

## Syntax Highlighting

Syntax highlighters are currently community-sourced. Please get in touch if you have created a plugin for your editor of choice and we will gladly list it here.

* [VSCode](https://github.com/z1fire/zmpl-syntax-highlighting-vscode) by [Zackary Housend](https://github.com/z1fire)

## Example

See [src/templates](src/templates) for more examples.

```html
if (std.mem.eql(u8, "zmpl is simple", "zmpl" ++ " is " ++ "simple")) {
  // Add comments using Zig syntax.
  <div>Email: {.user.email}</div>
  <div>Token: {.auth.token}</div>

  // Render a partial named `users/_mailto.zmpl`:
  <div>{^users/mailto}</div>

  <>Use fragment tags when you want to output content without a specific HTML tag</>

  <#>
  Use multi-line raw text tags to bypass Zmpl syntax.
  <code>Some example code with curly braces {} etc.</code>
  </#>

  <span>Escape curly braces {{like this}}</span>
}
```

```zig
const std = @import("std");
const zmpl = @import("zmpl");
const allocator = std.testing.allocator;
const manifest = @import("zmpl.manifest"); // Generated at build time

test "readme example" {
    var data = zmpl.Data.init(allocator);
    defer data.deinit();

    var body = try data.object();
    var user = try data.object();
    var auth = try data.object();

    try user.put("email", data.string("user@example.com"));
    try auth.put("token", data.string("abc123-456-def"));

    try body.put("user", user);
    try body.put("auth", auth);

    if (manifest.find("example")) |template| {
        const output = try template.render(&data);
        defer allocator.free(output);

        try std.testing.expectEqualStrings(
            \\  <div>Email: user@example.com</div>
            \\  <div>Token: abc123-456-def</div>
            \\  <div><a href="mailto:user@example.com">user@example.com</a></div>
            \\  Use fragment tags when you want to output content without a specific HTML tag
            \\  Use multi-line raw text tags to bypass Zmpl syntax.
            \\  <code>Some example code with curly braces {} etc.</code>
            \\  <span>Escape curly braces {like this}</span>
            \\
        , output);
    } else {
        try std.testing.expect(false);
    }
}
```

## License

[MIT](LICENSE)

## Credits

[Templ](https://github.com/a-h/templ) - inspiration for template layout.
