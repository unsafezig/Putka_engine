//! Axis-separated move-and-collide of an AABB against a solid tile grid.
//! No bouncing, no slopes: top-down GTA-style movement only.

const TileMap = @import("../world/map.zig").TileMap;
const Tiles = @import("../world/tiles.zig").Tiles;
const Aabb = @import("../math/aabb.zig").Aabb;
const Vec2 = @import("../math/vec2.zig").Vec2;

pub fn isBoxBlocked(tiles: Tiles, box: Aabb) bool {
    const min = Tiles.worldToTile(box.min);
    const max = Tiles.worldToTile(.{ .x = box.max.x - 0.01, .y = box.max.y - 0.01 });
    var ty = min.y;
    while (ty <= max.y) : (ty += 1) {
        var tx = min.x;
        while (tx <= max.x) : (tx += 1) {
            const t = tiles.get(tx, ty) orelse return true; // OOB counts as solid
            if (t.solid or !t.isWalkable()) {
                if (box.overlaps(TileMap.tileAabb(tx, ty))) return true;
            }
        }
    }
    return false;
}

/// Move `pos` (top-left of `size` box) by `delta`, sliding per axis.
/// Returns the actual movement applied.
pub fn moveBox(tiles: Tiles, pos: *Vec2, size: Vec2, delta: Vec2) Vec2 {
    var moved: Vec2 = .{};
    // X axis.
    {
        const probe = Aabb.fromPosSize(.{ .x = pos.x + delta.x, .y = pos.y }, size);
        if (!isBoxBlocked(tiles, probe)) {
            pos.x += delta.x;
            moved.x = delta.x;
        }
    }
    // Y axis.
    {
        const probe = Aabb.fromPosSize(.{ .x = pos.x, .y = pos.y + delta.y }, size);
        if (!isBoxBlocked(tiles, probe)) {
            pos.y += delta.y;
            moved.y = delta.y;
        }
    }
    return moved;
}

const std = @import("std");

test "open field moves freely, wall blocks" {
    var map = try TileMap.init(std.testing.allocator, 8, 8);
    defer map.deinit();
    const tiles = Tiles{ .single = &map };
    // All grass by default (walkable).
    var pos: Vec2 = .{ .x = 40, .y = 40 };
    const size: Vec2 = .{ .x = 16, .y = 16 };
    const moved = moveBox(tiles, &pos, size, .{ .x = 8, .y = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 8), moved.x, 1e-4);

    map.set(3, 1, .{ .type = .wall, .solid = true }); // world x 96..128
    pos = .{ .x = 70, .y = 40 };
    const blocked = moveBox(tiles, &pos, size, .{ .x = 40, .y = 0 });
    try std.testing.expect(blocked.x < 40);
    try std.testing.expect(pos.x + size.x <= 96.0 + 1e-3);
}

test "oob counts as solid" {
    var map = try TileMap.init(std.testing.allocator, 4, 4);
    defer map.deinit();
    const tiles = Tiles{ .single = &map };
    var pos: Vec2 = .{ .x = 0, .y = 0 };
    const moved = moveBox(tiles, &pos, .{ .x = 16, .y = 16 }, .{ .x = -50, .y = 0 });
    try std.testing.expectEqual(@as(f32, 0), moved.x);
}

test "world tiles collide across sector borders" {
    var w = try @import("../world/world.zig").loadWorldJson(std.testing.allocator,
        \\{"sector_size":8,"grid":["R"]}
    );
    defer w.deinit();
    const tiles = Tiles{ .world = &w };
    // Residential block at local (3,3) is solid through the union.
    const b = Aabb.fromPosSize(.{ .x = 3 * 32, .y = 3 * 32 }, .{ .x = 8, .y = 8 });
    try std.testing.expect(isBoxBlocked(tiles, b));
    const g = Aabb.fromPosSize(.{ .x = 0, .y = 7 * 32 }, .{ .x = 8, .y = 8 });
    try std.testing.expect(!isBoxBlocked(tiles, g));
}
