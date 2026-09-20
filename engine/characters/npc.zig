//! Deterministic pedestrian AI (no LLMs): idle/walk/panic.
//! Randomness is injected (`*std.Random`) so tests seed it and gameplay
//! can seed per-run. Combat couples via `Threat` and `sweepShots`.

const Faction = @import("../factions/factions.zig").Faction;
const TileMap = @import("../world/map.zig").TileMap;
const moveBox = @import("../physics/collision.zig").moveBox;
const Shots = @import("../weapons/weapon.zig").Shots;
const Vec2 = @import("../math/vec2.zig").Vec2;

pub const NPC_SIZE: Vec2 = .{ .x = 18, .y = 18 };
pub const BODY_RADIUS: f32 = 12;

pub const WALK_SPEED: f32 = 55;
pub const PANIC_SPEED: f32 = 175;
pub const HEAR_RADIUS: f32 = 280;
pub const CAR_SCARE_RADIUS: f32 = 130;
pub const RUNOVER_SPEED: f32 = 150;

pub const State = enum { idle, walk, panic };

pub const ThreatKind = enum { gunshot, car };

pub const Threat = struct {
    pos: Vec2,
    kind: ThreatKind,
};

pub const Npc = struct {
    pos: Vec2 = .{}, // top-left of body box
    dir: Vec2 = .{ .x = 1, .y = 0 },
    state: State = .idle,
    hp: f32 = 100,
    faction: Faction = .civilians,
    timer: f32 = 1,
    flee_from: Vec2 = .{},
    dead: bool = false,

    pub fn center(self: Npc) Vec2 {
        return .{ .x = self.pos.x + NPC_SIZE.x * 0.5, .y = self.pos.y + NPC_SIZE.y * 0.5 };
    }

    /// Returns true if this blow killed.
    pub fn damage(self: *Npc, amount: f32) bool {
        if (self.dead) return false;
        self.hp -= amount;
        if (self.hp <= 0) {
            self.dead = true;
            return true;
        }
        return false;
    }

    fn startPanic(self: *Npc, from: Vec2) void {
        self.state = .panic;
        self.flee_from = from;
        self.timer = 4;
    }

    fn pickWander(self: *Npc, rand: *std.Random) void {
        const a = rand.float(f32) * std.math.pi * 2;
        self.dir = .{ .x = @cos(a), .y = @sin(a) };
        self.state = .walk;
        self.timer = 2 + rand.float(f32) * 3;
    }

    pub fn update(self: *Npc, map: TileMap, rand: *std.Random, dt: f32, threat: ?Threat) void {
        if (self.dead) return;
        // React to the world before acting.
        if (threat) |t| {
            const d2 = self.center().sub(t.pos).lengthSq();
            switch (t.kind) {
                .gunshot => {
                    if (d2 <= HEAR_RADIUS * HEAR_RADIUS) self.startPanic(t.pos);
                },
                .car => {
                    if (d2 <= CAR_SCARE_RADIUS * CAR_SCARE_RADIUS) self.startPanic(t.pos);
                },
            }
        }
        switch (self.state) {
            .idle => {
                self.timer -= dt;
                if (self.timer <= 0) self.pickWander(rand);
            },
            .walk => {
                _ = moveBox(map, &self.pos, NPC_SIZE, self.dir.scale(WALK_SPEED * dt));
                self.timer -= dt;
                if (self.timer <= 0) {
                    self.state = .idle;
                    self.timer = 1 + rand.float(f32) * 2;
                } else if (rand.float(f32) < dt * 0.4) {
                    self.pickWander(rand); // occasionally change mind
                }
            },
            .panic => {
                const away = self.center().sub(self.flee_from).normalized();
                _ = moveBox(map, &self.pos, NPC_SIZE, away.scale(PANIC_SPEED * dt));
                self.dir = away;
                self.timer -= dt;
                if (self.timer <= 0) {
                    self.state = .idle;
                    self.timer = 1;
                }
            },
        }
    }
};

pub const SweepResult = struct {
    hits: u32 = 0,
    kills: u32 = 0,
    /// Factions of the killed (truncated at 8 per step; `kills` is exact).
    killed: [8]Faction = undefined,
    killed_count: u8 = 0,
};

/// Bullets vs bodies. Removes shots that connect.
pub fn sweepShots(shots: *Shots, npcs: []Npc) SweepResult {
    var res = SweepResult{};
    var i = shots.items.items.len;
    while (i > 0) {
        i -= 1;
        const s = shots.items.items[i];
        var connected = false;
        for (npcs) |*n| {
            if (n.dead) continue;
            if (s.pos.sub(n.center()).lengthSq() <= BODY_RADIUS * BODY_RADIUS) {
                connected = true;
                res.hits += 1;
                if (n.damage(s.damage)) {
                    res.kills += 1;
                    if (res.killed_count < res.killed.len) {
                        res.killed[res.killed_count] = n.faction;
                        res.killed_count += 1;
                    }
                }
                break;
            }
        }
        if (connected) _ = shots.items.swapRemove(i);
    }
    return res;
}

/// Fast car + contact = death. Returns true on a fresh kill.
pub fn checkRunOver(n: *Npc, car_pos: Vec2, car_radius: f32, speed: f32) bool {
    if (n.dead) return false;
    if (@abs(speed) < RUNOVER_SPEED) return false;
    const rr = car_radius + BODY_RADIUS;
    if (n.center().sub(car_pos).lengthSq() > rr * rr) return false;
    n.hp = 0;
    n.dead = true;
    return true;
}

const std = @import("std");

fn testRand(seed: u64) std.Random.DefaultPrng {
    return std.Random.DefaultPrng.init(seed);
}

test "npc wanders when idle expires" {
    var map = try TileMap.init(std.testing.allocator, 16, 16);
    defer map.deinit();
    var prng = testRand(1);
    var r = prng.random();
    var n = Npc{ .pos = .{ .x = 100, .y = 100 }, .timer = 0 };
    n.update(map, &r, 0.016, null);
    try std.testing.expect(n.state == .walk);
    const before = n.pos;
    n.update(map, &r, 1.0, null);
    try std.testing.expect(!n.pos.eql(before));
}

test "gunshot nearby causes panic, far one ignored" {
    var map = try TileMap.init(std.testing.allocator, 32, 32);
    defer map.deinit();
    var prng = testRand(2);
    var r = prng.random();
    var n = Npc{ .pos = .{ .x = 500, .y = 500 } };
    n.update(map, &r, 0.016, .{ .pos = .{ .x = 5000, .y = 5000 }, .kind = .gunshot });
    try std.testing.expect(n.state == .idle);
    const threatened = Threat{ .pos = .{ .x = 520, .y = 500 }, .kind = .gunshot };
    n.update(map, &r, 0.016, threatened);
    try std.testing.expect(n.state == .panic);
    const before = n.pos.x;
    n.update(map, &r, 1.0, null);
    try std.testing.expect(n.pos.x < before); // fled away from threat at +x
}

test "damage kills at zero hp" {
    var n = Npc{};
    try std.testing.expect(!n.damage(30));
    try std.testing.expect(n.damage(80));
    try std.testing.expect(n.dead);
}

test "sweep connects shots to bodies" {
    var shots = Shots.init(std.testing.allocator);
    defer shots.deinit();
    try shots.items.append(std.testing.allocator, .{
        .pos = .{ .x = 100, .y = 100 },
        .vel = .{ .x = 1, .y = 0 },
        .left = 100,
        .damage = 100,
    });
    var npcs = [_]Npc{.{ .pos = .{ .x = 100 - NPC_SIZE.x * 0.5, .y = 100 - NPC_SIZE.y * 0.5 }, .faction = .gang_a }};
    const res = sweepShots(&shots, &npcs);
    try std.testing.expectEqual(@as(u32, 1), res.hits);
    try std.testing.expectEqual(@as(u32, 1), res.kills);
    try std.testing.expectEqual(@as(u8, 1), res.killed_count);
    try std.testing.expect(res.killed[0] == .gang_a);
    try std.testing.expectEqual(@as(usize, 0), shots.items.items.len);
}

test "runover needs speed and contact" {
    var n = Npc{ .pos = .{ .x = 100, .y = 100 } };
    try std.testing.expect(!checkRunOver(&n, .{ .x = 109, .y = 109 }, 16, 50));
    try std.testing.expect(!n.dead);
    try std.testing.expect(checkRunOver(&n, .{ .x = 109, .y = 109 }, 16, 300));
    try std.testing.expect(n.dead);
}
