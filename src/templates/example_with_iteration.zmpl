var data = try zmpl.get("foo");
var it = data.iterator();
while (it.next()) |item| {
  <span>{item}</span>
}
