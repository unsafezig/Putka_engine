//! PUTKA Engine root module.
//! Headless simulation foundation. No windowing/rendering dependency here;
//! the raylib backend lives only in `game/putka/main.zig`.

pub const math = struct {
    pub const vec2 = @import("math/vec2.zig");
    pub const aabb = @import("math/aabb.zig");
};

pub const core = struct {
    pub const time = @import("core/time.zig");
};

pub const input = @import("input/input.zig");
pub const camera = @import("camera/camera.zig");
pub const world = struct {
    pub const tile = @import("world/tile.zig");
    pub const map = @import("world/map.zig");
};
pub const physics = struct {
    pub const collision = @import("physics/collision.zig");
};
pub const entities = struct {
    pub const id = @import("entities/id.zig");
    pub const registry = @import("entities/registry.zig");
};
pub const characters = struct {
    pub const player = @import("characters/player.zig");
};

// Re-export commonly used types at top level for convenience.
pub const Vec2 = math.vec2.Vec2;
pub const Aabb = math.aabb.Aabb;
pub const Circle = math.aabb.Circle;
pub const FixedStep = core.time.FixedStep;
pub const Intent = input.Intent;
pub const Camera2D = camera.Camera2D;
pub const Tile = world.tile.Tile;
pub const TileType = world.tile.TileType;
pub const TileMap = world.map.TileMap;
pub const EntityId = entities.id.EntityId;
pub const Registry = entities.registry.Registry;
pub const Player = characters.player.Player;

test {
    // Pull in all engine unit tests.
    _ = @import("math/vec2.zig");
    _ = @import("math/aabb.zig");
    _ = @import("core/time.zig");
    _ = @import("input/input.zig");
    _ = @import("camera/camera.zig");
    _ = @import("world/tile.zig");
    _ = @import("world/map.zig");
    _ = @import("physics/collision.zig");
    _ = @import("entities/id.zig");
    _ = @import("entities/registry.zig");
    _ = @import("characters/player.zig");
}
