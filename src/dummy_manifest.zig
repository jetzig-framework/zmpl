pub const __Manifest = struct {
    pub const Template = struct {};
    pub fn find(_: []const u8) ?Template {
        return null;
    }
    pub fn findPrefixed(_: []const u8, _: []const u8) ?Template {
        return null;
    }
};
