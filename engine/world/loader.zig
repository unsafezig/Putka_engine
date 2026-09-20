//! Data-driven map loading: JSON text -> TileMap.
//! Format (`data/putka/maps/*.json`):
//! ```json
//! { "name": "mini_city", "width": 24, "height": 24,
//!   "tiles": ["....RR....", ...] }
//! ```
//! Legend: `.` grass, `R` road, `s` sidewalk, `~` water,
//!         `#` wall, `B` building, `=` bridge.
//! Unknown fields are ignored so the format can grow.

const Tile = @import("tile.zig").Tile;
const TileType = @import("tile.zig").TileType;
const TileMap = @import("map.zig").TileMap;

pub const LoadError = error{
    NoRows,
    UnevenRows,
    UnknownGlyph,
    SizeMismatch,
};

const MapJson = struct {
    name: []const u8 = "",
    width: u32 = 0,
    height: u32 = 0,
    tiles: []const []const u8 = &.{},
};

fn tileFromGlyph(g: u8) LoadError!Tile {
    return switch (g) {
        '.' => .{ .type = .grass },
        'R' => .{ .type = .road },
        's' => .{ .type = .sidewalk },
        '~' => .{ .type = .water, .solid = true },
        '#' => .{ .type = .wall, .solid = true },
        'B' => .{ .type = .building, .solid = true },
        '=' => .{ .type = .bridge },
        else => LoadError.UnknownGlyph,
    };
}

pub fn loadMapJson(allocator: std.mem.Allocator, text: []const u8) !TileMap {
    const parsed = try std.json.parseFromSlice(MapJson, allocator, text, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const rows = parsed.value.tiles;
    if (rows.len == 0) return LoadError.NoRows;
    const w: u32 = @intCast(rows[0].len);
    const h: u32 = @intCast(rows.len);
    if (w == 0) return LoadError.NoRows;
    if (parsed.value.width != 0 and parsed.value.width != w) return LoadError.SizeMismatch;
    if (parsed.value.height != 0 and parsed.value.height != h) return LoadError.SizeMismatch;

    var map = try TileMap.init(allocator, w, h);
    errdefer map.deinit();
    var y: i32 = 0;
    for (rows) |row| {
        if (row.len != w) {
            return LoadError.UnevenRows;
        }
        var x: i32 = 0;
        for (row) |g| {
            map.set(x, y, try tileFromGlyph(g));
            x += 1;
        }
        y += 1;
    }
    return map;
}

const std = @import("std");

test "load tiny map" {
    const text =
        \\{"name":"t","width":4,"height":3,"tiles":["....",".RR.",".BB."]}
    ;
    var map = try loadMapJson(std.testing.allocator, text);
    defer map.deinit();
    try std.testing.expectEqual(@as(u32, 4), map.width);
    try std.testing.expectEqual(@as(u32, 3), map.height);
    try std.testing.expect(map.get(1, 1).?.type == .road);
    try std.testing.expect(map.get(1, 2).?.solid);
    try std.testing.expect(!map.get(0, 0).?.solid);
}

test "load rejects bad input" {
    // Uneven rows.
    try std.testing.expectError(
        LoadError.UnevenRows,
        loadMapJson(std.testing.allocator,
            \\{"tiles":["....","..."]}
        ),
    );
    // Unknown glyph.
    try std.testing.expectError(
        LoadError.UnknownGlyph,
        loadMapJson(std.testing.allocator,
            \\{"tiles":["X"]}
        ),
    );
    // Declared size mismatch.
    try std.testing.expectError(
        LoadError.SizeMismatch,
        loadMapJson(std.testing.allocator,
            \\{"width":9,"tiles":[".."]}
        ),
    );
    // Empty.
    try std.testing.expectError(
        LoadError.NoRows,
        loadMapJson(std.testing.allocator,
            \\{"tiles":[]}
        ),
    );
}

test "legend covers all glyphs" {
    const text =
        \\{"tiles":[ "Rs~#B=." ]}
    ;
    var map = try loadMapJson(std.testing.allocator, text);
    defer map.deinit();
    try std.testing.expectEqual(@as(u32, 7), map.width);
    try std.testing.expect(map.get(0, 0).?.type == .road);
    try std.testing.expect(map.get(1, 0).?.type == .sidewalk);
    try std.testing.expect(map.get(2, 0).?.type == .water);
    try std.testing.expect(map.get(3, 0).?.type == .wall);
    try std.testing.expect(map.get(4, 0).?.type == .building);
    try std.testing.expect(map.get(5, 0).?.type == .bridge);
    try std.testing.expect(map.get(6, 0).?.type == .grass);
    try std.testing.expect(map.get(2, 0).?.solid);
    try std.testing.expect(!map.get(5, 0).?.solid);
}
