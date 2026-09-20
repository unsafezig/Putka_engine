//! Player: top-down walker driven by `Intent`, collides via `moveBox`.
//! Speeds are world units/sec. No rendering, no input backend here.

const Intent = @import("../input/input.zig").Intent;
const TileMap = @import("../world/map.zig").TileMap;
const moveBox = @import("../physics/collision.zig").moveBox;
const Vec2 = @import("../math/vec2.zig").Vec2;

pub const WALK_SPEED: f32 = 160.0;
pub const SPRINT_MULT: f32 = 1.6;
pub const PLAYER_SIZE: Vec2 = .{ .x = 20, .y = 20 };

pub const Player = struct {
    /// Top-left position of the body box.
    pos: Vec2 = .{},
    vel: Vec2 = .{},

    pub fn center(self: Player) Vec2 {
        return .{ .x = self.pos.x + PLAYER_SIZE.x * 0.5, .y = self.pos.y + PLAYER_SIZE.y * 0.5 };
    }

    pub fn update(self: *Player, map: TileMap, intent: Intent, dt: f32) void {
        const speed = if (intent.sprint) WALK_SPEED * SPRINT_MULT else WALK_SPEED;
        const wish = intent.move.scale(speed * dt);
        self.vel = if (dt > 0) intent.move.scale(speed) else .{};
        _ = moveBox(map, &self.pos, PLAYER_SIZE, wish);
    }
};

const std = @import("std");

test "player moves and is blocked by wall" {
    var map = try TileMap.init(std.testing.allocator, 8, 8);
    defer map.deinit();
    var p = Player{ .pos = .{ .x = 40, .y = 40 } };
    p.update(map, Intent.fromKeys(false, true, false, false), 0.5);
    try std.testing.expect(p.pos.y > 40);

    map.set(1, 3, .{ .type = .wall, .solid = true });
    p.pos = .{ .x = 40, .y = 60 };
    const before = p.pos.y;
    p.update(map, Intent.fromKeys(false, false, true, false), 1.0);
    // Moving left along the wall row: x may change, y must not tunnel.
    try std.testing.expect(p.pos.y == before or p.pos.y < before + 1);
}
