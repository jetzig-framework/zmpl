const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const zmpl = @import("zmpl");

pub fn main() !void {
    var gpa: GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var arena: ArenaAllocator = .init(allocator);

    var data = zmpl.Data.init(arena.allocator());
    // https://github.com/json-iterator/test-data/blob/master/large-file.json
    const stat = try std.fs.cwd().statFile("large-file.json");
    const json = try std.fs.cwd().readFileAlloc(allocator, "large-file.json", stat.size);

    // Time to beat: Duration: 1.28s
    try benchmark(allocator, zmpl.Data.fromJson, .{ &data, json });

    // Time to beat: Duration: 946.734ms
    _ = try benchmark(allocator, zmpl.Data.toJson, .{&data});
}

fn benchmark(allocator: Allocator, func: anytype, args: anytype) !void {
    const start = std.time.microTimestamp();
    _ = try @call(.auto, func, args);
    const end = std.time.microTimestamp();
    var buf: Writer.Allocating = .init(allocator);
    defer buf.deinit();
    try buf.writer.printDuration((end - start) * 1000, .{});
    std.debug.print("Duration: {s}\n", .{try buf.toOwnedSlice()});
}
