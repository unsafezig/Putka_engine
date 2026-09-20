//! PUTKA game data package.
//! Exposes data files as embedded bytes so the demo and tests load the
//! exact files shipped in `data/` regardless of working directory.
//! Engine code never imports this; only game entry points and their tests.

pub const mini_city_map = @embedFile("putka/maps/mini_city.json");
pub const districts_map = @embedFile("putka/maps/districts.json");
pub const car_params = @embedFile("putka/vehicles/car.json");
pub const pistol_def = @embedFile("putka/weapons/pistol.json");
pub const crime_table = @embedFile("putka/crimes.json");
pub const mission_m1 = @embedFile("putka/missions/m1.json");
pub const mission_m2a = @embedFile("putka/missions/m2a.json");
pub const mission_m2b = @embedFile("putka/missions/m2b.json");
pub const dlg_civilian = @embedFile("putka/dialogue/civilian.json");
pub const dlg_gang = @embedFile("putka/dialogue/gang.json");
pub const dlg_m1_choice = @embedFile("putka/dialogue/m1_choice.json");
pub const sprites_tiles = @embedFile("putka/sprites/tiles.json");
pub const sprites_vehicles = @embedFile("putka/sprites/vehicles.json");
pub const sprites_peds = @embedFile("putka/sprites/peds.json");
