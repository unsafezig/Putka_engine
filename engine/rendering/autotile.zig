//! Autotiling for roads + deterministic ground variation.
//! Pure functions of the tile grid: same input, same sprite choice.
//! The demo maps these to textures; tests pin the mapping.

const Tiles = @import("../world/tiles.zig").Tiles;

pub const RoadKind = enum { plain, straight_v, straight_h };

fn isRoad(tiles: Tiles, tx: i32, ty: i32) bool {
    const t = tiles.get(tx, ty) orelse return false;
    return t.type == .road or t.type == .bridge;
}

/// 4-neighbor road mask decides the road sprite.
pub fn roadKind(tiles: Tiles, tx: i32, ty: i32) RoadKind {
    const n = isRoad(tiles, tx, ty - 1);
    const e = isRoad(tiles, tx + 1, ty);
    const s = isRoad(tiles, tx, ty + 1);
    const w = isRoad(tiles, tx - 1, ty);
    if (n and s and !e and !w) return .straight_v;
    if (e and w and !n and !s) return .straight_h;
    return .plain; // crossings, ends, lone tiles: unmarked asphalt
}

/// Deterministic variant 0..count-1 for ground/sidewalk tiles.
pub fn variant(tx: i32, ty: i32, count: u32) u32 {
    std.debug.assert(count > 0);
    var h: u32 = @bitCast(@as(i32, @truncate(tx *% 374761393 +% ty *% 668265263)));
    h = (h ^ (h >> 13)) *% 1274126177;
    h ^= h >> 16;
    return h % count;
}

const std = @import("std");

test "road masks pick orientation" {
    var map = try @import("../world/map.zig").TileMap.init(std.testing.allocator, 8, 8);
    defer map.deinit();
    const tiles = Tiles{ .single = &map };
    // Vertical road column.
    map.set(3, 1, .{ .type = .road });
    map.set(3, 2, .{ .type = .road });
    map.set(3, 3, .{ .type = .road });
    try std.testing.expect(roadKind(tiles, 3, 2) == .straight_v);
    // Horizontal road row.
    map.set(1, 5, .{ .type = .road });
    map.set(2, 5, .{ .type = .road });
    map.set(3, 5, .{ .type = .road });
    try std.testing.expect(roadKind(tiles, 2, 5) == .straight_h);
    // Crossing and lone tile fall back to plain.
    try std.testing.expect(roadKind(tiles, 3, 5) == .plain);
    map.set(6, 6, .{ .type = .road });
    try std.testing.expect(roadKind(tiles, 6, 6) == .plain);
}

test "variants are deterministic and in range" {
    var seen = [_]bool{false} ** 3;
    var x: i32 = 0;
    while (x < 16) : (x += 1) {
        var y: i32 = 0;
        while (y < 16) : (y += 1) {
            const v = variant(x, y, 3);
            try std.testing.expect(v < 3);
            seen[v] = true;
            try std.testing.expectEqual(variant(x, y, 3), v);
        }
    }
    try std.testing.expect(seen[0] and seen[1] and seen[2]);
}
