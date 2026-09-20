//! World: a dense rectangle of sectors forming a city.
//! Districts come from data (`data/putka/maps/districts.json`):
//! a grid of block types, roads auto-paved along sector borders.
//!
//! ```json
//! {"name":"downtown","sector_size":16,"grid":["RCR","CPC","RCR"]}
//! ```
//! Block types: `R` residential, `C` commercial, `P` park.

const Sector = @import("sector.zig").Sector;
const Tile = @import("tile.zig").Tile;
const map_mod = @import("map.zig");
const TileMap = map_mod.TileMap;
const TILE_SIZE = map_mod.TILE_SIZE;
const Vec2 = @import("../math/vec2.zig").Vec2;
const Aabb = @import("../math/aabb.zig").Aabb;

pub const WorldError = error{ NoGrid, UnevenGrid, UnknownBlock, BadSectorSize };

const DistrictsJson = struct {
    name: []const u8 = "",
    sector_size: u32 = 16,
    grid: []const []const u8 = &.{},
};

pub const World = struct {
    alloc: std.mem.Allocator,
    sector_size: u32,
    wide: u32,
    high: u32,
    sectors: []Sector,
    active: []bool,

    pub fn deinit(self: *World) void {
        for (self.sectors) |*s| s.deinit();
        self.alloc.free(self.sectors);
        self.alloc.free(self.active);
        self.* = undefined;
    }

    pub fn sectorCount(self: World) usize {
        return self.sectors.len;
    }

    pub fn activeCount(self: World) usize {
        var n: usize = 0;
        for (self.active) |a| {
            if (a) n += 1;
        }
        return n;
    }

    fn at(self: World, sx: i32, sy: i32) ?*Sector {
        if (sx < 0 or sy < 0 or sx >= self.wide or sy >= self.high) return null;
        return &self.sectors[@as(usize, @intCast(sy)) * self.wide + @as(usize, @intCast(sx))];
    }

    fn atConst(self: *const World, sx: i32, sy: i32) ?*const Sector {
        if (sx < 0 or sy < 0 or sx >= self.wide or sy >= self.high) return null;
        return &self.sectors[@as(usize, @intCast(sy)) * self.wide + @as(usize, @intCast(sx))];
    }

    /// Global tile lookup across sector borders. Null outside the world.
    pub fn get(self: *const World, tx: i32, ty: i32) ?Tile {
        const c = Sector.containing(self.sector_size, tx, ty);
        const s = self.atConst(c.sx, c.sy) orelse return null;
        const l = Sector.localTile(self.sector_size, tx, ty);
        return s.map.get(l.x, l.y);
    }

    pub fn worldToTile(_: *const World, world: Vec2) struct { x: i32, y: i32 } {
        return .{
            .x = @as(i32, @intFromFloat(@floor(world.x / TILE_SIZE))),
            .y = @as(i32, @intFromFloat(@floor(world.y / TILE_SIZE))),
        };
    }

    /// Mark sectors within Chebyshev `radius` of `center` active.
    /// Returns the active count (streaming budget signal).
    pub fn activeAround(self: *World, center: Vec2, radius: u32) usize {
        const t = self.worldToTile(center);
        const c = Sector.containing(self.sector_size, t.x, t.y);
        const r: i32 = @intCast(radius);
        var n: usize = 0;
        for (self.sectors, 0..) |*s, i| {
            const dx: i32 = @intCast(@abs(s.sx - c.sx));
            const dy: i32 = @intCast(@abs(s.sy - c.sy));
            const on = dx <= r and dy <= r;
            self.active[i] = on;
            if (on) n += 1;
        }
        return n;
    }

    pub fn sectorActiveAt(self: *const World, world: Vec2) bool {
        const t = self.worldToTile(world);
        const c = Sector.containing(self.sector_size, t.x, t.y);
        const s = self.atConst(c.sx, c.sy) orelse return false;
        const idx = @as(usize, @intCast(s.sy)) * self.wide + @as(usize, @intCast(s.sx));
        return self.active[idx];
    }

    /// Whole-world bounds in world units (for camera/debug).
    pub fn bounds(self: World) Aabb {
        const w: f32 = @floatFromInt(self.wide * self.sector_size);
        const h: f32 = @floatFromInt(self.high * self.sector_size);
        return Aabb.fromPosSize(.{}, .{ .x = w * TILE_SIZE, .y = h * TILE_SIZE });
    }
};

/// Build a world from a districts description. Roads pave every sector's
/// top row and left column so the grid connects; interiors by block type.
pub fn loadWorldJson(alloc: std.mem.Allocator, text: []const u8) !World {
    const parsed = try std.json.parseFromSlice(DistrictsJson, alloc, text, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    const j = parsed.value;
    if (j.grid.len == 0) return WorldError.NoGrid;
    if (j.sector_size < 8 or j.sector_size > 64) return WorldError.BadSectorSize;
    const wide: u32 = @intCast(j.grid[0].len);
    const high: u32 = @intCast(j.grid.len);
    if (wide == 0) return WorldError.NoGrid;

    var world = World{
        .alloc = alloc,
        .sector_size = j.sector_size,
        .wide = wide,
        .high = high,
        .sectors = try alloc.alloc(Sector, @as(usize, wide) * high),
        .active = try alloc.alloc(bool, @as(usize, wide) * high),
    };
    var done: usize = 0;
    errdefer {
        for (world.sectors[0..done]) |*s| s.deinit();
        alloc.free(world.sectors);
        alloc.free(world.active);
    }
    @memset(world.active, true);
    var sy: u32 = 0;
    while (sy < high) : (sy += 1) {
        if (j.grid[sy].len != wide) return WorldError.UnevenGrid;
        var sx: u32 = 0;
        while (sx < wide) : (sx += 1) {
            const idx = @as(usize, sy) * wide + sx;
            world.sectors[idx] = try Sector.init(alloc, @intCast(sx), @intCast(sy), j.sector_size);
            done = idx + 1;
            try paveSector(&world.sectors[idx], j.grid[sy][sx]);
        }
    }
    return world;
}

fn paveSector(s: *Sector, block: u8) !void {
    const size: i32 = @intCast(s.size());
    // Border roads: top row + left column connect the whole grid.
    var i: i32 = 0;
    while (i < size) : (i += 1) {
        s.map.set(i, 0, .{ .type = .road });
        s.map.set(0, i, .{ .type = .road });
    }
    switch (block) {
        'R' => { // residential: building blocks in the interior corners
            const spots = [_]struct { x: i32, y: i32 }{ .{ .x = 3, .y = 3 }, .{ .x = size - 6, .y = 3 }, .{ .x = 3, .y = size - 5 }, .{ .x = size - 6, .y = size - 5 } };
            for (spots) |b| {
                var dy: i32 = 0;
                while (dy < 2) : (dy += 1) {
                    var dx: i32 = 0;
                    while (dx < 3) : (dx += 1) {
                        s.map.set(b.x + dx, b.y + dy, .{ .type = .building, .solid = true });
                    }
                }
            }
        },
        'C' => { // commercial: big central block + sidewalk ring
            var y: i32 = 4;
            while (y < size - 4) : (y += 1) {
                var x: i32 = 4;
                while (x < size - 4) : (x += 1) {
                    const edge = x == 4 or y == 4 or x == size - 5 or y == size - 5;
                    s.map.set(x, y, if (edge) .{ .type = .sidewalk } else .{ .type = .building, .solid = true });
                }
            }
        },
        'P' => { // park: grass with a sidewalk cross
            const mid: i32 = @divTrunc(size, 2);
            var k: i32 = 1;
            while (k < size) : (k += 1) {
                s.map.set(k, mid, .{ .type = .sidewalk });
                s.map.set(mid, k, .{ .type = .sidewalk });
            }
        },
        else => return WorldError.UnknownBlock,
    }
}

const std = @import("std");

test "districts load: borders connect, interiors differ" {
    const text =
        \\{"name":"t","sector_size":16,"grid":["RC","PR"]}
    ;
    var w = try loadWorldJson(std.testing.allocator, text);
    defer w.deinit();
    try std.testing.expectEqual(@as(usize, 4), w.sectorCount());
    // Border roads: sector (1,0) top row is road across the seam.
    try std.testing.expect(w.get(16, 0).?.type == .road);
    try std.testing.expect(w.get(0, 16).?.type == .road);
    // Residential interior has solid buildings; park does not.
    try std.testing.expect(w.get(3, 3).?.solid);
    try std.testing.expect(!w.get(3, 19).?.solid);
    try std.testing.expect(w.get(3, 19).?.type == .grass);
    // Outside the world: null.
    try std.testing.expect(w.get(-1, 0) == null);
    try std.testing.expect(w.get(100, 100) == null);
}

test "activeAround flags a 3x3 neighborhood" {
    var w = try loadWorldJson(std.testing.allocator,
        \\{"sector_size":8,"grid":["RRR","RRR","RRR"]}
    );
    defer w.deinit();
    // Center of the middle sector.
    const n = w.activeAround(.{ .x = 12 * 32, .y = 12 * 32 }, 1);
    try std.testing.expectEqual(@as(usize, 9), n);
    try std.testing.expect(w.sectorActiveAt(.{ .x = 0, .y = 0 }));
    const m = w.activeAround(.{ .x = 2 * 32, .y = 2 * 32 }, 0);
    try std.testing.expectEqual(@as(usize, 1), m);
    try std.testing.expect(!w.sectorActiveAt(.{ .x = 20 * 32, .y = 20 * 32 }));
}

test "bad districts rejected" {
    try std.testing.expectError(WorldError.NoGrid, loadWorldJson(std.testing.allocator,
        \\{"grid":[]}
    ));
    try std.testing.expectError(WorldError.UnevenGrid, loadWorldJson(std.testing.allocator,
        \\{"grid":["RR","R"]}
    ));
    try std.testing.expectError(WorldError.UnknownBlock, loadWorldJson(std.testing.allocator,
        \\{"grid":["X"]}
    ));
    try std.testing.expectError(WorldError.BadSectorSize, loadWorldJson(std.testing.allocator,
        \\{"sector_size":4,"grid":["R"]}
    ));
}
