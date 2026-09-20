//! 2D vector: minimal ops needed for top-down movement, camera and physics.
//! Favor plain Zig over abstraction.

pub const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    pub fn scale(a: Vec2, s: f32) Vec2 {
        return .{ .x = a.x * s, .y = a.y * s };
    }

    pub fn lengthSq(a: Vec2) f32 {
        return a.x * a.x + a.y * a.y;
    }

    pub fn length(a: Vec2) f32 {
        return @sqrt(a.lengthSq());
    }

    pub fn normalized(a: Vec2) Vec2 {
        const len = a.length();
        if (len < 1e-6) return .{};
        return a.scale(1.0 / len);
    }

    pub fn eql(a: Vec2, b: Vec2) bool {
        return a.x == b.x and a.y == b.y;
    }
};

const std = @import("std");

test "vec2 add/sub/scale" {
    const a: Vec2 = .{ .x = 1, .y = 2 };
    const b: Vec2 = .{ .x = 3, .y = -1 };
    try std.testing.expect((Vec2.add(a, b)).eql(.{ .x = 4, .y = 1 }));
    try std.testing.expect((Vec2.sub(a, b)).eql(.{ .x = -2, .y = 3 }));
    try std.testing.expect((a.scale(2)).eql(.{ .x = 2, .y = 4 }));
}

test "vec2 normalized zero stays zero" {
    const z: Vec2 = .{};
    try std.testing.expect(z.normalized().eql(.{}));
    const v: Vec2 = .{ .x = 3, .y = 4 };
    const n = v.normalized();
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), n.length(), 1e-5);
}
