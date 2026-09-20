//! Sector: one fixed-size tile block of the world grid.
//! Sectors own their tiles; `World` arranges sectors into a city.
//! Tile size constants live in `map.zig`; this file only adds the
//! sector coordinate layer.

const Tile = @import("tile.zig").Tile;
const map_mod = @import("map.zig");
const TileMap = map_mod.TileMap;
const TILE_SIZE = map_mod.TILE_SIZE;
const Vec2 = @import("../math/vec2.zig").Vec2;

pub const Sector = struct {
    sx: i32,
    sy: i32,
    map: TileMap,

    pub fn init(alloc: std.mem.Allocator, sx: i32, sy: i32, edge: u32) !Sector {
        return .{ .sx = sx, .sy = sy, .map = try TileMap.init(alloc, edge, edge) };
    }

    pub fn deinit(self: *Sector) void {
        self.map.deinit();
    }

    pub fn size(self: Sector) u32 {
        return self.map.width;
    }

    /// World-space origin (top-left) of this sector, in world units.
    pub fn origin(self: Sector) Vec2 {
        const s: f32 = @floatFromInt(self.size());
        return .{
            .x = @as(f32, @floatFromInt(self.sx)) * s * TILE_SIZE,
            .y = @as(f32, @floatFromInt(self.sy)) * s * TILE_SIZE,
        };
    }

    /// Which sector contains global tile (tx, ty) for a given sector size.
    pub fn containing(sector_size: u32, tx: i32, ty: i32) struct { sx: i32, sy: i32 } {
        const s: i32 = @intCast(sector_size);
        return .{ .sx = @divFloor(tx, s), .sy = @divFloor(ty, s) };
    }

    /// Local tile coords inside the sector (0..size).
    pub fn localTile(sector_size: u32, tx: i32, ty: i32) struct { x: i32, y: i32 } {
        const s: i32 = @intCast(sector_size);
        return .{ .x = tx - @divFloor(tx, s) * s, .y = ty - @divFloor(ty, s) * s };
    }
};

const std = @import("std");

test "containing + local tile incl. negatives" {
    const c = Sector.containing(16, 17, 5);
    try std.testing.expect(c.sx == 1 and c.sy == 0);
    const l = Sector.localTile(16, 17, 5);
    try std.testing.expect(l.x == 1 and l.y == 5);
    const cn = Sector.containing(16, -1, -17);
    try std.testing.expect(cn.sx == -1 and cn.sy == -2);
    const ln = Sector.localTile(16, -1, -17);
    try std.testing.expect(ln.x == 15 and ln.y == 15);
}

test "sector owns a tile grid" {
    var s = try Sector.init(std.testing.allocator, 2, 3, 16);
    defer s.deinit();
    try std.testing.expectEqual(@as(u32, 16), s.size());
    s.map.set(0, 0, .{ .type = .road });
    try std.testing.expect(s.map.get(0, 0).?.type == .road);
    const o = s.origin();
    try std.testing.expectApproxEqAbs(@as(f32, 2 * 16 * 32), o.x, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 3 * 16 * 32), o.y, 1e-3);
}
