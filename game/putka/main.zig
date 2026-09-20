//! PUTKA engine demo: mini city + walking player + follow camera.
//! Simulation (engine/) is backend-independent; this file only maps
//! raylib input -> Intent and draws tiles/entities as rectangles.

const std = @import("std");
const engine = @import("engine");
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
    intent.action = rl.isKeyDown(.e) or rl.isKeyDown(.space);
    return intent;
}

pub fn main() !void {
    var gpa_state = std.heap.DebugAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var map = try engine.TileMap.init(gpa, 24, 24);
    defer map.deinit();
    map.buildMiniCity();

    var player = engine.Player{ .pos = .{
        .x = 12 * engine.world.map.TILE_SIZE,
        .y = 12 * engine.world.map.TILE_SIZE,
    } };
    var sim = engine.FixedStep.init(1.0 / 60.0);

    const screen_w = 1280;
    const screen_h = 720;
    rl.initWindow(screen_w, screen_h, "PUTKA Engine - mini city demo");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        const frame_dt: f32 = @min(rl.getFrameTime(), 0.1);
        const steps = sim.push(frame_dt);
        var s: u32 = 0;
        while (s < steps) : (s += 1) {
            const intent = pollIntent();
            player.update(map, intent, sim.dt);
        }

        const c = player.center();
        const cam = rl.Camera2D{
            .offset = .{ .x = screen_w / 2, .y = screen_h / 2 },
            .target = .{ .x = c.x, .y = c.y },
            .rotation = 0,
            .zoom = 1.5,
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
        // Player.
        rl.drawRectangleRec(
            .{
                .x = player.pos.x,
                .y = player.pos.y,
                .width = engine.characters.player.PLAYER_SIZE.x,
                .height = engine.characters.player.PLAYER_SIZE.y,
            },
            rl.Color.red,
        );
        rl.endMode2D();
        rl.drawText("WASD/arrows: move  SHIFT: sprint  ESC: quit", 10, 10, 20, rl.Color.ray_white);
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
