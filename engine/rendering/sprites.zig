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
    ped_civ,
    ped_gang,
    ped_cop,
    ped_player,
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

/// Pedestrian entries (`data/putka/sprites/peds.json`).
pub const PedsJson = struct {
    ped_civ: Entry = .{},
    ped_gang: Entry = .{},
    ped_cop: Entry = .{},
    ped_player: Entry = .{},

    pub fn get(self: PedsJson, id: SpriteId) Entry {
        return switch (id) {
            .ped_civ => self.ped_civ,
            .ped_gang => self.ped_gang,
            .ped_cop => self.ped_cop,
            .ped_player => self.ped_player,
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

pub fn loadPedsJson(alloc: std.mem.Allocator, text: []const u8) !PedsJson {
    const parsed = try std.json.parseFromSlice(PedsJson, alloc, text, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return parsed.value;
}

/// Every SpriteId must resolve to a file+source across the files.
pub fn resolve(tiles: TilesJson, vehicles: VehiclesJson, peds: PedsJson, id: SpriteId) Entry {
    const e = tiles.get(id);
    if (e.file.len > 0) return e;
    const v = vehicles.get(id);
    if (v.file.len > 0) return v;
    return peds.get(id);
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
    try std.testing.expectEqualStrings("s.png", resolve(t, v, .{}, .sedan).file);
    try std.testing.expectEqualStrings("a.png", resolve(t, v, .{}, .road_plain_a).file);
    const p = try loadPedsJson(std.testing.allocator,
        \\{"ped_civ":{"file":"c.png","source":"putka-original"}}
    );
    try std.testing.expectEqualStrings("c.png", resolve(t, v, p, .ped_civ).file);
    try std.testing.expectEqualStrings("", resolve(t, v, p, .ped_cop).file);
}
