const std = @import("std");
const Build = std.Build;
const builtin = @import("builtin");

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const use_llvm = b.option(bool, "use_llvm", "Use LLVM") orelse true;
}
