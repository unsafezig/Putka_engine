//! Police pursuit: foot patrol officers that chase when wanted > 0
//! and complete an arrest on sustained contact. Game logic turns the
//! arrest event into consequences (BUSTED, fines, reset).

const Faction = @import("../factions/factions.zig").Faction;
const TileMap = @import("../world/map.zig").TileMap;
const Tiles = @import("../world/tiles.zig").Tiles;
const moveBox = @import("../physics/collision.zig").moveBox;
const Vec2 = @import("../math/vec2.zig").Vec2;

pub const OFFICER_SIZE: Vec2 = .{ .x = 18, .y = 18 };
pub const PATROL_SPEED: f32 = 70;
pub const CHASE_SPEED: f32 = 205;
pub const ARREST_RADIUS: f32 = 30;
pub const ARREST_TIME: f32 = 2.0;

pub const OfficerState = enum { patrol, chase };

pub const Officer = struct {
    pos: Vec2 = .{},
    dir: Vec2 = .{ .x = 1, .y = 0 },
    state: OfficerState = .patrol,
    faction: Faction = .police,
    wander_timer: f32 = 2,
    arrest_progress: f32 = 0,
    /// Gait phase in radians (rendering bob).
    phase: f32 = 0,

    pub fn center(self: Officer) Vec2 {
        return .{ .x = self.pos.x + OFFICER_SIZE.x * 0.5, .y = self.pos.y + OFFICER_SIZE.y * 0.5 };
    }

    /// Returns true when an arrest completes on this step.
    pub fn update(
        self: *Officer,
        tiles: Tiles,
        rand: *std.Random,
        dt: f32,
        target: Vec2,
        wanted_level: u8,
    ) bool {
        if (wanted_level == 0 and self.state == .chase) {
            self.state = .patrol;
            self.arrest_progress = 0;
            self.wander_timer = 1;
        } else if (wanted_level > 0 and self.state == .patrol) {
            self.state = .chase;
            self.arrest_progress = 0;
        }

        switch (self.state) {
            .patrol => {
                _ = moveBox(tiles, &self.pos, OFFICER_SIZE, self.dir.scale(PATROL_SPEED * dt));
                self.phase += dt * PATROL_SPEED * 0.12;
                self.wander_timer -= dt;
                if (self.wander_timer <= 0) {
                    const a = rand.float(f32) * std.math.pi * 2;
                    self.dir = .{ .x = @cos(a), .y = @sin(a) };
                    self.wander_timer = 2 + rand.float(f32) * 3;
                }
            },
            .chase => {
                const to = target.sub(self.center());
                const dist = to.length();
                if (dist > 1e-3) {
                    self.dir = to.scale(1 / dist);
                    _ = moveBox(tiles, &self.pos, OFFICER_SIZE, self.dir.scale(CHASE_SPEED * dt));
                    self.phase += dt * CHASE_SPEED * 0.12;
                }
                if (dist <= ARREST_RADIUS) {
                    self.arrest_progress += dt;
                    if (self.arrest_progress >= ARREST_TIME) {
                        self.arrest_progress = 0;
                        return true;
                    }
                } else {
                    self.arrest_progress = @max(0, self.arrest_progress - dt);
                }
            },
        }
        return false;
    }
};

const std = @import("std");

fn testRand(seed: u64) std.Random.DefaultPrng {
    return std.Random.DefaultPrng.init(seed);
}

test "officer patrols, chases when wanted, stands down after" {
    var map = try TileMap.init(std.testing.allocator, 32, 32);
    defer map.deinit();
    const tiles = Tiles{ .single = &map };
    var prng = testRand(7);
    var r = prng.random();
    var o = Officer{ .pos = .{ .x = 500, .y = 500 } };
    try std.testing.expect(o.update(tiles, &r, 1.0, .{ .x = 0, .y = 0 }, 0) == false);
    try std.testing.expect(o.state == .patrol);
    _ = o.update(tiles, &r, 0.016, .{ .x = 0, .y = 0 }, 2);
    try std.testing.expect(o.state == .chase);
    _ = o.update(tiles, &r, 0.016, .{ .x = 0, .y = 0 }, 0);
    try std.testing.expect(o.state == .patrol);
}

test "chase closes distance" {
    var map = try TileMap.init(std.testing.allocator, 64, 64);
    defer map.deinit();
    const tiles = Tiles{ .single = &map };
    var prng = testRand(8);
    var r = prng.random();
    var o = Officer{ .pos = .{ .x = 100, .y = 100 } };
    const target = Vec2{ .x = 900, .y = 900 };
    const d0 = o.center().sub(target).length();
    var i: u32 = 0;
    while (i < 60) : (i += 1) _ = o.update(tiles, &r, 1.0 / 60.0, target, 1);
    const d1 = o.center().sub(target).length();
    try std.testing.expect(d1 < d0 - 100);
}

test "sustained contact completes arrest, distance resets it" {
    var map = try TileMap.init(std.testing.allocator, 32, 32);
    defer map.deinit();
    const tiles = Tiles{ .single = &map };
    var prng = testRand(9);
    var r = prng.random();
    // Officer center sits exactly on the target: contact every step.
    var o = Officer{ .pos = .{ .x = 500 - OFFICER_SIZE.x * 0.5, .y = 500 - OFFICER_SIZE.y * 0.5 } };
    const target = Vec2{ .x = 500, .y = 500 };
    var done = false;
    var i: u32 = 0;
    while (i < 200) : (i += 1) {
        if (o.update(tiles, &r, 1.0 / 60.0, target, 1)) {
            done = true;
            break;
        }
    }
    try std.testing.expect(done);

    // Breaking contact drains progress: 1s of contact then far away.
    var o2 = Officer{ .pos = .{ .x = 500 - OFFICER_SIZE.x * 0.5, .y = 500 - OFFICER_SIZE.y * 0.5 } };
    i = 0;
    while (i < 60) : (i += 1) _ = o2.update(tiles, &r, 1.0 / 60.0, target, 1);
    try std.testing.expect(o2.arrest_progress > 0.5);
    _ = o2.update(tiles, &r, 5.0, .{ .x = 0, .y = 0 }, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 0), o2.arrest_progress, 1e-4);
}
