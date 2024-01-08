const std = @import("std");
const __zmpl = @import("zmpl");
const __Context = __zmpl.Context;
pub fn render(zmpl: *__Context) anyerror!void {
if (std.mem.eql(u8, "hello", "hello")) {
try zmpl.write("  <div>Hi!</div>\n");
} else {
try zmpl.write("  <div>Hello</div>\n");
}


}