//! Mission system: data-driven defs (JSON), explicit runtime states,
//! branching via story flags. Objective types v1:
//! `go_to`, `kill`, `survive`, `escape`.
//!
//! The board never touches the world directly: the game feeds it
//! `player_pos`, `wanted_level` and the step's kills, and reads events.

const Faction = @import("../factions/factions.zig").Faction;
const Flags = @import("../story/story.zig").Flags;
const Vec2 = @import("../math/vec2.zig").Vec2;

pub const ObjectiveType = enum { go_to, kill, survive, escape };

pub const ObjectiveDef = struct {
    type: ObjectiveType,
    desc: []const u8 = "",
    x: f32 = 0,
    y: f32 = 0,
    radius: f32 = 60,
    faction: Faction = .gang_a,
    count: u32 = 1,
    duration: f32 = 10,
};

pub const ChoiceDef = struct {
    text: []const u8 = "",
    set: []const []const u8 = &.{},
};

pub const MissionDef = struct {
    id: []const u8 = "",
    name: []const u8 = "",
    briefing: []const u8 = "",
    required: []const []const u8 = &.{},
    objectives: []const ObjectiveDef = &.{},
    choices: []const ChoiceDef = &.{},
    /// Optional dialogue def id rendered for the end choice.
    /// When empty, the game falls back to its own choice UI.
    choice_dialogue: []const u8 = "",
    set_on_complete: []const []const u8 = &.{},
    clear_wanted: bool = false,
};

/// Load a def; all memory (strings, arrays) is owned by `arena`.
/// Keep the arena alive as long as the def (and its board) is used.
pub fn loadDefJson(arena: std.mem.Allocator, text: []const u8) !MissionDef {
    return std.json.parseFromSliceLeaky(MissionDef, arena, text, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}

pub const State = enum { available, active, awaiting_choice, complete, failed };

pub const MissionSave = struct {
    id: []const u8 = "",
    state: State = .available,
    obj_idx: u32 = 0,
    count: u32 = 0,
    timer: f32 = 0,
};

pub const Runtime = struct {
    def: *const MissionDef,
    state: State = .available,
    obj_idx: u32 = 0,
    count: u32 = 0,
    timer: f32 = 0,
    had_wanted: bool = false,

    fn enterObjective(self: *Runtime) void {
        self.count = 0;
        self.had_wanted = false;
        const o = self.def.objectives[self.obj_idx];
        self.timer = o.duration;
    }
};

pub const Events = struct {
    objectives_done: u32 = 0,
    completed_id: ?[]const u8 = null,
};

pub const Board = struct {
    alloc: std.mem.Allocator,
    defs: []const MissionDef,
    runs: std.ArrayList(Runtime),
    flags: *Flags,

    pub const Error = error{ UnknownId, Busy, BadChoice, NoChoice };

    pub fn init(alloc: std.mem.Allocator, defs: []const MissionDef, flags: *Flags) !Board {
        var runs: std.ArrayList(Runtime) = .empty;
        for (defs) |*d| try runs.append(alloc, .{ .def = d });
        return .{ .alloc = alloc, .defs = defs, .runs = runs, .flags = flags };
    }

    pub fn deinit(self: *Board) void {
        self.runs.deinit(self.alloc);
        self.* = undefined;
    }

    fn find(self: *Board, id: []const u8) ?*Runtime {
        for (self.runs.items) |*r| {
            if (std.mem.eql(u8, r.def.id, id)) return r;
        }
        return null;
    }

    pub fn isAvailable(self: *Board, r: *const Runtime) bool {
        if (r.state != .available and r.state != .failed) return false;
        return self.flags.satisfies(r.def.required);
    }

    /// First mission the player can take, if any.
    pub fn offered(self: *Board) ?*Runtime {
        for (self.runs.items) |*r| {
            if (self.isAvailable(r)) return r;
        }
        return null;
    }

    pub fn active(self: *Board) ?*Runtime {
        for (self.runs.items) |*r| {
            if (r.state == .active or r.state == .awaiting_choice) return r;
        }
        return null;
    }

    pub fn start(self: *Board, id: []const u8) Error!void {
        if (self.active() != null) return Error.Busy;
        const r = self.find(id) orelse return Error.UnknownId;
        if (!self.isAvailable(r)) return Error.UnknownId;
        r.state = .active;
        r.obj_idx = 0;
        r.enterObjective();
    }

    pub fn failActive(self: *Board) void {
        if (self.active()) |r| {
            if (r.state == .active) r.state = .failed;
        }
    }

    pub fn choose(self: *Board, id: []const u8, idx: usize) Error!void {
        const r = self.find(id) orelse return Error.UnknownId;
        if (r.state != .awaiting_choice) return Error.NoChoice;
        if (idx >= r.def.choices.len) return Error.BadChoice;
        for (r.def.choices[idx].set) |f| self.flags.set(f, true) catch return Error.BadChoice;
        self.finish(r);
    }

    fn finish(self: *Board, r: *Runtime) void {
        for (r.def.set_on_complete) |f| self.flags.set(f, true) catch {};
        r.state = .complete;
    }

    fn advance(self: *Board, r: *Runtime, ev: *Events) void {
        r.obj_idx += 1;
        ev.objectives_done += 1;
        if (r.obj_idx >= r.def.objectives.len) {
            if (r.def.choices.len == 0) {
                self.finish(r);
                ev.completed_id = r.def.id;
            } else {
                r.state = .awaiting_choice;
            }
        } else {
            r.enterObjective();
        }
    }

    pub fn update(
        self: *Board,
        dt: f32,
        player_pos: Vec2,
        wanted_level: u8,
        killed: []const Faction,
    ) Events {
        var ev = Events{};
        const r = self.active() orelse return ev;
        if (r.state != .active) return ev;
        const o = r.def.objectives[r.obj_idx];
        switch (o.type) {
            .go_to => {
                const d = player_pos.sub(.{ .x = o.x, .y = o.y }).length();
                if (d <= o.radius) self.advance(r, &ev);
            },
            .kill => {
                for (killed) |f| {
                    if (f == o.faction) r.count += 1;
                }
                if (r.count >= o.count) self.advance(r, &ev);
            },
            .survive => {
                r.timer -= dt;
                if (r.timer <= 0) self.advance(r, &ev);
            },
            .escape => {
                if (wanted_level > 0) r.had_wanted = true;
                if (r.had_wanted and wanted_level == 0) self.advance(r, &ev);
            },
        }
        if (r.state == .complete) ev.completed_id = r.def.id;
        return ev;
    }

    pub fn save(self: *Board, alloc: std.mem.Allocator) ![]MissionSave {
        var out = try alloc.alloc(MissionSave, self.runs.items.len);
        for (self.runs.items, 0..) |*r, i| {
            out[i] = .{
                .id = r.def.id,
                .state = r.state,
                .obj_idx = r.obj_idx,
                .count = r.count,
                .timer = r.timer,
            };
        }
        return out;
    }

    pub fn load(self: *Board, saves: []const MissionSave) void {
        for (saves) |s| {
            if (self.find(s.id)) |r| {
                r.state = s.state;
                r.obj_idx = @min(s.obj_idx, @as(u32, @intCast(r.def.objectives.len)));
                r.count = s.count;
                r.timer = s.timer;
            }
        }
    }
};

const std = @import("std");

const DEF_JSON =
    \\{"id":"m1","name":"Viesti","required":[],"objectives":[
    \\{"type":"go_to","desc":"Mene sillalle","x":100.0,"y":200.0,"radius":60.0},
    \\{"type":"kill","desc":"Hoida gangsteri","faction":"gang_a","count":2},
    \\{"type":"survive","desc":"Selvia","duration":5.0},
    \\{"type":"escape","desc":"Karista poliisit"}],
    \\"choices":[{"text":"Pida rahat","set":["kept_cash"]}],
    \\"set_on_complete":["m1_done"]}
;

test "def json parses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const d = try loadDefJson(arena.allocator(), DEF_JSON);
    try std.testing.expectEqualStrings("m1", d.id);
    try std.testing.expectEqual(@as(usize, 4), d.objectives.len);
    try std.testing.expect(d.objectives[1].type == .kill);
    try std.testing.expect(d.objectives[1].faction == .gang_a);
    try std.testing.expectEqual(@as(usize, 1), d.choices.len);
}

test "go_to -> kill -> survive -> escape -> choice -> complete" {
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const d = try loadDefJson(arena.allocator(), DEF_JSON);
    const defs = [_]MissionDef{d};
    var b = try Board.init(std.testing.allocator, &defs, &flags);
    defer b.deinit();

    try std.testing.expect(b.offered() != null);
    try b.start("m1");
    // go_to: far away does nothing, on the spot advances.
    var ev = b.update(0.016, .{ .x = 0, .y = 0 }, 0, &.{});
    try std.testing.expect(ev.objectives_done == 0);
    ev = b.update(0.016, .{ .x = 100, .y = 200 }, 0, &.{});
    try std.testing.expect(ev.objectives_done == 1);
    // kill 2 gang_a (a civilian doesn't count).
    ev = b.update(0.016, .{ .x = 0, .y = 0 }, 0, &.{Faction.civilians});
    try std.testing.expect(ev.objectives_done == 0);
    ev = b.update(0.016, .{ .x = 0, .y = 0 }, 0, &.{ Faction.gang_a, Faction.gang_a });
    try std.testing.expect(ev.objectives_done == 1);
    // survive 5s.
    ev = b.update(5.0, .{ .x = 0, .y = 0 }, 0, &.{});
    try std.testing.expect(ev.objectives_done == 1);
    // escape: needs heat first.
    ev = b.update(0.016, .{ .x = 0, .y = 0 }, 0, &.{});
    try std.testing.expect(ev.objectives_done == 0);
    ev = b.update(0.016, .{ .x = 0, .y = 0 }, 2, &.{});
    try std.testing.expect(ev.objectives_done == 0);
    ev = b.update(0.016, .{ .x = 0, .y = 0 }, 0, &.{});
    try std.testing.expect(ev.objectives_done == 1);
    // Choice, then flags applied.
    try std.testing.expect(b.active().?.state == .awaiting_choice);
    try b.choose("m1", 0);
    try std.testing.expect(b.active() == null);
    try std.testing.expect(flags.get("kept_cash"));
    try std.testing.expect(flags.get("m1_done"));
}

test "prereq gating and fail/retry" {
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const d = try loadDefJson(arena.allocator(),
        \\{"id":"m2","required":["m1_done"],"objectives":[{"type":"survive","duration":1.0}]}
    );
    const defs = [_]MissionDef{d};
    var b = try Board.init(std.testing.allocator, &defs, &flags);
    defer b.deinit();
    try std.testing.expect(b.offered() == null);
    try flags.set("m1_done", true);
    try std.testing.expect(b.offered() != null);
    try b.start("m2");
    b.failActive();
    try std.testing.expect(b.offered() != null); // retryable
    try b.start("m2");
    const ev = b.update(2.0, .{}, 0, &.{});
    try std.testing.expect(ev.completed_id != null);
}

test "save/load roundtrip" {
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const d = try loadDefJson(arena.allocator(), DEF_JSON);
    const defs = [_]MissionDef{d};
    var b = try Board.init(std.testing.allocator, &defs, &flags);
    defer b.deinit();
    try b.start("m1");
    _ = b.update(0.016, .{ .x = 100, .y = 200 }, 0, &.{});
    const data = try b.save(std.testing.allocator);
    defer std.testing.allocator.free(data);
    try std.testing.expect(data[0].obj_idx == 1);
    // Fresh board restores progress.
    var b2 = try Board.init(std.testing.allocator, &defs, &flags);
    defer b2.deinit();
    b2.load(data);
    try std.testing.expect(b2.runs.items[0].state == .active);
    try std.testing.expect(b2.runs.items[0].obj_idx == 1);
}
