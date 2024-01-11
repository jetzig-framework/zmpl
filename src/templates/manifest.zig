pub const templates = struct {
  pub const example = @import(".example.zmpl.compiled.zig");
  pub const example_with_array_data_lookup = @import(".example_with_array_data_lookup.zmpl.compiled.zig");
  pub const example_with_root_array = @import(".example_with_root_array.zmpl.compiled.zig");
  pub const example_with_deep_nesting = @import(".example_with_deep_nesting.zmpl.compiled.zig");
  pub const example_with_nested_data_lookup = @import(".example_with_nested_data_lookup.zmpl.compiled.zig");
  pub const example_with_quotes = @import(".example_with_quotes.zmpl.compiled.zig");
  pub const example_with_iteration = @import(".example_with_iteration.zmpl.compiled.zig");
};
