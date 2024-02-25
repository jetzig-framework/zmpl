if (std.mem.eql(u8, "zmpl is simple", "zmpl" ++ " is " ++ "simple")) {
  <div>Email: {.user.email}</div>
  <div>Token: {.auth.token}</div>
  <#>
    <script>
      console.log("add any raw content using multi-line <#> tags");
    </script>
  </#>
  <>Use fragment tags when you don't want to use a specific HTML tag
}
