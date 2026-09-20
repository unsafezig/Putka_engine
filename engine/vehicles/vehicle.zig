//! Arcade vehicle physics (GTA-style top-down).
//! Scalar speed along heading, steering scales with speed, axis-separated
//! collision. Tuning lives in data (`data/putka/vehicles/*.json`);
//! this file only integrates it.

const Intent = @import("../input/input.zig").Intent;
const TileMap = @import("../world/map.zig").TileMap;
const Tiles = @import("../world/tiles.zig").Tiles;
const isBoxBlocked = @import("../physics/collision.zig").isBoxBlocked;
const Aabb = @import("../math/aabb.zig").Aabb;
const Vec2 = @import("../math/vec2.zig").Vec2;

pub const Params = struct {
    name: []const u8 = "car",
    accel: f32 = 220,
    brake_decel: f32 = 320,
    max_speed: f32 = 340,
    reverse_max: f32 = 120,
    turn_rate: f32 = 2.6, // rad/s at full steer and full speed
    drag: f32 = 0.55, // 1/s proportional slowdown on road (accel/drag > max_speed)
    offroad_drag: f32 = 2.2, // extra 1/s when not on road/bridge
    length: f32 = 44,
    width: f32 = 22,
};

pub fn loadParamsJson(allocator: std.mem.Allocator, text: []const u8) !Params {
    const parsed = try std.json.parseFromSlice(Params, allocator, text, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return parsed.value;
}

pub const ENTER_RADIUS: f32 = 56.0;

pub const Vehicle = struct {
    pos: Vec2 = .{}, // center
    heading: f32 = 0, // radians, 0 = +x
    speed: f32 = 0, // signed, along heading
    driver: bool = false,

    pub fn forward(self: Vehicle) Vec2 {
        return .{ .x = @cos(self.heading), .y = @sin(self.heading) };
    }

    /// Intent.move doubles as drive input: up = throttle, x = steer.
    pub fn update(self: *Vehicle, tiles: Tiles, p: Params, intent: Intent, dt: f32) void {
        const throttle: f32 = -intent.move.y; // up key => +1
        const steer: f32 = intent.move.x;

        if (throttle > 0) {
            self.speed += p.accel * throttle * dt;
        } else if (throttle < 0) {
            if (self.speed > 1) {
                self.speed += p.brake_decel * throttle * dt; // braking
            } else {
                self.speed += p.accel * 0.6 * throttle * dt; // reverse
            }
        }
        self.speed = std.math.clamp(self.speed, -p.reverse_max, p.max_speed);

        // Steering needs motion; reversing flips it (like a real car).
        const grip: f32 = std.math.clamp(@abs(self.speed) / (p.max_speed * 0.35), 0, 1);
        const dir: f32 = if (self.speed >= 0) 1 else -1;
        self.heading += steer * p.turn_rate * grip * dir * dt;

        // Drag, harsher off-road.
        var drag = p.drag;
        const tc = Tiles.worldToTile(self.pos);
        if (tiles.get(tc.x, tc.y)) |t| {
            if (t.type != .road and t.type != .bridge) drag += p.offroad_drag;
        }
        self.speed -= self.speed * @min(drag * dt, 0.9);
        if (@abs(self.speed) < 2) self.speed = 0;

        // Integrate with axis-separated collision; walls kill speed.
        const half = Vec2{ .x = p.width * 0.4, .y = p.width * 0.4 };
        const d = self.forward().scale(self.speed * dt);
        const box_x = Aabb.fromCenterHalf(.{ .x = self.pos.x + d.x, .y = self.pos.y }, half);
        if (!isBoxBlocked(tiles, box_x)) {
            self.pos.x += d.x;
        } else {
            self.speed = 0;
        }
        const box_y = Aabb.fromCenterHalf(.{ .x = self.pos.x, .y = self.pos.y + d.y }, half);
        if (!isBoxBlocked(tiles, box_y)) {
            self.pos.y += d.y;
        } else {
            self.speed = 0;
        }
    }
};

/// Can the player at `player_center` step into `v`?
pub fn canEnter(player_center: Vec2, v: Vehicle) bool {
    if (v.driver) return false;
    return player_center.sub(v.pos).lengthSq() <= ENTER_RADIUS * ENTER_RADIUS;
}

/// Where the driver appears when stepping out (right side of the car).
pub fn exitSpot(v: Vehicle) Vec2 {
    const side = Vec2{ .x = -@sin(v.heading), .y = @cos(v.heading) };
    return v.pos.add(side.scale(30));
}

const std = @import("std");

fn openMap() !TileMap {
    return TileMap.init(std.testing.allocator, 32, 32);
}

/// Test car parked mid-field, away from map edges.
fn testCar() Vehicle {
    return .{ .pos = .{ .x = 16 * 32, .y = 16 * 32 } };
}

test "vehicle accelerates toward max speed" {
    var map = try TileMap.init(std.testing.allocator, 64, 8);
    defer map.deinit();
    const tiles = Tiles{ .single = &map };
    // Long paved straight so the car can wind out without hitting a wall.
    var x: i32 = 0;
    while (x < 64) : (x += 1) map.set(x, 4, .{ .type = .road });
    const p = Params{};
    var v = Vehicle{ .pos = .{ .x = 2 * 32, .y = 4 * 32 + 16 } };
    const gas = Intent{ .move = .{ .x = 0, .y = -1 } };
    var top: f32 = 0;
    var i: u32 = 0;
    while (i < 600) : (i += 1) {
        v.update(tiles, p, gas, 1.0 / 60.0);
        top = @max(top, v.speed);
    }
    try std.testing.expect(top > p.max_speed * 0.95);
    try std.testing.expect(v.pos.x > 2 * 32 + 200);
}

test "vehicle brakes and reverses" {
    var map = try openMap();
    defer map.deinit();
    const tiles = Tiles{ .single = &map };
    const p = Params{};
    var v = testCar();
    v.speed = 200;
    const brake = Intent{ .move = .{ .x = 0, .y = 1 } };
    var i: u32 = 0;
    while (i < 120) : (i += 1) v.update(tiles, p, brake, 1.0 / 60.0);
    try std.testing.expect(v.speed < 0); // came to stop, now reversing
}

test "no steering when stationary, steering at speed" {
    var map = try openMap();
    defer map.deinit();
    const tiles = Tiles{ .single = &map };
    const p = Params{};
    var v = testCar();
    const steer = Intent{ .move = .{ .x = 1, .y = 0 } };
    v.update(tiles, p, steer, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), v.heading, 1e-5);
    v.speed = p.max_speed;
    v.update(tiles, p, steer, 0.5);
    try std.testing.expect(v.heading > 1.0);
}

test "wall stops the car" {
    var map = try openMap();
    defer map.deinit();
    const tiles = Tiles{ .single = &map };
    map.set(10, 5, .{ .type = .wall, .solid = true }); // world x 320..
    const p = Params{};
    var v = Vehicle{ .pos = .{ .x = 200, .y = 5 * 32 + 16 }, .speed = 300 };
    const gas = Intent{ .move = .{ .x = 0, .y = -1 } };
    var i: u32 = 0;
    while (i < 120) : (i += 1) v.update(tiles, p, gas, 1.0 / 60.0);
    try std.testing.expect(v.pos.x + p.width * 0.4 <= 320.0 + 1e-3);
}

test "offroad is slower than road" {
    var map = try openMap();
    defer map.deinit();
    const tiles = Tiles{ .single = &map };
    const p = Params{};
    // Road tile under car A.
    map.set(2, 2, .{ .type = .road });
    var road = Vehicle{ .pos = .{ .x = 2 * 32 + 16, .y = 2 * 32 + 16 }, .speed = 200 };
    var grass = Vehicle{ .pos = .{ .x = 20 * 32 + 16, .y = 20 * 32 + 16 }, .speed = 200 };
    const coast = Intent{};
    road.update(tiles, p, coast, 1.0);
    grass.update(tiles, p, coast, 1.0);
    try std.testing.expect(grass.speed < road.speed);
}

test "enter radius and exit spot" {
    const v = Vehicle{ .pos = .{ .x = 100, .y = 100 } };
    try std.testing.expect(canEnter(.{ .x = 120, .y = 100 }, v));
    try std.testing.expect(!canEnter(.{ .x = 500, .y = 500 }, v));
    var driven = v;
    driven.driver = true;
    try std.testing.expect(!canEnter(.{ .x = 120, .y = 100 }, driven));
    const out = exitSpot(v);
    try std.testing.expect(out.sub(v.pos).length() > 10);
}

test "car.json parses" {
    const p = try loadParamsJson(std.testing.allocator,
        \\{"name":"sedan","accel":220.0,"max_speed":340.0}
    );
    try std.testing.expectApproxEqAbs(@as(f32, 220), p.accel, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 340), p.max_speed, 1e-4);
}
