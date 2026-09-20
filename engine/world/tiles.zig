//! Tiles: the single query surface every simulation reads.
//! Either one `TileMap` (tests, small maps) or a streamed `World`
//! (districts). Gameplay code takes `Tiles` and never branches on it.

const Tile = @import("tile.zig").Tile;
const map_mod = @import("map.zig");
const TileMap = map_mod.TileMap;
const TILE_SIZE = map_mod.TILE_SIZE;
const World = @import("world.zig").World;
const Vec2 = @import("../math/vec2.zig").Vec2;

pub const Tiles = union(enum) {
    single: *const TileMap,
    world: *const World,

    pub fn get(self: Tiles, tx: i32, ty: i32) ?Tile {
        return switch (self) {
            .single => |m| m.get(tx, ty),
            .world => |w| w.get(tx, ty),
        };
    }

    pub fn worldToTile(world: Vec2) struct { x: i32, y: i32 } {
        return .{
            .x = @as(i32, @intFromFloat(@floor(world.x / TILE_SIZE))),
            .y = @as(i32, @intFromFloat(@floor(world.y / TILE_SIZE))),
        };
    }

    /// Simulation culling: single maps are always "active".
    pub fn activeAt(self: Tiles, world: Vec2) bool {
        return switch (self) {
            .single => true,
            .world => |w| w.sectorActiveAt(world),
        };
    }
};

const std = @import("std");

test "single and world answer the same way" {
    var map = try TileMap.init(std.testing.allocator, 4, 4);
    defer map.deinit();
    map.set(1, 1, .{ .type = .wall, .solid = true });
    const single = Tiles{ .single = &map };
    try std.testing.expect(single.get(1, 1).?.solid);
    try std.testing.expect(single.activeAt(.{ .x = 0, .y = 0 }));

    var w = try @import("world.zig").loadWorldJson(std.testing.allocator,
        \\{"sector_size":8,"grid":["R"]}
    );
    defer w.deinit();
    const wt = Tiles{ .world = &w };
    try std.testing.expect(wt.get(3, 3).?.solid); // residential block
    const t = Tiles.worldToTile(.{ .x = 40, .y = 70 });
    try std.testing.expect(t.x == 1 and t.y == 2);
}
