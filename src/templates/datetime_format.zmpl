<div>{{try zmpl.fmt.datetime(.foo, "%c")}}</div>
<div>{{try zmpl.fmt.datetime(.foo, "%Y-%m-%d")}}</div>

@for (.bar) |item| {
  <div>{{try zmpl.fmt.datetime(item.baz, "%c")}}</div>
}
