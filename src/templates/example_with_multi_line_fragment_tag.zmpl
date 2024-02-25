<pre><code class="language-zig">
<#>
// src/app/views/users.zig
const std = @import("std");
const jetzig = @import("jetzig");

const Request = jetzig.http.Request;
const Data = jetzig.data.Data;
const View = jetzig.views.View;

pub fn get(id: []const u8, request: *Request, data: *Data) !View {
  var user = try data.object();

  try user.put("email", data.string("user@example.com"));
  try user.put("name", data.string("Ziggy Ziguana"));
  try user.put("id", data.integer(id));
  try user.put("authenticated", data.boolean(true));

  return request.render(.ok);
}
</#>
</code></pre>
