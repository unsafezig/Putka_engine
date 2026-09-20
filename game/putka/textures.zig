//! TextureManager: PNG bytes (putka_assets) -> GPU textures, keyed by
//! engine SpriteId. Missing art fails loudly at load, never mid-frame.

const engine = @import("engine");
const putka_assets = @import("putka_assets");
const rl = @import("raylib");

const Sprites = engine.rendering.sprites;

fn bytesFor(id: Sprites.SpriteId) []const u8 {
    return switch (id) {
        .road_plain_a => putka_assets.road_plain_a,
        .road_plain_b => putka_assets.road_plain_b,
        .road_plain_c => putka_assets.road_plain_c,
        .road_v => putka_assets.road_v,
        .road_h => putka_assets.road_h,
        .ground_a => putka_assets.ground_a,
        .ground_b => putka_assets.ground_b,
        .walk_a => putka_assets.walk_a,
        .walk_b => putka_assets.walk_b,
        .roof_a => putka_assets.roof_a,
        .roof_b => putka_assets.roof_b,
        .wall_south => putka_assets.wall_south,
        .wall_block => putka_assets.wall_block,
        .sedan => putka_assets.sedan,
        .sedan_brake => putka_assets.sedan_brake,
        .ped_civ => putka_assets.ped_civ,
        .ped_gang => putka_assets.ped_gang,
        .ped_cop => putka_assets.ped_cop,
        .ped_player => putka_assets.ped_player,
        .glow => putka_assets.glow,
        .vignette => putka_assets.vignette,
    };
}

pub const TexManager = struct {
    alloc: std.mem.Allocator,
    map: std.AutoHashMap(Sprites.SpriteId, rl.Texture2D),

    pub fn load(alloc: std.mem.Allocator) !TexManager {
        var m = TexManager{ .alloc = alloc, .map = std.AutoHashMap(Sprites.SpriteId, rl.Texture2D).init(alloc) };
        errdefer m.unload();
        inline for (std.meta.fields(Sprites.SpriteId)) |f| {
            const id: Sprites.SpriteId = @enumFromInt(f.value);
            const img = try rl.loadImageFromMemory(".png", bytesFor(id));
            defer rl.unloadImage(img);
            const tex = try rl.loadTextureFromImage(img);
            rl.setTextureFilter(tex, .point);
            try m.map.put(id, tex);
        }
        return m;
    }

    pub fn unload(self: *TexManager) void {
        var it = self.map.valueIterator();
        while (it.next()) |tex| rl.unloadTexture(tex.*);
        self.map.deinit();
        self.* = undefined;
    }

    pub fn get(self: TexManager, id: Sprites.SpriteId) rl.Texture2D {
        return self.map.get(id) orelse unreachable; // load() fills all ids
    }
};

const std = @import("std");
