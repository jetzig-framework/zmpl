@args foo: ZmplValue
@for (foo.items(.array)) |arg| {
    {{arg}}
}
@for (foo) |arg| {
    {{arg}}
}
