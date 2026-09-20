//! Tile semantics: what a tile *means* for gameplay, not how it looks.

pub const TileType = enum(u8) {
    grass = 0,
    road = 1,
    sidewalk = 2,
    water = 3,
    wall = 4,
    building = 5,
    bridge = 6,
};

pub const Tile = struct {
    type: TileType = .grass,
    /// Gameplay collision. Rendering reads the same flag, owns nothing.
    solid: bool = false,
    /// Visual height in levels (0 = flat). Gameplay ignores it;
    /// districts/builders assign it, rendering turns it into roofs+walls.
    height: u8 = 0,

    pub fn isDriveable(t: Tile) bool {
        return t.type == .road or t.type == .bridge;
    }

    pub fn isWalkable(t: Tile) bool {
        return switch (t.type) {
            .water, .wall, .building => false,
            else => !t.solid,
        };
    }
};

const std = @import("std");

test "tile walk/drive semantics" {
    const road = Tile{ .type = .road };
    try std.testing.expect(road.isDriveable());
    try std.testing.expect(road.isWalkable());
    const wall = Tile{ .type = .wall, .solid = true };
    try std.testing.expect(!wall.isWalkable());
    const building = Tile{ .type = .building, .solid = true };
    try std.testing.expect(!building.isWalkable());
}
