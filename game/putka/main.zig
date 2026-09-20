//! PUTKA engine demo: mini city + player + car + crime systems.
//! Simulation (engine/) is backend-independent; this file only maps
//! raylib input -> Intent and draws the world with shapes.

const std = @import("std");
const engine = @import("engine");
const putka_data = @import("putka_data");
const rl = @import("raylib");
const textures = @import("textures.zig");

const TILE_PX: i32 = 32;

const Sprites = engine.rendering.sprites;
const Autotile = engine.rendering.autotile;
const Tiles = engine.world.tiles.Tiles;

/// Textured sprite for a tile, or null for the flat fallback
/// (buildings/walls/water get real art in slice 2).
fn tileSpriteId(tiles: Tiles, tx: i32, ty: i32) ?Sprites.SpriteId {
    const t = tiles.get(tx, ty) orelse return null;
    return switch (t.type) {
        .road, .bridge => switch (Autotile.roadKind(tiles, tx, ty)) {
            .plain => switch (Autotile.variant(tx, ty, 3)) {
                0 => .road_plain_a,
                1 => .road_plain_b,
                else => .road_plain_c,
            },
            .straight_v => .road_v,
            .straight_h => .road_h,
        },
        .grass => if (Autotile.variant(tx, ty, 2) == 0) .ground_a else .ground_b,
        .sidewalk => if (Autotile.variant(tx, ty, 2) == 0) .walk_a else .walk_b,
        .wall => .wall_block,
        else => null, // buildings render as roofs+walls; water stays flat
    };
}

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

/// Greedy word wrap for the dialogue panel (ASCII demo text).
/// Returns lines drawn.
fn drawWrapped(text: []const u8, x: i32, y: i32, max_chars: usize, size: i32, color: rl.Color) i32 {
    var lines: i32 = 0;
    var start: usize = 0;
    while (start < text.len and lines < 6) {
        var end = @min(start + max_chars, text.len);
        if (end < text.len) {
            var cut = end;
            while (cut > start and text[cut] != ' ') : (cut -= 1) {}
            if (cut > start) end = cut;
        }
        // Trim leading space of continuation lines.
        while (start < end and text[start] == ' ') : (start += 1) {}
        if (start >= end) break;
        var line_buf: [96]u8 = undefined;
        const n = @min(end - start, line_buf.len);
        @memcpy(line_buf[0..n], text[start..][0..n]);
        line_buf[n] = 0;
        rl.drawText(line_buf[0..n :0], x, y + lines * (size + 6), size, color);
        start = end;
        lines += 1;
    }
    return lines;
}

pub fn main(init: std.process.Init) !void {
    var gpa_state = std.heap.DebugAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();
    const io = init.io;
    const cwd = std.Io.Dir.cwd();

    // Canonical city comes from data; a 1-sector fallback keeps the
    // demo running if the JSON is broken.
    var world = engine.world.districts.loadWorldJson(gpa, putka_data.districts_map) catch
        try engine.world.districts.loadWorldJson(gpa, "{\"sector_size\":16,\"grid\":[\"R\"]}");
    defer world.deinit();
    const tiles = engine.world.tiles.Tiles{ .world = &world };

    var player = engine.Player{ .pos = .{ .x = 560, .y = 688 } };
    var sim = engine.FixedStep.init(1.0 / 60.0);

    const car_params = try engine.vehicles.vehicle.loadParamsJson(gpa, putka_data.car_params);
    var car = engine.Vehicle{ .pos = .{ .x = 528, .y = 656 }, .heading = std.math.pi * 0.5 };
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
        .{ .x = 704, .y = 704, .f = .civilians },
        .{ .x = 832, .y = 704, .f = .civilians },
        .{ .x = 704, .y = 832, .f = .civilians },
        .{ .x = 832, .y = 832, .f = .gang_a },
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
        .{ .x = 528 - 9, .y = 272 - 9 },
        .{ .x = 1040 - 9, .y = 1296 - 9 },
    };
    for (posts) |post| {
        try officers.append(gpa, .{ .pos = post });
    }

    var busted_timer: f32 = 0;
    var banner: ?[]const u8 = null;
    var banner_timer: f32 = 0;
    var was_save = false;
    var was_load = false;
    var was_m = false;
    var was_one = false;
    var was_two = false;
    var was_three = false;
    var was_esc = false;

    // Missions: defs live in the arena, progress in the board + flags.
    var def_arena = std.heap.ArenaAllocator.init(gpa);
    defer def_arena.deinit();
    const dalloc = def_arena.allocator();
    const mission_defs = [_]engine.missions.MissionDef{
        try engine.missions.loadDefJson(dalloc, putka_data.mission_m1),
        try engine.missions.loadDefJson(dalloc, putka_data.mission_m2a),
        try engine.missions.loadDefJson(dalloc, putka_data.mission_m2b),
    };
    var story_flags = engine.story.Flags.init(gpa);
    defer story_flags.deinit();
    var flag_arena = std.heap.ArenaAllocator.init(gpa);
    defer flag_arena.deinit();
    var board = try engine.missions.Board.init(gpa, &mission_defs, &story_flags);
    defer board.deinit();

    // Dialogues share the def arena (process lifetime).
    const dlg_defs = [_]engine.dialogue.DialogueDef{
        try engine.dialogue.loadDefJson(dalloc, putka_data.dlg_civilian),
        try engine.dialogue.loadDefJson(dalloc, putka_data.dlg_gang),
        try engine.dialogue.loadDefJson(dalloc, putka_data.dlg_m1_choice),
    };
    for (&dlg_defs) |*dd| {
        engine.dialogue.validate(dd) catch |err| {
            std.log.warn("dialogue {s} invalid: {}", .{ dd.id, err });
        };
    }
    var convo: ?engine.dialogue.Conversation = null;
    var convo_mission: ?[]const u8 = null; // mission id answered by this dialogue
    var was_talk = false;

    var killed = std.ArrayList(engine.factions.Faction).empty;
    defer killed.deinit(gpa);

    const screen_w = 1280;
    const screen_h = 720;
    rl.initWindow(screen_w, screen_h, "PUTKA Engine - mini city demo");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // Headless screenshot mode for agents/CI: `--shot <frames>`.
    var shot_frames: ?u32 = null;
    {
        const args = try init.minimal.args.toSlice(gpa);
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--shot") and i + 1 < args.len) {
                shot_frames = std.fmt.parseInt(u32, args[i + 1], 10) catch null;
            }
        }
    }
    var shot_no: u32 = 0;

    // Sprite catalog (JSON) + GPU textures (needs a GL context).
    const tile_cat = try engine.rendering.sprites.loadTilesJson(gpa, putka_data.sprites_tiles);
    var texm = try textures.TexManager.load(gpa);
    defer texm.unload();
    var brake_light = false;

    while (!rl.windowShouldClose()) {
        const frame_dt: f32 = @min(rl.getFrameTime(), 0.1);

        if (busted_timer > 0) {
            busted_timer -= frame_dt;
            if (busted_timer <= 0) {
                // Morning after: back on the street, record clean.
                player.pos = .{ .x = 560, .y = 688 };
                car.pos = .{ .x = 528, .y = 656 };
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
        } else if (convo == null) {
            const steps = sim.push(frame_dt);
        var s: u32 = 0;
        while (s < steps) : (s += 1) {
            const intent = pollIntent();
            const action_pressed = intent.action and !was_action;
            was_action = intent.action;
            if (driving) {
                car.update(tiles, car_params, intent, sim.dt);
                brake_light = intent.move.y > 0.2 and car.speed > 60;
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
                player.update(tiles, intent, sim.dt);
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
            engine.weapons.weapon.updateShots(&shots, tiles, sim.dt);
            killed.clearRetainingCapacity();
            const sweep = engine.characters.npc.sweepShots(&shots, npcs.items);
            if (sweep.kills > 0) {
                wanted.addHeat(crimes.kill * @as(f32, @floatFromInt(sweep.kills)));
                killed.appendSlice(gpa, sweep.killed[0..sweep.killed_count]) catch {};
            }
            // Show last gunshot to witnesses even if this step's shot missed.
            var car_threat: ?engine.characters.npc.Threat = null;
            if (driving and @abs(car.speed) > 200) {
                car_threat = .{ .pos = car.pos, .kind = .car };
            }
            for (npcs.items) |*n| {
                if (n.dead) continue;
                // Streaming: frozen peds outside active sectors.
                if (!tiles.activeAt(n.center())) continue;
                n.update(tiles, &rng, sim.dt, threat orelse car_threat);
                if (driving and engine.characters.npc.checkRunOver(n, car.pos, car_params.width * 0.5, car.speed)) {
                    wanted.addHeat(crimes.runover);
                    killed.append(gpa, n.faction) catch {};
                }
            }
            wanted.update(sim.dt, !intent.fire);

            // Patrol responds to the wanted level; sustained contact busts.
            const target = if (driving) car.pos else player.center();
            for (officers.items) |*o| {
                if (!tiles.activeAt(o.center())) {
                    // Out of streaming range: the tail is lost.
                    if (o.state == .chase) {
                        o.state = .patrol;
                        o.arrest_progress = 0;
                    }
                    continue;
                }
                if (o.update(tiles, &rng, sim.dt, target, wanted.level())) {
                    busted_timer = 3.0;
                    wanted.heat = 0;
                    if (board.active() != null) {
                        board.failActive();
                        banner = "Tehtava epaonnistui";
                        banner_timer = 3;
                    }
                }
            }

            // Missions consume the step's kills and wanted level.
            const mev = board.update(sim.dt, target, wanted.level(), killed.items);
            if (mev.objectives_done > 0) {
                banner = "Tehtava etenee";
                banner_timer = 2;
            }
            if (mev.completed_id) |mid| {
                banner = "Tehtava valmis";
                banner_timer = 3;
                for (mission_defs) |md| {
                    if (std.mem.eql(u8, md.id, mid) and md.clear_wanted) wanted.heat = 0;
                }
            }
        }

        // Save/load are frame-rate actions, not simulation.
        const save_pressed = rl.isKeyDown(.f5) and !was_save;
        const load_pressed = rl.isKeyDown(.f9) and !was_load;
        was_save = rl.isKeyDown(.f5);
        was_load = rl.isKeyDown(.f9);
        if (save_pressed and busted_timer <= 0) {
            const story_list = story_flags.toList(gpa) catch &.{};
            defer gpa.free(story_list);
            const mission_saves = board.save(gpa) catch &.{};
            defer gpa.free(mission_saves);
            const snap = engine.save.Snapshot{
                .player_pos = player.pos,
                .car_pos = car.pos,
                .car_heading = car.heading,
                .car_speed = car.speed,
                .driving = driving,
                .wanted_heat = wanted.heat,
                .npcs = npcs.items,
                .officers = officers.items,
                .story = story_list,
                .missions = mission_saves,
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
                // Flag keys from the save borrow parsed JSON: copy them
                // into the long-lived arena before the parse is freed.
                flag_arena.deinit();
                flag_arena = std.heap.ArenaAllocator.init(gpa);
                story_flags.map.clearRetainingCapacity();
                for (snap.story) |f| {
                    const key = flag_arena.allocator().dupe(u8, f.key) catch continue;
                    story_flags.set(key, f.value) catch {};
                }
                board.load(snap.missions);
                banner = "LOADED";
                banner_timer = 2;
            } else |_| {
                banner = "LOAD FAILED";
                banner_timer = 2;
            }
        }
        if (banner_timer > 0) banner_timer -= frame_dt;

        // Mission accept (M) and branch choices (1/2) are frame-rate actions.
        // An open dialogue owns the number keys instead (see below).
        if (convo == null) {
            if (rl.isKeyDown(.m) and !was_m and busted_timer <= 0) {
                if (board.offered()) |offer| board.start(offer.def.id) catch {};
            }
            if (board.active()) |act| {
                if (act.state == .awaiting_choice and act.def.choice_dialogue.len == 0) {
                    if (rl.isKeyDown(.one) and !was_one) board.choose(act.def.id, 0) catch {};
                    if (rl.isKeyDown(.two) and !was_two and act.def.choices.len > 1) {
                        board.choose(act.def.id, 1) catch {};
                    }
                }
            }
        }
        was_m = rl.isKeyDown(.m);

        // Mission branch through dialogue: auto-open once, answer closes.
        if (convo == null and convo_mission == null) {
            if (board.active()) |act| {
                if (act.state == .awaiting_choice and act.def.choice_dialogue.len > 0) {
                    for (&dlg_defs) |*dd| {
                        if (std.mem.eql(u8, dd.id, act.def.choice_dialogue)) {
                            convo = engine.dialogue.Conversation.start(dd) catch null;
                            if (convo != null) convo_mission = act.def.id;
                            break;
                        }
                    }
                }
            }
        }

        // Talk (T) opens NPC chatter; number keys answer an open dialogue.
        if (convo == null and busted_timer <= 0 and !driving) {
            if (rl.isKeyDown(.t) and !was_talk) {
                var best: ?*engine.Npc = null;
                var best_d2: f32 = 64.0 * 64.0;
                for (npcs.items) |*n| {
                    if (n.dead) continue;
                    const d2 = n.center().sub(player.center()).lengthSq();
                    if (d2 < best_d2) {
                        best = n;
                        best_d2 = d2;
                    }
                }
                if (best) |n| {
                    const dlg_id: []const u8 = if (n.faction == .civilians) "civilian" else "gang";
                    for (&dlg_defs) |*dd| {
                        if (std.mem.eql(u8, dd.id, dlg_id)) {
                            convo = engine.dialogue.Conversation.start(dd) catch null;
                            break;
                        }
                    }
                }
            }
        }
        was_talk = rl.isKeyDown(.t);
        if (convo) |*c| {
            var pick: ?usize = null;
            if (rl.isKeyDown(.one) and !was_one) pick = 0;
            if (rl.isKeyDown(.two) and !was_two) pick = 1;
            if (rl.isKeyDown(.three) and !was_three) pick = 2;
            if (pick) |idx| {
                if (c.select(&story_flags, idx)) |r| {
                    if (r.mission_choice) |mc| {
                        if (convo_mission) |mid| board.choose(mid, mc) catch {};
                        convo = null;
                        convo_mission = null;
                    } else if (r.ended) {
                        convo = null;
                        convo_mission = null;
                    }
                } else |_| {}
            }
            // NPC talk can be walked away from; mission answers cannot.
            if (convo_mission == null and rl.isKeyDown(.escape) and !was_esc) {
                convo = null;
            }
        }
        was_esc = rl.isKeyDown(.escape);
        was_one = rl.isKeyDown(.one);
        was_two = rl.isKeyDown(.two);
        was_three = rl.isKeyDown(.three);
        }

        const focus = if (driving) car.pos else player.center();
        _ = world.activeAround(focus, 1);
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
        // Tiles, culled to the camera view; inactive sectors drawn dim.
        const view_size: engine.Vec2 = .{ .x = screen_w, .y = screen_h };
        const ctl = ecam.screenToWorld(view_size, .{});
        const cbr = ecam.screenToWorld(view_size, view_size);
        const tx0: i32 = @max(0, @as(i32, @intFromFloat(@floor(ctl.x / 32))) - 1);
        const ty0: i32 = @max(0, @as(i32, @intFromFloat(@floor(ctl.y / 32))) - 1);
        const tx1: i32 = @as(i32, @intFromFloat(@floor(cbr.x / 32))) + 1;
        const ty1: i32 = @as(i32, @intFromFloat(@floor(cbr.y / 32))) + 1;
        var ty: i32 = ty0;
        while (ty <= ty1) : (ty += 1) {
            var tx: i32 = tx0;
            while (tx <= tx1) : (tx += 1) {
                const center = engine.Vec2{
                    .x = @as(f32, @floatFromInt(tx)) * 32 + 16,
                    .y = @as(f32, @floatFromInt(ty)) * 32 + 16,
                };
                const dim = !world.sectorActiveAt(center);
                if (tileSpriteId(tiles, tx, ty)) |sid| {
                    const tex = texm.get(sid);
                    // Ground recedes (dark, quiet); roads stay bright.
                    const base: rl.Color = switch (sid) {
                        .ground_a, .ground_b => .{ .r = 150, .g = 150, .b = 168, .a = 255 },
                        else => .white,
                    };
                    const tint: rl.Color = if (dim) .{ .r = base.r / 2, .g = base.g / 2, .b = base.b / 2, .a = base.a } else base;
                    rl.drawTextureEx(
                        tex,
                        .{ .x = @as(f32, @floatFromInt(tx * TILE_PX)), .y = @as(f32, @floatFromInt(ty * TILE_PX)) },
                        0,
                        tile_cat.get(sid).scale,
                        tint,
                    );
                } else if (tiles.get(tx, ty)) |t| {
                    if (t.type == .building) continue; // roofs pass draws these
                    var col = tileColor(t.type);
                    if (dim) {
                        col = .{ .r = col.r / 2, .g = col.g / 2, .b = col.b / 2, .a = col.a };
                    }
                    rl.drawRectangle(tx * TILE_PX, ty * TILE_PX, TILE_PX, TILE_PX, col);
                }
            }
        }
        // Sector borders (streaming debug view).
        {
            const edge: i32 = @as(i32, @intCast(world.sector_size)) * TILE_PX;
            const wide: i32 = @as(i32, @intCast(world.wide));
            const high: i32 = @as(i32, @intCast(world.high));
            var sy: i32 = 0;
            while (sy < high) : (sy += 1) {
                var sx: i32 = 0;
                while (sx < wide) : (sx += 1) {
                    rl.drawRectangleLines(sx * edge, sy * edge, edge, edge, .{ .r = 200, .g = 180, .b = 80, .a = 90 });
                }
            }
        }
        // Building south walls (merged interiors expose no faces).
        {
            const wall_tex = texm.get(.wall_south);
            var wy: i32 = ty0;
            while (wy <= ty1) : (wy += 1) {
                var wx: i32 = tx0;
                while (wx <= tx1) : (wx += 1) {
                    const bt = tiles.get(wx, wy) orelse continue;
                    if (bt.type != .building or bt.height == 0) continue;
                    if (!engine.rendering.height.faces(tiles, wx, wy).south) continue;
                    const lift = engine.rendering.height.roofLift(bt.height);
                    rl.drawTexturePro(
                        wall_tex,
                        .{ .x = 0, .y = 0, .width = 16, .height = 16 },
                        .{
                            .x = @as(f32, @floatFromInt(wx * TILE_PX)),
                            .y = @as(f32, @floatFromInt((wy + 1) * TILE_PX)) - lift,
                            .width = TILE_PX,
                            .height = lift,
                        },
                        .{ .x = 0, .y = 0 },
                        0,
                        .white,
                    );
                }
            }
        }
        // Entities y-sorted by feet, each with a contact shadow.
        {
            const Ent = struct { y: f32, tag: u8, idx: u32 };
            var order: [40]Ent = undefined;
            var n_ent: usize = 0;
            order[n_ent] = .{ .y = car.pos.y, .tag = 0, .idx = 0 };
            n_ent += 1;
            if (!driving) {
                order[n_ent] = .{ .y = player.center().y, .tag = 1, .idx = 0 };
                n_ent += 1;
            }
            for (npcs.items, 0..) |*e_npc, i| {
                if (e_npc.dead) continue;
                if (n_ent < order.len) {
                    order[n_ent] = .{ .y = e_npc.center().y, .tag = 2, .idx = @intCast(i) };
                    n_ent += 1;
                }
            }
            for (officers.items, 0..) |*e_off, i| {
                if (n_ent < order.len) {
                    order[n_ent] = .{ .y = e_off.center().y, .tag = 3, .idx = @intCast(i) };
                    n_ent += 1;
                }
            }
            var ai: usize = 1;
            while (ai < n_ent) : (ai += 1) {
                const key = order[ai];
                var bi: usize = ai;
                while (bi > 0 and order[bi - 1].y > key.y) {
                    order[bi] = order[bi - 1];
                    bi -= 1;
                }
                order[bi] = key;
            }
            const shadow: rl.Color = .{ .r = 0, .g = 0, .b = 0, .a = 110 };
            const siren = @mod(@as(i32, @intFromFloat(rl.getTime() * 4)), 2) == 0;
            for (order[0..n_ent]) |e| {
                switch (e.tag) {
                    0 => {
                        rl.drawEllipse(
                            @as(i32, @intFromFloat(car.pos.x)),
                            @as(i32, @intFromFloat(car.pos.y + 10)),
                            20,
                            6,
                            shadow,
                        );
                        const tex = texm.get(if (brake_light) .sedan_brake else .sedan);
                        if (driving) {
                            const fwd = car.forward();
                            const side = engine.Vec2{ .x = -fwd.y, .y = fwd.x };
                            const glow = texm.get(.glow);
                            for ([2]f32{ -1, 1 }) |s| {
                                const hp = car.pos.add(fwd.scale(30)).add(side.scale(s * 9));
                                rl.drawTextureEx(glow, .{ .x = hp.x - 9, .y = hp.y - 9 }, 0, 1.5, .{ .r = 255, .g = 240, .b = 200, .a = 160 });
                            }
                        }
                        rl.drawTexturePro(
                            tex,
                            .{ .x = 0, .y = 0, .width = 22, .height = 11 },
                            .{ .x = car.pos.x - 22, .y = car.pos.y - 11, .width = 44, .height = 22 },
                            .{ .x = 22, .y = 11 },
                            car.heading * 180.0 / std.math.pi,
                            .white,
                        );
                    },
                    1 => {
                        const c = player.center();
                        rl.drawEllipse(@as(i32, @intFromFloat(c.x)), @as(i32, @intFromFloat(c.y + 9)), 9, 3.5, shadow);
                        rl.drawRectangleRec(
                            .{
                                .x = player.pos.x,
                                .y = player.pos.y,
                                .width = engine.characters.player.PLAYER_SIZE.x,
                                .height = engine.characters.player.PLAYER_SIZE.y,
                            },
                            rl.Color.red,
                        );
                    },
                    2 => {
                        const n = npcs.items[e.idx];
                        const c = n.center();
                        rl.drawEllipse(@as(i32, @intFromFloat(c.x)), @as(i32, @intFromFloat(c.y + 8)), 9, 3.5, shadow);
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
                    },
                    else => {
                        const o = officers.items[e.idx];
                        const c = o.center();
                        rl.drawEllipse(@as(i32, @intFromFloat(c.x)), @as(i32, @intFromFloat(c.y + 8)), 9, 3.5, shadow);
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
                    },
                }
            }
        }
        // Live bullets (over entities, under roofs).
        for (shots.items.items) |shot| {
            rl.drawCircle(
                @as(i32, @intFromFloat(shot.pos.x)),
                @as(i32, @intFromFloat(shot.pos.y)),
                3,
                rl.Color.ray_white,
            );
        }
        // Roofs last: they cap the walls and hide what stands behind.
        {
            var ry: i32 = ty0;
            while (ry <= ty1) : (ry += 1) {
                var rx: i32 = tx0;
                while (rx <= tx1) : (rx += 1) {
                    const bt = tiles.get(rx, ry) orelse continue;
                    if (bt.type != .building or bt.height == 0) continue;
                    const lift = engine.rendering.height.roofLift(bt.height);
                    const tex = texm.get(if (engine.rendering.autotile.variant(rx, ry, 2) == 0) .roof_a else .roof_b);
                    rl.drawTexturePro(
                        tex,
                        .{ .x = 0, .y = 0, .width = 16, .height = 16 },
                        .{
                            .x = @as(f32, @floatFromInt(rx * TILE_PX)),
                            .y = @as(f32, @floatFromInt(ry * TILE_PX)) - lift,
                            .width = TILE_PX,
                            .height = TILE_PX,
                        },
                        .{ .x = 0, .y = 0 },
                        0,
                        .white,
                    );
                }
            }
        }
        // Active go_to target marker.
        if (board.active()) |act| {
            if (act.state == .active and act.obj_idx < act.def.objectives.len) {
                const o = act.def.objectives[act.obj_idx];
                if (o.type == .go_to) {
                    const pulse: f32 = 7 + @as(f32, @floatCast(@sin(rl.getTime() * 5))) * 3;
                    rl.drawCircle(
                        @as(i32, @intFromFloat(o.x)),
                        @as(i32, @intFromFloat(o.y)),
                        pulse,
                        rl.Color.gold,
                    );
                }
            }
        }
        rl.endMode2D();
        // Night mood over the world (under the HUD): cold tint + vignette.
        rl.drawRectangle(0, 0, screen_w, screen_h, .{ .r = 8, .g = 10, .b = 28, .a = 70 });
        {
            const vig = texm.get(.vignette);
            rl.drawTexturePro(
                vig,
                .{ .x = 0, .y = 0, .width = 320, .height = 180 },
                .{ .x = 0, .y = 0, .width = @as(f32, @floatFromInt(screen_w)), .height = @as(f32, @floatFromInt(screen_h)) },
                .{ .x = 0, .y = 0 },
                0,
                .white,
            );
        }
        rl.drawText("WASD/arrows: move/drive  E: car  SPACE/J/click: fire  T: talk  M: mission  F5/F9: save/load", 10, 10, 20, rl.Color.ray_white);
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
        var sect_buf: [32]u8 = undefined;
        if (std.fmt.bufPrintZ(&sect_buf, "SECT {d}/{d}", .{ world.activeCount(), world.sectorCount() })) |line| {
            rl.drawText(line, 10, 62, 20, rl.Color.sky_blue);
        } else |_| {}
        // Mission tracker: offer, active objective, or branch choice.
        if (board.active()) |act| {
            var name_buf: [96]u8 = undefined;
            if (std.fmt.bufPrintZ(&name_buf, "{s}", .{act.def.name})) |name| {
                rl.drawText(name, 10, 88, 20, rl.Color.gold);
            } else |_| {}
            if (act.state == .awaiting_choice and convo == null) {
                rl.drawText("Valitse:", 10, 114, 20, rl.Color.ray_white);
                for (act.def.choices, 0..) |ch, i| {
                    var ch_buf: [96]u8 = undefined;
                    if (std.fmt.bufPrintZ(&ch_buf, "{d}: {s}", .{ i + 1, ch.text })) |line| {
                        rl.drawText(line, 10, 140 + @as(i32, @intCast(i)) * 26, 20, rl.Color.ray_white);
                    } else |_| {}
                }
            } else if (act.obj_idx < act.def.objectives.len) {
                const o = act.def.objectives[act.obj_idx];
                var obj_buf: [128]u8 = undefined;
                const line = switch (o.type) {
                    .kill => std.fmt.bufPrintZ(&obj_buf, "{s} {d}/{d}", .{ o.desc, @min(act.count, o.count), o.count }),
                    .survive => std.fmt.bufPrintZ(&obj_buf, "{s} {d}s", .{ o.desc, @as(u32, @intFromFloat(@max(0, act.timer))) }),
                    else => std.fmt.bufPrintZ(&obj_buf, "{s}", .{o.desc}),
                };
                if (line) |l| {
                    rl.drawText(l, 10, 114, 20, rl.Color.ray_white);
                } else |_| {}
            }
        } else if (board.offered()) |offer| {
            var off_buf: [128]u8 = undefined;
            if (std.fmt.bufPrintZ(&off_buf, "M: {s} - {s}", .{ offer.def.name, offer.def.briefing })) |line| {
                rl.drawText(line, 10, 88, 20, rl.Color.lime);
            } else |_| {}
        }
        if (banner_timer > 0) {
            if (banner) |msg| {
                var msg_buf: [32]u8 = undefined;
                if (std.fmt.bufPrintZ(&msg_buf, "{s}", .{msg})) |m| {
                    rl.drawText(m, 10, 166, 20, rl.Color.gold);
                } else |_| {}
            }
        }
        if (busted_timer > 0) {
            rl.drawText("BUSTED", screen_w / 2 - 110, screen_h / 2 - 30, 60, rl.Color.red);
        }
        // Dialogue panel (screen space, above everything else).
        if (convo) |c| {
            const px: i32 = 40;
            const pw: i32 = screen_w - 80;
            const ph: i32 = 230;
            const py: i32 = screen_h - ph - 20;
            rl.drawRectangle(px, py, pw, ph, .{ .r = 10, .g = 10, .b = 14, .a = 230 });
            rl.drawRectangleLines(px, py, pw, ph, rl.Color.gold);
            var spk_buf: [64]u8 = undefined;
            if (std.fmt.bufPrintZ(&spk_buf, "{s}", .{c.node.speaker})) |spk| {
                rl.drawText(spk, px + 16, py + 10, 20, rl.Color.gold);
            } else |_| {}
            const drawn = drawWrapped(c.node.text, px + 16, py + 40, 72, 20, rl.Color.ray_white);
            var vmap: [8]u8 = undefined;
            const n = c.visible(&story_flags, &vmap);
            var i: usize = 0;
            while (i < n and i < 3) : (i += 1) {
                const o = &c.node.options[vmap[i]];
                var ob: [112]u8 = undefined;
                if (std.fmt.bufPrintZ(&ob, "{d}: {s}", .{ i + 1, o.text })) |line| {
                    rl.drawText(line, px + 16, py + 44 + drawn * 26 + @as(i32, @intCast(i)) * 26, 20, rl.Color.sky_blue);
                } else |_| {}
            }
        }
        rl.drawFPS(screen_w - 100, screen_h - 30);
        rl.endDrawing();

        if (shot_frames) |n| {
            shot_no += 1;
            if (shot_no >= n) {
                rl.takeScreenshot("shot.png");
                break;
            }
        }
    }
}

test "demo wiring smoke test" {
    // Headless: Intent -> Player update path used by main().
    var map = try engine.TileMap.init(std.testing.allocator, 8, 8);
    defer map.deinit();
    var p = engine.Player{};
    p.update(.{ .single = &map }, engine.Intent.fromKeys(false, true, false, false), 1.0 / 60.0);
    try std.testing.expect(p.pos.y > 0);
}

test "mini_city.json loads with cross roads and solid buildings" {    var map = try engine.world.loader.loadMapJson(std.testing.allocator, putka_data.mini_city_map);
    defer map.deinit();
    try std.testing.expectEqual(@as(u32, 24), map.width);
    try std.testing.expectEqual(@as(u32, 24), map.height);
    try std.testing.expect(map.get(12, 3).?.type == .road);
    try std.testing.expect(map.get(3, 12).?.type == .road);
    try std.testing.expect(map.get(2, 2).?.solid);
    try std.testing.expect(!map.get(0, 0).?.solid);
}

test "districts.json loads a connected 3x3 city" {
    var world = try engine.world.districts.loadWorldJson(std.testing.allocator, putka_data.districts_map);
    defer world.deinit();
    try std.testing.expectEqual(@as(usize, 9), world.sectorCount());
    const tiles = engine.world.tiles.Tiles{ .world = &world };
    // Border roads connect across the seam between sectors.
    try std.testing.expect(tiles.get(16, 5).?.type == .road);
    try std.testing.expect(tiles.get(5, 16).?.type == .road);
    // Demo spawn tiles are walkable road.
    try std.testing.expect(tiles.get(16, 20).?.type == .road);
    try std.testing.expect(!tiles.get(16, 20).?.solid);
    // Streaming starts fully active, narrows to the focus sector.
    try std.testing.expectEqual(@as(usize, 9), world.activeAround(.{ .x = 784, .y = 784 }, 1));
    try std.testing.expectEqual(@as(usize, 1), world.activeAround(.{ .x = 100, .y = 100 }, 0));
}

test "every sprite id resolves to licensed art" {
    const tiles = try engine.rendering.sprites.loadTilesJson(std.testing.allocator, putka_data.sprites_tiles);
    const vehicles = try engine.rendering.sprites.loadVehiclesJson(std.testing.allocator, putka_data.sprites_vehicles);
    inline for (std.meta.fields(engine.rendering.sprites.SpriteId)) |f| {
        const id: engine.rendering.sprites.SpriteId = @enumFromInt(f.value);
        const e = engine.rendering.sprites.resolve(tiles, vehicles, id);
        try std.testing.expect(e.file.len > 0);
        try std.testing.expect(e.source.len > 0);
        try std.testing.expect(e.scale > 0);
    }
}

test "demo missions load, gate and branch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const da = arena.allocator();
    const defs = [_]engine.missions.MissionDef{
        try engine.missions.loadDefJson(da, putka_data.mission_m1),
        try engine.missions.loadDefJson(da, putka_data.mission_m2a),
        try engine.missions.loadDefJson(da, putka_data.mission_m2b),
    };
    var flags = engine.story.Flags.init(std.testing.allocator);
    defer flags.deinit();
    var board = try engine.missions.Board.init(std.testing.allocator, &defs, &flags);
    defer board.deinit();

    // Only m1 offered at first; its first go_to point works.
    try std.testing.expectEqualStrings("m1", board.offered().?.def.id);
    try board.start("m1");
    const ev = board.update(0.016, .{ .x = 528, .y = 208 }, 0, &.{});
    try std.testing.expectEqual(@as(u32, 1), ev.objectives_done);
    // Branch: choice 2 opens m2b, not m2a.
    _ = board.update(0.016, .{ .x = 1040, .y = 1296 }, 0, &.{});
    try board.choose("m1", 1);
    try std.testing.expect(flags.get("returned_cash"));
    try std.testing.expect(!flags.get("kept_cash"));
    try std.testing.expectEqualStrings("m2b", board.offered().?.def.id);
}

test "demo dialogues load, validate and answer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const da = arena.allocator();
    const defs = [_]engine.dialogue.DialogueDef{
        try engine.dialogue.loadDefJson(da, putka_data.dlg_civilian),
        try engine.dialogue.loadDefJson(da, putka_data.dlg_gang),
        try engine.dialogue.loadDefJson(da, putka_data.dlg_m1_choice),
    };
    for (&defs) |*dd| try engine.dialogue.validate(dd);
    var flags = engine.story.Flags.init(std.testing.allocator);
    defer flags.deinit();
    // m1 branch through dialogue option 1.
    var c = try engine.dialogue.Conversation.start(&defs[2]);
    const r = try c.select(&flags, 0);
    try std.testing.expect(r.ended);
    try std.testing.expectEqual(@as(?u32, 0), r.mission_choice);
    // Civilian hides the gated option until m1_done.
    var t = try engine.dialogue.Conversation.start(&defs[0]);
    var vmap: [8]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 2), t.visible(&flags, &vmap));
    try flags.set("m1_done", true);
    try std.testing.expectEqual(@as(usize, 3), t.visible(&flags, &vmap));
}
