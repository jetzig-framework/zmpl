const std = @import("std");

const colors = @import("colors.zig");
const util = @import("util.zig");

pub fn printSourceInfo(
    allocator: std.mem.Allocator,
    err: anyerror,
    stack_trace: *std.builtin.StackTrace,
) !void {
    const debug_info = std.debug.getSelfDebugInfo() catch return err;
    const source_location = (zmplSourceLocation(debug_info, stack_trace, err) catch
        return err) orelse
        return err;
    defer debug_info.allocator.free(source_location.file_name);
    try debugSourceLocation(allocator, source_location);
}

fn zmplSourceLocation(
    debug_info: *std.debug.SelfInfo,
    stack_trace: *std.builtin.StackTrace,
    err: anyerror,
) !?std.debug.SourceLocation {
    const builtin = @import("builtin");
    if (builtin.strip_debug_info) return error.MissingDebugInfo;
    var frame_index: usize = 0;
    var frames_left: usize = @min(stack_trace.index, stack_trace.instruction_addresses.len);

    while (frames_left != 0) : ({
        frames_left -= 1;
        frame_index = (frame_index + 1) % stack_trace.instruction_addresses.len;
    }) {
        const return_address = stack_trace.instruction_addresses[frame_index];
        const address = return_address - 1;
        const module = debug_info.getModuleForAddress(address) catch return err;

        const symbol_info = module.getSymbolAtAddress(debug_info.allocator, address) catch
            return err;

        if (symbol_info.source_location) |source_location| {
            if (std.mem.endsWith(u8, source_location.file_name, "zmpl.manifest.zig")) {
                return source_location;
            }
        }
    }

    return null;
}

fn debugSourceLocation(
    allocator: std.mem.Allocator,
    source_location: std.debug.SourceLocation,
) !void {
    const debug_line = try findDebugLine(allocator, source_location) orelse return;
    var it = std.mem.tokenizeScalar(u8, debug_line, ':');
    _ = it.next();
    _ = it.next();
    const from = it.next();
    const to = it.next();
    const filename = it.rest();
    if (from == null or to == null or filename.len == 0) return;

    const from_position = try std.fmt.parseInt(usize, from.?, 10);
    const to_position = try std.fmt.parseInt(usize, to.?, 10);

    const source_file = try std.fs.openFileAbsolute(filename, .{});

    const content = try allocator.alloc(u8, to_position - from_position + 1);
    try source_file.seekTo(from_position);
    _ = try source_file.readAll(content);

    var cursor: usize = 0;
    var buf: [std.heap.pageSize()]u8 = undefined;
    try source_file.seekTo(0);
    const source_line_number = outer: {
        while (cursor < from_position) {
            var line_count: usize = 1;
            const bytes_read = try source_file.readAll(buf[0..]);
            if (bytes_read == 0) return;
            for (buf[0..bytes_read]) |char| {
                if (cursor >= from_position) break :outer line_count;
                if (char == '\n') line_count += 1;
                cursor += 1;
            }
        }
        return;
    };

    std.debug.print(
        std.fmt.comptimePrint(
            "\n{s} {s} {s} {s}:\n\n{s}\n",
            .{
                colors.red("Error occurred in"),
                colors.cyan("{s}"),
                colors.red("near line"),
                colors.cyan("{}"),
                colors.yellow("{s}"),
            },
        ),
        .{ filename, source_line_number, try util.indent(allocator, content, 4) },
    );
}

fn findDebugLine(
    allocator: std.mem.Allocator,
    source_location: std.debug.SourceLocation,
) !?[]const u8 {
    const file = try std.fs.openFileAbsolute(source_location.file_name, .{});
    const stat = try file.stat();
    const size = stat.size;

    var cursor: usize = 0;
    var line: usize = 0;
    var buf: [std.heap.pageSize()]u8 = undefined;
    var position: usize = 0;

    while (cursor < size) outer: {
        const bytes_read = try file.readAll(buf[0..]);
        if (bytes_read == 0) return null;
        for (buf) |char| {
            if (char == '\n') line += 1;
            if (line == source_location.line) {
                position = cursor;
                break :outer;
            }
            cursor += 1;
        }
    }

    try file.seekTo(position);
    cursor = position;
    var debug_line_buf = std.array_list.Managed(u8).init(allocator);
    const debug_writer = debug_line_buf.writer();

    outer: {
        while (cursor < size) {
            const bytes_read = try file.readAll(buf[0..]);
            if (bytes_read == 0) return null;
            cursor += bytes_read;
            if (std.mem.indexOf(u8, buf[0..bytes_read], "//zmpl:debug")) |index| {
                if (std.mem.indexOf(u8, buf[index..], "\n")) |line_index| {
                    try debug_writer.writeAll(buf[index .. index + line_index]);
                    break :outer;
                } else {
                    try debug_writer.writeAll(buf[0..bytes_read]);
                    while (cursor < size) {
                        const line_bytes_read = try file.read(buf[0..]);
                        if (std.mem.indexOf(u8, buf[0..line_bytes_read], "\n")) |line_index| {
                            try debug_writer.writeAll(buf[0..line_index]);
                            break :outer;
                        } else {
                            try debug_writer.writeAll(buf[0..line_bytes_read]);
                        }
                        cursor += line_bytes_read;
                    }
                }
            }
        }
    }

    if (debug_line_buf.items.len == 0) return null;
    return try debug_line_buf.toOwnedSlice();
}
