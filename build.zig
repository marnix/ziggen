const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    var test_step = b.addTest("ziggen.zig");
    test_step.test_evented_io = true;
    b.default_step.dependOn(&test_step.step);
}
