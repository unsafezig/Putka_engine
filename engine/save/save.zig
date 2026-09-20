//! Save system: whole demo state as one versioned JSON snapshot.
//! Pure encode/decode plus thin file helpers over the caller's `Io`.
//! Unknown fields are ignored on load; wrong versions are rejected.

const Npc = @import("../characters/npc.zig").Npc;
const Officer = @import("../police/pursuit.zig").Officer;
const Flag = @import("../story/story.zig").Flag;
const MissionSave = @import("../missions/mission.zig").MissionSave;
const Vec2 = @import("../math/vec2.zig").Vec2;

pub const CURRENT_VERSION: u32 = 1;
pub const SAVE_NAME: []const u8 = "putka_save.json";
pub const MAX_SAVE_BYTES: usize = 1 << 20;

pub const Snapshot = struct {
    version: u32 = CURRENT_VERSION,
    player_pos: Vec2 = .{},
    car_pos: Vec2 = .{},
    car_heading: f32 = 0,
    car_speed: f32 = 0,
    driving: bool = false,
    wanted_heat: f32 = 0,
    npcs: []const Npc = &.{},
    officers: []const Officer = &.{},
    story: []const Flag = &.{},
    missions: []const MissionSave = &.{},
};

pub const SaveError = error{VersionMismatch};

pub fn encode(alloc: std.mem.Allocator, snap: Snapshot) ![]u8 {
    return std.json.Stringify.valueAlloc(alloc, snap, .{});
}

pub fn decode(alloc: std.mem.Allocator, text: []const u8) !std.json.Parsed(Snapshot) {
    const parsed = try std.json.parseFromSlice(Snapshot, alloc, text, .{
        .ignore_unknown_fields = true,
    });
    if (parsed.value.version != CURRENT_VERSION) {
        parsed.deinit();
        return SaveError.VersionMismatch;
    }
    return parsed;
}

pub fn saveToDir(dir: std.Io.Dir, io: std.Io, sub_path: []const u8, snap: Snapshot, alloc: std.mem.Allocator) !void {
    const bytes = try encode(alloc, snap);
    defer alloc.free(bytes);
    try dir.writeFile(io, .{ .sub_path = sub_path, .data = bytes });
}

pub fn loadFromDir(dir: std.Io.Dir, io: std.Io, sub_path: []const u8, alloc: std.mem.Allocator) !std.json.Parsed(Snapshot) {
    const bytes = try dir.readFileAlloc(io, sub_path, alloc, .limited(MAX_SAVE_BYTES));
    defer alloc.free(bytes);
    return decode(alloc, bytes);
}

const std = @import("std");

test "snapshot roundtrips through json" {
    const alloc = std.testing.allocator;
    const npcs = [_]Npc{.{ .pos = .{ .x = 1, .y = 2 }, .hp = 66, .faction = .gang_a }};
    const officers = [_]Officer{.{ .pos = .{ .x = 3, .y = 4 }, .state = .chase }};
    const snap = Snapshot{
        .player_pos = .{ .x = 10, .y = 20 },
        .car_heading = 1.5,
        .driving = true,
        .wanted_heat = 42,
        .npcs = &npcs,
        .officers = &officers,
    };
    const bytes = try encode(alloc, snap);
    defer alloc.free(bytes);
    var parsed = try decode(alloc, bytes);
    defer parsed.deinit();
    const back = parsed.value;
    try std.testing.expect(back.player_pos.eql(snap.player_pos));
    try std.testing.expectApproxEqAbs(snap.car_heading, back.car_heading, 1e-4);
    try std.testing.expect(back.driving);
    try std.testing.expectApproxEqAbs(@as(f32, 42), back.wanted_heat, 1e-4);
    try std.testing.expectEqual(@as(usize, 1), back.npcs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 66), back.npcs[0].hp, 1e-4);
    try std.testing.expect(back.npcs[0].faction == .gang_a);
    try std.testing.expectEqual(@as(usize, 1), back.officers.len);
    try std.testing.expect(back.officers[0].state == .chase);
    try std.testing.expect(back.officers[0].pos.eql(snap.officers[0].pos));
}

test "wrong version rejected" {
    const alloc = std.testing.allocator;
    const bad = try std.json.Stringify.valueAlloc(alloc, Snapshot{ .version = 999 }, .{});
    defer alloc.free(bad);
    try std.testing.expectError(SaveError.VersionMismatch, decode(alloc, bad));
}

test "save and load file in tmp dir" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const snap = Snapshot{ .player_pos = .{ .x = 7, .y = 8 }, .wanted_heat = 30 };
    try saveToDir(tmp.dir, io, "s.json", snap, alloc);
    var parsed = try loadFromDir(tmp.dir, io, "s.json", alloc);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.player_pos.eql(snap.player_pos));
    try std.testing.expectError(error.FileNotFound, loadFromDir(tmp.dir, io, "missing.json", alloc));
}
