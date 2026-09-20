//! Data-driven personal weapons: defs in `data/putka/weapons/*.json`.
//! Engine integrates cooldown, projectile flight, wall impact and
//! hit-sweeps against NPC body circles.

const TileMap = @import("../world/map.zig").TileMap;
const Tiles = @import("../world/tiles.zig").Tiles;
const Vec2 = @import("../math/vec2.zig").Vec2;

pub const WeaponDef = struct {
    name: []const u8 = "pistol",
    damage: f32 = 34,
    range: f32 = 420,
    fire_interval: f32 = 0.22, // seconds between shots
    projectile_speed: f32 = 900,
};

pub fn loadDefJson(allocator: std.mem.Allocator, text: []const u8) !WeaponDef {
    const parsed = try std.json.parseFromSlice(WeaponDef, allocator, text, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return parsed.value;
}

pub const Shot = struct {
    pos: Vec2,
    vel: Vec2,
    left: f32, // remaining range
    damage: f32,
};

pub const Shots = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(Shot),

    pub fn init(allocator: std.mem.Allocator) Shots {
        return .{ .allocator = allocator, .items = .empty };
    }

    pub fn deinit(self: *Shots) void {
        self.items.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clearRetainingCapacity(self: *Shots) void {
        self.items.clearRetainingCapacity();
    }
};

pub const Gun = struct {
    def: WeaponDef,
    cooldown: f32 = 0,

    pub fn update(self: *Gun, dt: f32) void {
        self.cooldown = @max(0, self.cooldown - dt);
    }

    /// Returns true when a shot was actually spawned (noise/crime hook).
    pub fn tryFire(self: *Gun, shots: *Shots, origin: Vec2, dir: Vec2) !bool {
        if (self.cooldown > 0) return false;
        if (dir.lengthSq() < 1e-6) return false;
        const n = dir.normalized();
        self.cooldown = self.def.fire_interval;
        try shots.items.append(shots.allocator, .{
            .pos = origin,
            .vel = n.scale(self.def.projectile_speed),
            .left = self.def.range,
            .damage = self.def.damage,
        });
        return true;
    }
};

fn pointSolid(tiles: Tiles, p: Vec2) bool {
    const t = Tiles.worldToTile(p);
    const tile = tiles.get(t.x, t.y) orelse return true;
    return tile.solid or !tile.isWalkable();
}

/// Advance shots; walls and spent range remove them (swap-remove).
/// Moves in <=8px substeps so fast bullets cannot tunnel through walls.
pub fn updateShots(shots: *Shots, tiles: Tiles, dt: f32) void {
    var i = shots.items.items.len;
    while (i > 0) {
        i -= 1;
        const s = &shots.items.items[i];
        const dist = s.vel.length() * dt;
        const steps: u32 = @max(1, @as(u32, @intFromFloat(@ceil(dist / 8))));
        const h = dt / @as(f32, @floatFromInt(steps));
        var dead = s.left <= 0;
        var n: u32 = 0;
        while (n < steps and !dead) : (n += 1) {
            s.pos = s.pos.add(s.vel.scale(h));
            s.left -= s.vel.length() * h;
            if (s.left <= 0 or pointSolid(tiles, s.pos)) dead = true;
        }
        if (dead) _ = shots.items.swapRemove(i);
    }
}

const std = @import("std");

test "fire interval gates shots" {
    var shots = Shots.init(std.testing.allocator);
    defer shots.deinit();
    var gun = Gun{ .def = .{ .fire_interval = 0.5 } };
    const dir = Vec2{ .x = 1, .y = 0 };
    try std.testing.expect(try gun.tryFire(&shots, .{}, dir));
    try std.testing.expect(!(try gun.tryFire(&shots, .{}, dir)));
    try std.testing.expectEqual(@as(usize, 1), shots.items.items.len);
    gun.update(0.5);
    try std.testing.expect(try gun.tryFire(&shots, .{}, dir));
    try std.testing.expectEqual(@as(usize, 2), shots.items.items.len);
}

test "shots fly straight and die on walls/range" {
    var map = try TileMap.init(std.testing.allocator, 16, 16);
    defer map.deinit();
    const tiles = Tiles{ .single = &map };
    map.set(8, 2, .{ .type = .wall, .solid = true });
    var shots = Shots.init(std.testing.allocator);
    defer shots.deinit();
    var gun = Gun{ .def = .{ .projectile_speed = 320, .range = 10000 } };
    _ = try gun.tryFire(&shots, .{ .x = 0, .y = 2 * 32 + 16 }, .{ .x = 1, .y = 0 });
    updateShots(&shots, tiles, 0.5); // 160px, still flying
    try std.testing.expectEqual(@as(usize, 1), shots.items.items.len);
    updateShots(&shots, tiles, 1.0); // into the wall
    try std.testing.expectEqual(@as(usize, 0), shots.items.items.len);
}

test "pistol.json parses" {
    const def = try loadDefJson(std.testing.allocator,
        \\{"name":"pistol","damage":34.0,"fire_interval":0.22}
    );
    try std.testing.expectApproxEqAbs(@as(f32, 34), def.damage, 1e-4);
}
