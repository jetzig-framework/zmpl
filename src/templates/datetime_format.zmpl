<div>{{try zmpl.fmt.datetime(zmpl.get("foo"), "%c")}}</div>
<div>{{try zmpl.fmt.datetime(zmpl.get("foo"), "%Y-%m-%d")}}</div>

@for (.bar) |item| {
  <div>{{try zmpl.fmt.datetime(item.get("baz"), "%c")}}</div>
}
