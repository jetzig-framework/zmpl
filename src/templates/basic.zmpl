{{.foo}}
{{.bar}}
{{.baz}}
{{.test_struct.a}}
{{.test_struct.nested_struct.a}}
{{.test_struct.nested_struct.enum}}
@zig {
  if (data.getPresence("qux")) {
    <span>qux was true</span>
  }
}
