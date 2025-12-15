const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const zmpl = @import("zmpl");

pub fn main() !void {
    var gpa: GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var arena: ArenaAllocator = .init(allocator);

    var data = zmpl.Data.init(arena.allocator());
    const stat = try std.fs.cwd().statFile("large-file.json");
    const json = try std.fs.cwd().readFileAlloc(allocator, "large-file.json", stat.size);

    // Time to beat: Duration: 1.28s
    try benchmark(zmpl.Data.fromJson, .{ &data, json });

    // Time to beat: Duration: 946.734ms
    _ = try benchmark(zmpl.Data.toJson, .{&data});
}

fn benchmark(func: anytype, args: anytype) @typeInfo(@TypeOf(func)).@"fn".return_type.? {
    const start = std.time.nanoTimestamp();
    const result = try @call(.auto, func, args);
    const end = std.time.nanoTimestamp();
    std.debug.print("Duration: {}\n", .{std.fmt.fmtDuration(@intCast(end - start))});
    return result;
}
