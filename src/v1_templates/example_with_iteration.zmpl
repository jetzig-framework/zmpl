var data = zmpl.get("foo").?;
var it = data.iterator();
while (it.next()) |item| {
  <span>{item}</span>
}
