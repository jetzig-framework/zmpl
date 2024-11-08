![Zmpl logo](public/zmpl.png)

_Zmpl_ is a templating language for [Zig](https://ziglang.org/) :lizard:

* Use _Zig_ code directly in templates for control flow.
* Simple and intuitive DSL for building flexible, _JSON_-compatible data objects.
* Compiles to _Zig_ code for syntax and type validation.
* Used by the [Jetzig](https://github.com/jetzig-framework/jetzig) web framework.

## Documentation

Visit the [Jetzig Documentation](https://jetzig.dev/documentation.html) page to see detailed _Zmpl_ documentation with usage examples.

## Syntax Highlighting

Syntax highlighters are currently community-sourced. Please get in touch if you have created a plugin for your editor of choice and we will gladly list it here.

* [VSCode](https://github.com/z1fire/zmpl-syntax-highlighting-vscode) by [Zackary Housend](https://github.com/z1fire)
* _NeoVim_ syntax highlighting can be achieved by using the above _VSCode_ grammar with the [nvim-textmate](https://github.com/icedman/nvim-textmate) plugin. You may need to use [this fork](https://github.com/bobf/nvim-textmate) if you have issues compiling the UTF-8 extension.

## Example

See [src/templates](src/templates) for more examples.

### Template

```zig
<!-- Zig mode for template logic -->
@zig {
  if (std.mem.eql(u8, "zmpl is simple", "zmpl" ++ " is " ++ "simple")) {
    <span>Zmpl is simple!</span>
  }
}

<!-- Easy data lookup syntax -->
<div>Email: {{.user.email}}</div>
<div>Token: {{.auth.token}}</div>

<!-- Partials -->
@partial example_partial

<!-- Partials with positional args -->
@partial mailto(.user.email, "Welcome to Jetzig!")

<!-- Partials with keyword args --->
@partial mailto(email: .user.email, subject: "Welcome to Jetzig!")

<!-- Partials with slots --->
@partial mailto(email: .user.email, subject: "Welcome to Jetzig!") {
  <a href="https://example.com/auth/{{.auth.token}}">Sign in</a>
  <a href="https://example.com/unsubscribe/{{.auth.token}}">Unsubscribe</a>
}

@markdown {
  # Built-in markdown support

  * [jetzig.dev](https://www.jetzig.dev/)
}
```

### `mailto` Partial

```zig
@args email: *ZmplValue, subject: []const u8
<a href="mailto:{{email}}?subject={{subject}}">{{email}}</a>

@zig {
    for (slots, 0..) |slot, slot_index| {
        <div class="slot-{{slot_index}}">{{slot}}</div>
    }
}
```

### Output HTML

```html
<!-- Zig mode for template logic -->
    <span>Zmpl is simple!</span>


<!-- Easy data lookup syntax -->
<div>Email: user@example.com</div>
<div>Token: abc123-456-def</div>

<!-- Partials -->
<span>An example partial</span>

<!-- Partials with positional args -->
<a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>

<!-- Partials with keyword args --->
<a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>

<!-- Partials with slots --->
<a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>
        <div class="slot-0"><a href="https://example.com/auth/abc123-456-def">Sign in</a></div>
        <div class="slot-1"><a href="https://example.com/unsubscribe/abc123-456-def">Unsubscribe</a></div>


<div><h1>Built-in markdown support</h1>
<ul><li><a href="https://www.jetzig.dev/">jetzig.dev</a></li></ul></div>
```

### Example Usage

Default template path is `src/templates`. Use `-Dzmpl_templates_path=...` to set an alternative (relative or absolute) path.

```zig
const std = @import("std");
const zmpl = @import("zmpl");

test "readme example" {
    var data = zmpl.Data.init(std.testing.allocator);
    defer data.deinit();

    var body = try data.object();
    var user = try data.object();
    var auth = try data.object();

    try user.put("email", data.string("user@example.com"));
    try auth.put("token", data.string("abc123-456-def"));

    try body.put("user", user);
    try body.put("auth", auth);

    if (zmpl.find("example")) |template| {
        const output = try template.render(&data);
        defer std.testing.allocator.free(output);

        try std.testing.expectEqualStrings(
            \\<!-- Zig mode for template logic -->
            \\    <span>Zmpl is simple!</span>
            \\
            \\
            \\<!-- Easy data lookup syntax -->
            \\<div>Email: user@example.com</div>
            \\<div>Token: abc123-456-def</div>
            \\
            \\<!-- Partials -->
            \\<span>An example partial</span>
            \\<!-- Partials with positional args -->
            \\<a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>
            \\<!-- Partials with keyword args --->
            \\<a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>
            \\<!-- Partials with slots --->
            \\<a href="mailto:user@example.com?subject=Welcome to Jetzig!">user@example.com</a>
            \\        <div class="slot-0"><a href="https://example.com/auth/abc123-456-def">Sign in</a></div>
            \\        <div class="slot-1"><a href="https://example.com/unsubscribe/abc123-456-def">Unsubscribe</a></div>
            \\
            \\<div><h1>Built-in markdown support</h1>
            \\<ul><li><a href="https://www.jetzig.dev/">jetzig.dev</a></li></ul></div>
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
