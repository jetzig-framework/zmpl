const std = @import("std");
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const zmpl = @import("zmpl");

pub fn main() !void {
    var gpa: GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var data: zmpl.Data = .init(allocator);
    const stat = try std.fs.cwd().statFile("large-file.json");
    const json = try std.fs.cwd().readFileAlloc("large-file.json", allocator, stat.size);

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
