//! Collision primitives: AABB + Circle. Rendering-independent.

const Vec2 = @import("vec2.zig").Vec2;

pub const Aabb = struct {
    min: Vec2,
    max: Vec2,

    pub fn fromCenterHalf(center: Vec2, half: Vec2) Aabb {
        return .{
            .min = .{ .x = center.x - half.x, .y = center.y - half.y },
            .max = .{ .x = center.x + half.x, .y = center.y + half.y },
        };
    }

    pub fn fromPosSize(pos: Vec2, size: Vec2) Aabb {
        return .{
            .min = pos,
            .max = .{ .x = pos.x + size.x, .y = pos.y + size.y },
        };
    }

    pub fn overlaps(a: Aabb, b: Aabb) bool {
        return a.min.x < b.max.x and a.max.x > b.min.x and
            a.min.y < b.max.y and a.max.y > b.min.y;
    }

    pub fn containsPoint(box: Aabb, p: Vec2) bool {
        return p.x >= box.min.x and p.x <= box.max.x and
            p.y >= box.min.y and p.y <= box.max.y;
    }
};

pub const Circle = struct {
    center: Vec2,
    radius: f32,

    pub fn overlapsAabb(c: Circle, box: Aabb) bool {
        const cx: f32 = @max(box.min.x, @min(c.center.x, box.max.x));
        const cy: f32 = @max(box.min.y, @min(c.center.y, box.max.y));
        const dx = c.center.x - cx;
        const dy = c.center.y - cy;
        return dx * dx + dy * dy <= c.radius * c.radius;
    }
};

const std = @import("std");

test "aabb overlaps" {
    const a = Aabb.fromPosSize(.{ .x = 0, .y = 0 }, .{ .x = 10, .y = 10 });
    const b = Aabb.fromPosSize(.{ .x = 5, .y = 5 }, .{ .x = 10, .y = 10 });
    const c = Aabb.fromPosSize(.{ .x = 20, .y = 20 }, .{ .x = 5, .y = 5 });
    try std.testing.expect(a.overlaps(b));
    try std.testing.expect(!a.overlaps(c));
}

test "circle vs aabb" {
    const box = Aabb.fromPosSize(.{ .x = 0, .y = 0 }, .{ .x = 10, .y = 10 });
    try std.testing.expect((Circle{ .center = .{ .x = 5, .y = 5 }, .radius = 1 }).overlapsAabb(box));
    try std.testing.expect(!(Circle{ .center = .{ .x = 20, .y = 20 }, .radius = 2 }).overlapsAabb(box));
}
