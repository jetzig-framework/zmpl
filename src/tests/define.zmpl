@define greeting(name: []const u8) {
Hi {{name}}!
}
@block greeting("World")
@block greeting("Zmpl")
