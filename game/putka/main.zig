//! PUTKA engine demo: mini city + player + car + crime systems.
//! Simulation (engine/) is backend-independent; this file only maps
//! raylib input -> Intent and draws the world with shapes.

const std = @import("std");
const engine = @import("engine");
const putka_data = @import("putka_data");
const rl = @import("raylib");

const TILE_PX: i32 = 32;

fn tileColor(t: engine.TileType) rl.Color {
    return switch (t) {
        .road => rl.Color.dark_gray,
        .sidewalk => rl.Color.light_gray,
        .grass => rl.Color.green,
        .water => rl.Color.blue,
        .wall => rl.Color.gray,
        .building => rl.Color.brown,
        .bridge => rl.Color.gold,
    };
}

fn pollIntent() engine.Intent {
    const up = rl.isKeyDown(.up) or rl.isKeyDown(.w);
    const down = rl.isKeyDown(.down) or rl.isKeyDown(.s);
    const left = rl.isKeyDown(.left) or rl.isKeyDown(.a);
    const right = rl.isKeyDown(.right) or rl.isKeyDown(.d);
    var intent = engine.Intent.fromKeys(up, down, left, right);
    intent.sprint = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
    intent.action = rl.isKeyDown(.e);
    intent.fire = rl.isKeyDown(.space) or rl.isKeyDown(.j) or rl.isMouseButtonDown(.left);
    return intent;
}

pub fn main(init: std.process.Init) !void {
    var gpa_state = std.heap.DebugAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();
    const io = init.io;
    const cwd = std.Io.Dir.cwd();

    // Canonical map comes from data; procedural layout is the fallback
    // so the demo still runs if the JSON is broken.
    var map = engine.world.loader.loadMapJson(gpa, putka_data.mini_city_map) catch blk: {
        std.log.warn("mini_city.json failed to load, using procedural fallback", .{});
        var fallback = try engine.TileMap.init(gpa, 24, 24);
        fallback.buildMiniCity();
        break :blk fallback;
    };
    defer map.deinit();

    var player = engine.Player{ .pos = .{
        .x = 13 * engine.world.map.TILE_SIZE,
        .y = 11 * engine.world.map.TILE_SIZE,
    } };
    var sim = engine.FixedStep.init(1.0 / 60.0);

    const car_params = try engine.vehicles.vehicle.loadParamsJson(gpa, putka_data.car_params);
    var car = engine.Vehicle{ .pos = .{
        .x = 12 * engine.world.map.TILE_SIZE + engine.world.map.TILE_SIZE * 0.5,
        .y = 10 * engine.world.map.TILE_SIZE + engine.world.map.TILE_SIZE * 0.5,
    }, .heading = std.math.pi * 0.5 };
    var driving = false;
    var was_action = false;
    var ecam = engine.Camera2D{};
    var facing: engine.Vec2 = .{ .x = 1, .y = 0 };

    // Crime systems: data-driven pistol + crime heat table.
    const pistol_def = try engine.weapons.weapon.loadDefJson(gpa, putka_data.pistol_def);
    const crimes = try engine.wanted.loadCrimeTableJson(gpa, putka_data.crime_table);
    var gun = engine.weapons.weapon.Gun{ .def = pistol_def };
    var shots = engine.weapons.weapon.Shots.init(gpa);
    defer shots.deinit();
    var wanted = engine.wanted.Wanted{};
    // Who hates whom (drives NPC colors + later AI targeting).
    const relations = engine.factions.Matrix.initDefaults();

    // Pedestrians: 3 civilians + 1 gang member (color-coded by faction).
    var npcs = std.ArrayList(engine.Npc).empty;
    defer npcs.deinit(gpa);
    const spawns = [_]struct { x: f32, y: f32, f: engine.factions.Faction }{
        .{ .x = 10 * 32, .y = 10 * 32, .f = .civilians },
        .{ .x = 15 * 32, .y = 9 * 32, .f = .civilians },
        .{ .x = 9 * 32, .y = 15 * 32, .f = .civilians },
        .{ .x = 15 * 32, .y = 15 * 32, .f = .gang_a },
    };
    for (spawns) |sp| {
        try npcs.append(gpa, .{
            .pos = .{ .x = sp.x, .y = sp.y },
            .faction = sp.f,
            .timer = 0.5 + @as(f32, @floatFromInt(npcs.items.len)) * 0.3,
        });
    }
    var prng = std.Random.DefaultPrng.init(1234);
    var rng = prng.random();

    // Patrol officers on the main roads.
    var officers = std.ArrayList(engine.pursuit.Officer).empty;
    defer officers.deinit(gpa);
    const posts = [_]engine.Vec2{
        .{ .x = 12 * 32 + 7, .y = 6 * 32 + 7 },
        .{ .x = 13 * 32 + 7, .y = 18 * 32 + 7 },
    };
    for (posts) |post| {
        try officers.append(gpa, .{ .pos = post });
    }

    var busted_timer: f32 = 0;
    var banner: ?[]const u8 = null;
    var banner_timer: f32 = 0;
    var was_save = false;
    var was_load = false;

    const screen_w = 1280;
    const screen_h = 720;
    rl.initWindow(screen_w, screen_h, "PUTKA Engine - mini city demo");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        const frame_dt: f32 = @min(rl.getFrameTime(), 0.1);

        if (busted_timer > 0) {
            busted_timer -= frame_dt;
            if (busted_timer <= 0) {
                // Morning after: back on the street, record clean.
                player.pos = .{ .x = 13 * 32, .y = 11 * 32 };
                car.pos = .{
                    .x = 12 * 32 + 16,
                    .y = 10 * 32 + 16,
                };
                car.heading = std.math.pi * 0.5;
                car.speed = 0;
                car.driver = false;
                driving = false;
                ecam.mode = .player;
                wanted.heat = 0;
                shots.clearRetainingCapacity();
                npcs.clearRetainingCapacity();
                for (spawns) |sp| {
                    npcs.append(gpa, .{
                        .pos = .{ .x = sp.x, .y = sp.y },
                        .faction = sp.f,
                        .timer = 1,
                    }) catch {};
                }
                officers.clearRetainingCapacity();
                for (posts) |post| {
                    officers.append(gpa, .{ .pos = post }) catch {};
                }
            }
        } else {
            const steps = sim.push(frame_dt);
        var s: u32 = 0;
        while (s < steps) : (s += 1) {
            const intent = pollIntent();
            const action_pressed = intent.action and !was_action;
            was_action = intent.action;
            if (driving) {
                car.update(map, car_params, intent, sim.dt);
                // Keep the walker's body glued to the seat.
                player.pos = .{
                    .x = car.pos.x - engine.characters.player.PLAYER_SIZE.x * 0.5,
                    .y = car.pos.y - engine.characters.player.PLAYER_SIZE.y * 0.5,
                };
                if (action_pressed) {
                    driving = false;
                    car.driver = false;
                    car.speed = 0;
                    const out = engine.vehicles.vehicle.exitSpot(car);
                    player.pos = .{
                        .x = out.x - engine.characters.player.PLAYER_SIZE.x * 0.5,
                        .y = out.y - engine.characters.player.PLAYER_SIZE.y * 0.5,
                    };
                    ecam.mode = .player;
                }
            } else {
                player.update(map, intent, sim.dt);
                if (action_pressed and engine.vehicles.vehicle.canEnter(player.center(), car)) {
                    driving = true;
                    car.driver = true;
                    ecam.mode = .vehicle;
                }
            }
            if (intent.move.lengthSq() > 1e-6) facing = intent.move.normalized();

            // Shooting: muzzle ahead, facing on foot, hood direction in car.
            gun.update(sim.dt);
            const muzzle = if (driving)
                car.pos.add(car.forward().scale(30))
            else
                player.center().add(facing.scale(16));
            const aim = if (driving) car.forward() else facing;
            var threat: ?engine.characters.npc.Threat = null;
            if (intent.fire) {
                if (try gun.tryFire(&shots, muzzle, aim)) {
                    wanted.addHeat(crimes.gunshot);
                    threat = .{ .pos = muzzle, .kind = .gunshot };
                }
            }
            engine.weapons.weapon.updateShots(&shots, map, sim.dt);
            const sweep = engine.characters.npc.sweepShots(&shots, npcs.items);
            if (sweep.kills > 0) {
                wanted.addHeat(crimes.kill * @as(f32, @floatFromInt(sweep.kills)));
            }
            // Show last gunshot to witnesses even if this step's shot missed.
            var car_threat: ?engine.characters.npc.Threat = null;
            if (driving and @abs(car.speed) > 200) {
                car_threat = .{ .pos = car.pos, .kind = .car };
            }
            for (npcs.items) |*n| {
                if (n.dead) continue;
                n.update(map, &rng, sim.dt, threat orelse car_threat);
                if (driving and engine.characters.npc.checkRunOver(n, car.pos, car_params.width * 0.5, car.speed)) {
                    wanted.addHeat(crimes.runover);
                }
            }
            wanted.update(sim.dt, !intent.fire);

            // Patrol responds to the wanted level; sustained contact busts.
            const target = if (driving) car.pos else player.center();
            for (officers.items) |*o| {
                if (o.update(map, &rng, sim.dt, target, wanted.level())) {
                    busted_timer = 3.0;
                    wanted.heat = 0;
                }
            }
        }

        // Save/load are frame-rate actions, not simulation.
        const save_pressed = rl.isKeyDown(.f5) and !was_save;
        const load_pressed = rl.isKeyDown(.f9) and !was_load;
        was_save = rl.isKeyDown(.f5);
        was_load = rl.isKeyDown(.f9);
        if (save_pressed and busted_timer <= 0) {
            const snap = engine.save.Snapshot{
                .player_pos = player.pos,
                .car_pos = car.pos,
                .car_heading = car.heading,
                .car_speed = car.speed,
                .driving = driving,
                .wanted_heat = wanted.heat,
                .npcs = npcs.items,
                .officers = officers.items,
            };
            if (engine.save.saveToDir(cwd, io, engine.save.SAVE_NAME, snap, gpa)) {
                banner = "SAVED";
                banner_timer = 2;
            } else |_| {
                banner = "SAVE FAILED";
                banner_timer = 2;
            }
        }
        if (load_pressed and busted_timer <= 0) {
            if (engine.save.loadFromDir(cwd, io, engine.save.SAVE_NAME, gpa)) |loaded| {
                var parsed = loaded;
                defer parsed.deinit();
                const snap = parsed.value;
                player.pos = snap.player_pos;
                car.pos = snap.car_pos;
                car.heading = snap.car_heading;
                car.speed = snap.car_speed;
                driving = snap.driving;
                car.driver = snap.driving;
                ecam.mode = if (snap.driving) .vehicle else .player;
                wanted.heat = snap.wanted_heat;
                shots.clearRetainingCapacity();
                npcs.clearRetainingCapacity();
                npcs.appendSlice(gpa, snap.npcs) catch {};
                officers.clearRetainingCapacity();
                officers.appendSlice(gpa, snap.officers) catch {};
                banner = "LOADED";
                banner_timer = 2;
            } else |_| {
                banner = "LOAD FAILED";
                banner_timer = 2;
            }
        }
        if (banner_timer > 0) banner_timer -= frame_dt;
        }

        const focus = if (driving) car.pos else player.center();
        ecam.follow(focus);
        ecam.zoom = if (driving) 1.0 else 1.5;
        const cam = rl.Camera2D{
            .offset = .{ .x = screen_w / 2, .y = screen_h / 2 },
            .target = .{ .x = ecam.center.x, .y = ecam.center.y },
            .rotation = 0,
            .zoom = ecam.zoom,
        };

        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);
        cam.begin();
        // Tiles.
        var ty: i32 = 0;
        while (ty < map.height) : (ty += 1) {
            var tx: i32 = 0;
            while (tx < map.width) : (tx += 1) {
                const t = map.get(tx, ty) orelse continue;
                rl.drawRectangle(
                    tx * TILE_PX,
                    ty * TILE_PX,
                    TILE_PX,
                    TILE_PX,
                    tileColor(t.type),
                );
                // Grid line for readability.
                rl.drawRectangleLines(tx * TILE_PX, ty * TILE_PX, TILE_PX, TILE_PX, rl.Color{ .r = 0, .g = 0, .b = 0, .a = 40 });
            }
        }
        // Parked/driven car (rotated body + windshield hint).
        rl.drawRectanglePro(
            .{
                .x = car.pos.x - car_params.length * 0.5,
                .y = car.pos.y - car_params.width * 0.5,
                .width = car_params.length,
                .height = car_params.width,
            },
            .{ .x = car_params.length * 0.5, .y = car_params.width * 0.5 },
            car.heading * 180.0 / std.math.pi,
            rl.Color.sky_blue,
        );
        // Player (hidden while driving).
        if (!driving) {
            rl.drawRectangleRec(
                .{
                    .x = player.pos.x,
                    .y = player.pos.y,
                    .width = engine.characters.player.PLAYER_SIZE.x,
                    .height = engine.characters.player.PLAYER_SIZE.y,
                },
                rl.Color.red,
            );
        }
        // Pedestrians: green civilians, purple hostiles, yellow when panicking.
        for (npcs.items) |n| {
            if (n.dead) continue;
            const c = n.center();
            const col = if (n.state == .panic)
                rl.Color.yellow
            else if (relations.get(n.faction, .player) == .hostile)
                rl.Color.purple
            else
                rl.Color.lime;
            rl.drawCircle(
                @as(i32, @intFromFloat(c.x)),
                @as(i32, @intFromFloat(c.y)),
                engine.characters.npc.BODY_RADIUS,
                col,
            );
        }
        // Live bullets.
        for (shots.items.items) |shot| {
            rl.drawCircle(
                @as(i32, @intFromFloat(shot.pos.x)),
                @as(i32, @intFromFloat(shot.pos.y)),
                3,
                rl.Color.ray_white,
            );
        }
        // Officers: dark blue on patrol, flashing red/blue in pursuit.
        const siren = @mod(@as(i32, @intFromFloat(rl.getTime() * 4)), 2) == 0;
        for (officers.items) |o| {
            const c = o.center();
            const col = if (o.state == .chase)
                if (siren) rl.Color.red else rl.Color.blue
            else
                rl.Color.dark_blue;
            rl.drawCircle(
                @as(i32, @intFromFloat(c.x)),
                @as(i32, @intFromFloat(c.y)),
                engine.pursuit.OFFICER_SIZE.x * 0.5,
                col,
            );
        }
        rl.endMode2D();
        rl.drawText("WASD/arrows: move/drive  E: car  SPACE/J/click: fire  F5: save  F9: load", 10, 10, 20, rl.Color.ray_white);
        var hud_buf: [64]u8 = undefined;
        const alive: u32 = blk: {
            var n: u32 = 0;
            for (npcs.items) |npc| {
                if (!npc.dead) n += 1;
            }
            break :blk n;
        };
        if (std.fmt.bufPrintZ(&hud_buf, "WANTED {d}  peds {d}", .{ wanted.level(), alive })) |hud| {
            const col = if (wanted.level() == 0) rl.Color.ray_white else rl.Color.red;
            rl.drawText(hud, 10, 36, 20, col);
        } else |_| {}
        if (banner_timer > 0) {
            if (banner) |msg| {
                var msg_buf: [32]u8 = undefined;
                if (std.fmt.bufPrintZ(&msg_buf, "{s}", .{msg})) |m| {
                    rl.drawText(m, 10, 62, 20, rl.Color.gold);
                } else |_| {}
            }
        }
        if (busted_timer > 0) {
            rl.drawText("BUSTED", screen_w / 2 - 110, screen_h / 2 - 30, 60, rl.Color.red);
        }
        rl.drawFPS(screen_w - 100, 10);
        rl.endDrawing();
    }
}

test "demo wiring smoke test" {
    // Headless: Intent -> Player update path used by main().
    var map = try engine.TileMap.init(std.testing.allocator, 8, 8);
    defer map.deinit();
    var p = engine.Player{};
    p.update(map, engine.Intent.fromKeys(false, true, false, false), 1.0 / 60.0);
    try std.testing.expect(p.pos.y > 0);
}

test "mini_city.json loads with cross roads and solid buildings" {
    var map = try engine.world.loader.loadMapJson(std.testing.allocator, putka_data.mini_city_map);
    defer map.deinit();
    try std.testing.expectEqual(@as(u32, 24), map.width);
    try std.testing.expectEqual(@as(u32, 24), map.height);
    try std.testing.expect(map.get(12, 3).?.type == .road);
    try std.testing.expect(map.get(3, 12).?.type == .road);
    try std.testing.expect(map.get(2, 2).?.solid);
    try std.testing.expect(!map.get(0, 0).?.solid);
}
