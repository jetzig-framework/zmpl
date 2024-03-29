@args email: *ZmplValue, subject: []const u8
<a href="mailto:{{email}}?subject={{subject}}">{{email}}</a>

@zig {
    for (slots, 0..) |slot, slot_index| {
        <div class="slot-{{slot_index}}">{{slot}}</div>
    }
}
