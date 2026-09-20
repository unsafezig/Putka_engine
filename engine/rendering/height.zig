//! Building height visuals: which wall faces a tile exposes and how far
//! its roof lifts. Pure grid logic; the demo turns it into textures.
//! Convention: light from the north-west, so south + east faces show.

const Tiles = @import("../world/tiles.zig").Tiles;

pub const PX_PER_LEVEL: f32 = 14.0;

pub const Faces = struct { south: bool, east: bool };

fn isBuilding(tiles: Tiles, tx: i32, ty: i32) bool {
    const t = tiles.get(tx, ty) orelse return false;
    return t.type == .building;
}

/// A face draws only against a non-building neighbor (merged interiors).
pub fn faces(tiles: Tiles, tx: i32, ty: i32) Faces {
    if (!isBuilding(tiles, tx, ty)) return .{ .south = false, .east = false };
    return .{
        .south = !isBuilding(tiles, tx, ty + 1),
        .east = !isBuilding(tiles, tx + 1, ty),
    };
}

pub fn roofLift(height: u8) f32 {
    return @as(f32, @floatFromInt(height)) * PX_PER_LEVEL;
}

const std = @import("std");

test "faces merge interiors, expose edges" {
    var map = try @import("../world/map.zig").TileMap.init(std.testing.allocator, 8, 8);
    defer map.deinit();
    const tiles = Tiles{ .single = &map };
    const B = @import("../world/tile.zig").Tile{ .type = .building, .solid = true, .height = 1 };
    map.set(2, 2, B);
    map.set(3, 2, B);
    map.set(2, 3, B);
    map.set(3, 3, B);
    // (2,2): east + south neighbors are buildings -> no faces.
    const inner = faces(tiles, 2, 2);
    try std.testing.expect(!inner.south and !inner.east);
    // (3,2): south is a building -> east face only.
    const edge = faces(tiles, 3, 2);
    try std.testing.expect(!edge.south and edge.east);
    // (2,3): east is a building -> south face only.
    const bottom = faces(tiles, 2, 3);
    try std.testing.expect(bottom.south and !bottom.east);
    // (3,3): south-east corner, both faces open.
    const corner = faces(tiles, 3, 3);
    try std.testing.expect(corner.south and corner.east);
    // Non-building: never faces.
    try std.testing.expect(!faces(tiles, 0, 0).south);
}

test "roof lift scales with height" {
    try std.testing.expectApproxEqAbs(@as(f32, 0), roofLift(0), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 14), roofLift(1), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 28), roofLift(2), 1e-5);
}
