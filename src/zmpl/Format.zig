const std = @import("std");

const jetcommon = @import("jetcommon");

const zmpl = @import("../zmpl.zig");

writer: zmpl.Data.Writer,

const Format = @This();

pub fn datetime(self: Format, value: anytype, comptime fmt: []const u8) ![]const u8 {
    const Type = switch (@typeInfo(@TypeOf(value))) {
        .pointer => |info| info.child,
        .optional => |info| switch (@typeInfo(info.child)) {
            .pointer => |ptr_info| ptr_info.child,
            else => info.child,
        },
        else => @TypeOf(value),
    };

    const reconciled_value = switch (@typeInfo(@TypeOf(value))) {
        .pointer => value.*,
        .optional => |info| switch (@typeInfo(info.child)) {
            .pointer => if (value) |capture| capture.* else return error.ZmplDateTimeFormatNull,
            else => value,
        },
        else => value,
    };

    const parsed_datetime = switch (Type) {
        zmpl.Data.Value => switch (reconciled_value) {
            .string => |val| try jetcommon.types.DateTime.parse(val.value),
            .datetime => |val| val.value,
            inline else => return zmpl.Data.zmplError(
                .type,
                "Cannot coerce `{s}` to datetime.",
                .{@tagName(reconciled_value)},
            ),
        },
        else => |T| @compileError(std.fmt.comptimePrint("Unsupported type: `{s}`", .{@typeName(T)})),
    };

    try parsed_datetime.strftime(self.writer, fmt);
    return ""; // We use the writer to output but Zmpl expects a string returned by `{{foo}}`
}
