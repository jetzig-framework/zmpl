const std = @import("std");

const zmpl = @import("zmpl");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    var data = zmpl.Data.init(io, std.heap.smp_allocator);
    // https://github.com/json-iterator/test-data/blob/master/large-file.json
    const stat = try std.Io.Dir.cwd().statFile(io, "large-file.json", .{});
    const json = try std.Io.Dir.cwd().readFileAlloc(io, "large-file.json", allocator, .limited(stat.size + 1));

    // Time to beat: Duration: 1.28s
    try benchmark(io, zmpl.Data.fromJson, .{ &data, json });

    // Time to beat: Duration: 946.734ms
    _ = try benchmark(io, zmpl.Data.toJson, .{&data});
}

fn benchmark(io: std.Io, func: anytype, args: anytype) !void {
    const start = std.Io.Clock.Timestamp.now(io, .awake);
    _ = try @call(.auto, func, args);
    const elapsed = start.untilNow(io);
    std.debug.print("Duration: {}ms\n", .{elapsed.raw.toMilliseconds()});
}
