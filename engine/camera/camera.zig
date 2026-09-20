//! Top-down follow camera. Independent from rendering and gameplay.

const Vec2 = @import("../math/vec2.zig").Vec2;

pub const CameraMode = enum { player, vehicle, mission, cinematic };

pub const Camera2D = struct {
    center: Vec2 = .{},
    zoom: f32 = 2.0,
    mode: CameraMode = .player,

    pub fn follow(self: *Camera2D, target: Vec2) void {
        self.center = target;
    }

    /// World position of screen point. `screen_size` in pixels,
    /// `screen_point` pixel offset from top-left.
    pub fn screenToWorld(self: Camera2D, screen_size: Vec2, screen_point: Vec2) Vec2 {
        const half = screen_size.scale(0.5 / self.zoom);
        const offset = screen_point.scale(1.0 / self.zoom);
        return .{
            .x = self.center.x - half.x + offset.x,
            .y = self.center.y - half.y + offset.y,
        };
    }

    pub fn worldToScreen(self: Camera2D, screen_size: Vec2, world: Vec2) Vec2 {
        const half = screen_size.scale(0.5 / self.zoom);
        const rel = world.sub(self.center);
        return .{
            .x = (rel.x + half.x) * self.zoom,
            .y = (rel.y + half.y) * self.zoom,
        };
    }
};

const std = @import("std");

test "camera roundtrip" {
    var cam = Camera2D{ .center = .{ .x = 100, .y = 50 }, .zoom = 2.0 };
    cam.follow(.{ .x = 10, .y = 20 });
    try std.testing.expect(cam.center.eql(.{ .x = 10, .y = 20 }));
    const size: Vec2 = .{ .x = 800, .y = 450 };
    const w: Vec2 = .{ .x = 15, .y = 25 };
    const s = cam.worldToScreen(size, w);
    const back = cam.screenToWorld(size, s);
    try std.testing.expectApproxEqAbs(w.x, back.x, 1e-4);
    try std.testing.expectApproxEqAbs(w.y, back.y, 1e-4);
}
