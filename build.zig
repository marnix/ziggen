const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    var test_step_1 = b.addTest("ziggen.zig");
    test_step_1.test_evented_io = false;
    b.default_step.dependOn(&test_step_1.step);

    var test_step_2 = b.addTest("ziggen.zig");
    test_step_2.test_evented_io = true;
    b.default_step.dependOn(&test_step_2.step);
}
