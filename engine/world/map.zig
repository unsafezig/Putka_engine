//! TileMap: dense tile grid + procedural builders.
//! Serialization (JSON) comes later; layout stays stable so data files
//! written against this shape keep working.

const Tile = @import("tile.zig").Tile;
const TileType = @import("tile.zig").TileType;
const Aabb = @import("../math/aabb.zig").Aabb;
const Vec2 = @import("../math/vec2.zig").Vec2;

pub const TILE_SIZE: f32 = 32.0;

pub const TileMap = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    tiles: []Tile,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !TileMap {
        const tiles = try allocator.alloc(Tile, @as(usize, width) * height);
        for (tiles) |*t| t.* = .{};
        return .{ .allocator = allocator, .width = width, .height = height, .tiles = tiles };
    }

    pub fn deinit(self: *TileMap) void {
        self.allocator.free(self.tiles);
        self.* = undefined;
    }

    pub fn inBounds(self: TileMap, tx: i32, ty: i32) bool {
        return tx >= 0 and ty >= 0 and tx < self.width and ty < self.height;
    }

    pub fn get(self: TileMap, tx: i32, ty: i32) ?Tile {
        if (!self.inBounds(tx, ty)) return null;
        return self.tiles[@as(usize, @intCast(ty)) * self.width + @as(usize, @intCast(tx))];
    }

    pub fn set(self: *TileMap, tx: i32, ty: i32, tile: Tile) void {
        if (!self.inBounds(tx, ty)) return;
        self.tiles[@as(usize, @intCast(ty)) * self.width + @as(usize, @intCast(tx))] = tile;
    }

    pub fn worldToTile(_: TileMap, world: Vec2) struct { x: i32, y: i32 } {
        return .{
            .x = @as(i32, @intFromFloat(@floor(world.x / TILE_SIZE))),
            .y = @as(i32, @intFromFloat(@floor(world.y / TILE_SIZE))),
        };
    }

    pub fn tileAabb(tx: i32, ty: i32) Aabb {
        return Aabb.fromPosSize(
            .{ .x = @as(f32, @floatFromInt(tx)) * TILE_SIZE, .y = @as(f32, @floatFromInt(ty)) * TILE_SIZE },
            .{ .x = TILE_SIZE, .y = TILE_SIZE },
        );
    }

    /// Small demo block: roads cross in the middle, buildings in corners.
    /// Used by the first engine demo before the JSON loader lands.
    pub fn buildMiniCity(self: *TileMap) void {
        const mid_x: i32 = @divTrunc(@as(i32, @intCast(self.width)), 2);
        const mid_y: i32 = @divTrunc(@as(i32, @intCast(self.height)), 2);
        var y: i32 = 0;
        while (y < self.height) : (y += 1) {
            var x: i32 = 0;
            while (x < self.width) : (x += 1) {
                if (x == mid_x or x == mid_x + 1 or y == mid_y or y == mid_y + 1) {
                    self.set(x, y, .{ .type = .road });
                } else {
                    self.set(x, y, .{ .type = .grass });
                }
            }
        }
        // Buildings: solid 3x2 blocks in each quadrant corner.
        const blocks = [_]struct { x: i32, y: i32 }{
            .{ .x = 2, .y = 2 },
            .{ .x = @as(i32, @intCast(self.width)) - 5, .y = 2 },
            .{ .x = 2, .y = @as(i32, @intCast(self.height)) - 4 },
            .{ .x = @as(i32, @intCast(self.width)) - 5, .y = @as(i32, @intCast(self.height)) - 4 },
        };
        for (blocks) |b| {
            var dy: i32 = 0;
            while (dy < 2) : (dy += 1) {
                var dx: i32 = 0;
                while (dx < 3) : (dx += 1) {
                    self.set(b.x + dx, b.y + dy, .{ .type = .building, .solid = true });
                }
            }
        }
    }
};

const std = @import("std");

test "tilemap get/set + oob" {
    var map = try TileMap.init(std.testing.allocator, 8, 8);
    defer map.deinit();
    map.set(1, 1, .{ .type = .wall, .solid = true });
    try std.testing.expect(map.get(1, 1).?.solid);
    try std.testing.expect(map.get(100, 100) == null);
    // OOB set is a no-op, must not crash.
    map.set(100, 100, .{ .type = .road });
}

test "mini city has cross roads and solid buildings" {
    var map = try TileMap.init(std.testing.allocator, 16, 16);
    defer map.deinit();
    map.buildMiniCity();
    try std.testing.expect(map.get(8, 3).?.type == .road);
    try std.testing.expect(map.get(3, 8).?.type == .road);
    try std.testing.expect(map.get(2, 2).?.solid);
}
