//! Sprite catalog: logical ids (backend-independent) plus the JSON shape
//! mapping each id to its art file, draw scale and license source.
//! PNG bytes live in the `putka_assets` package; the game backend
//! (TextureManager) resolves ids to GPU textures.

pub const SpriteId = enum {
    road_plain_a,
    road_plain_b,
    road_plain_c,
    road_v,
    road_h,
    ground_a,
    ground_b,
    walk_a,
    walk_b,
    roof_a,
    roof_b,
    wall_south,
    wall_block,
    sedan,
    sedan_brake,
    glow,
    vignette,
};

pub const Entry = struct {
    file: []const u8 = "",
    scale: f32 = 2.0,
    source: []const u8 = "",
};

/// Tile entries (`data/putka/sprites/tiles.json`).
pub const TilesJson = struct {
    road_plain_a: Entry = .{},
    road_plain_b: Entry = .{},
    road_plain_c: Entry = .{},
    road_v: Entry = .{},
    road_h: Entry = .{},
    ground_a: Entry = .{},
    ground_b: Entry = .{},
    walk_a: Entry = .{},
    walk_b: Entry = .{},
    roof_a: Entry = .{},
    roof_b: Entry = .{},
    wall_south: Entry = .{},
    wall_block: Entry = .{},

    pub fn get(self: TilesJson, id: SpriteId) Entry {
        return switch (id) {
            .road_plain_a => self.road_plain_a,
            .road_plain_b => self.road_plain_b,
            .road_plain_c => self.road_plain_c,
            .road_v => self.road_v,
            .road_h => self.road_h,
            .ground_a => self.ground_a,
            .ground_b => self.ground_b,
            .walk_a => self.walk_a,
            .walk_b => self.walk_b,
            .roof_a => self.roof_a,
            .roof_b => self.roof_b,
            .wall_south => self.wall_south,
            .wall_block => self.wall_block,
            else => .{},
        };
    }
};

/// Vehicle + fx entries (`data/putka/sprites/vehicles.json`).
pub const VehiclesJson = struct {
    sedan: Entry = .{},
    sedan_brake: Entry = .{},
    glow: Entry = .{},
    vignette: Entry = .{},

    pub fn get(self: VehiclesJson, id: SpriteId) Entry {
        return switch (id) {
            .sedan => self.sedan,
            .sedan_brake => self.sedan_brake,
            .glow => self.glow,
            .vignette => self.vignette,
            else => .{},
        };
    }
};

/// Entries borrow `text` (no arrays involved); keep input alive.
pub fn loadTilesJson(alloc: std.mem.Allocator, text: []const u8) !TilesJson {
    const parsed = try std.json.parseFromSlice(TilesJson, alloc, text, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return parsed.value;
}

pub fn loadVehiclesJson(alloc: std.mem.Allocator, text: []const u8) !VehiclesJson {
    const parsed = try std.json.parseFromSlice(VehiclesJson, alloc, text, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return parsed.value;
}

/// Every SpriteId must resolve to a file+source across the two files.
pub fn resolve(tiles: TilesJson, vehicles: VehiclesJson, id: SpriteId) Entry {
    const e = tiles.get(id);
    if (e.file.len > 0) return e;
    return vehicles.get(id);
}

const std = @import("std");

test "entries parse with defaults" {
    const t = try loadTilesJson(std.testing.allocator,
        \\{"road_plain_a":{"file":"a.png","scale":2.0,"source":"kenney-cc0"}}
    );
    try std.testing.expectEqualStrings("a.png", t.road_plain_a.file);
    try std.testing.expectApproxEqAbs(@as(f32, 2), t.road_plain_a.scale, 1e-5);
    try std.testing.expectEqualStrings("", t.road_v.file); // default empty
    const v = try loadVehiclesJson(std.testing.allocator,
        \\{"sedan":{"file":"s.png","source":"putka-original"}}
    );
    try std.testing.expectEqualStrings("s.png", resolve(t, v, .sedan).file);
    try std.testing.expectEqualStrings("a.png", resolve(t, v, .road_plain_a).file);
}
