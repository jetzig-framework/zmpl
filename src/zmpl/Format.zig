const std = @import("std");

const jetcommon = @import("jetcommon");

const zmpl = @import("../zmpl.zig");

writer: zmpl.Data.Writer,

const Format = @This();

pub const FormatType = enum { default };

pub fn datetime(self: Format, value: anytype, fmt: FormatType) ![]const u8 {
    _ = fmt;
    const Type = switch (@typeInfo(@TypeOf(value))) {
        .pointer => |info| info.child,
        inline else => @TypeOf(value),
    };

    const reconciled_value = switch (@typeInfo(@TypeOf(value))) {
        .pointer => value.*,
        inline else => value,
    };

    const parsed_datetime = switch (Type) {
        zmpl.Data.Value => switch (reconciled_value) {
            .string => |val| try jetcommon.types.DateTime.parse(val.value),
            inline else => return zmpl.Data.zmplError(
                .type,
                "Cannot coerce `{s}` to datetime.",
                .{@tagName(reconciled_value)},
            ),
        },
        else => |T| @compileError(std.fmt.comptimePrint("Unsupported type: `{s}`", .{@typeName(T)})),
    };

    try parsed_datetime.strftime(self.writer, "%c");
    return ""; // We use the writer to output but Zmpl expects a string returned by `{{foo}}`
}
