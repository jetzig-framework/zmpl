{{.foo}}
{{.bar}}
{{.baz}}
{{.test_struct.a}}
{{.test_struct.nested_struct.a}}
{{.test_struct.nested_struct.enum_val}}
@zig {
  if (data.qux) {
    <span>qux was true</span>
  }
}
