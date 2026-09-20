//! Generational handle: index + generation. Stale handles never alias
//! a recycled slot.

pub const EntityId = struct {
    index: u32 = std.math.maxInt(u32),
    generation: u32 = 0,

    pub const NULL: EntityId = .{};

    pub fn isNull(self: EntityId) bool {
        return self.index == std.math.maxInt(u32);
    }

    pub fn eql(a: EntityId, b: EntityId) bool {
        return a.index == b.index and a.generation == b.generation;
    }
};

const std = @import("std");

test "null handle" {
    try std.testing.expect(EntityId.NULL.isNull());
    try std.testing.expect(!(EntityId{ .index = 0, .generation = 1 }).isNull());
}
