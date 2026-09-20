//! PUTKA art package: embedded PNG bytes.
//! Only game entry points (and their tests) import this; engine code
//! refers to sprites by logical id (see engine sprite catalog).

pub const road_plain_a = @embedFile("putka/tiles/road_plain_a.png");
pub const road_plain_b = @embedFile("putka/tiles/road_plain_b.png");
pub const road_plain_c = @embedFile("putka/tiles/road_plain_c.png");
pub const road_v = @embedFile("putka/tiles/road_v.png");
pub const road_h = @embedFile("putka/tiles/road_h.png");
pub const ground_a = @embedFile("putka/tiles/ground_a.png");
pub const ground_b = @embedFile("putka/tiles/ground_b.png");
pub const walk_a = @embedFile("putka/tiles/walk_a.png");
pub const walk_b = @embedFile("putka/tiles/walk_b.png");
pub const roof_a = @embedFile("putka/tiles/roof_a.png");
pub const roof_b = @embedFile("putka/tiles/roof_b.png");
pub const wall_south = @embedFile("putka/tiles/wall_south.png");
pub const wall_block = @embedFile("putka/tiles/wall_block.png");
pub const sedan = @embedFile("putka/vehicles/sedan.png");
pub const sedan_brake = @embedFile("putka/vehicles/sedan_brake.png");
pub const ped_civ = @embedFile("putka/peds/ped_civ.png");
pub const ped_gang = @embedFile("putka/peds/ped_gang.png");
pub const ped_cop = @embedFile("putka/peds/ped_cop.png");
pub const ped_player = @embedFile("putka/peds/ped_player.png");
pub const glow = @embedFile("putka/fx/glow.png");
pub const vignette = @embedFile("putka/fx/vignette.png");
