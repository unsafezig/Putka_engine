//! Dialogue system: data-driven trees (JSON), explicit runtime cursor.
//! Options can require story flags, set flags, jump to nodes, and —
//! through `mission_choice` — answer a mission board branch, so mission
//! choices render through the same UI as NPC talk.

const Flags = @import("../story/story.zig").Flags;

pub const OptionDef = struct {
    text: []const u8 = "",
    /// Empty goto ends the conversation after applying `set`.
    goto: []const u8 = "",
    set: []const []const u8 = &.{},
    requires: []const []const u8 = &.{},
    /// When set, picking this answers mission-board choice `mission_choice`.
    mission_choice: ?u32 = null,
};

pub const NodeDef = struct {
    id: []const u8 = "",
    speaker: []const u8 = "",
    text: []const u8 = "",
    options: []const OptionDef = &.{},
};

pub const DialogueDef = struct {
    id: []const u8 = "",
    start: []const u8 = "",
    nodes: []const NodeDef = &.{},
};

pub const DefError = error{ NoNodes, UnknownStart, UnknownGoto, DuplicateNode };

/// Load a def; all memory is owned by `arena` (same pattern as missions).
pub fn loadDefJson(arena: std.mem.Allocator, text: []const u8) !DialogueDef {
    return std.json.parseFromSliceLeaky(DialogueDef, arena, text, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}

fn findNode(def: *const DialogueDef, id: []const u8) ?*const NodeDef {
    for (def.nodes) |*n| {
        if (std.mem.eql(u8, n.id, id)) return n;
    }
    return null;
}

/// Validate structure: start exists, gotos resolve, node ids unique.
pub fn validate(def: *const DialogueDef) DefError!void {
    if (def.nodes.len == 0) return DefError.NoNodes;
    if (findNode(def, def.start) == null) return DefError.UnknownStart;
    for (def.nodes, 0..) |*n, i| {
        for (def.nodes[0..i]) |*m| {
            if (std.mem.eql(u8, n.id, m.id)) return DefError.DuplicateNode;
        }
        for (n.options) |*o| {
            if (o.goto.len > 0 and findNode(def, o.goto) == null) return DefError.UnknownGoto;
        }
    }
}

pub const Conversation = struct {
    def: *const DialogueDef,
    node: *const NodeDef,
    over: bool = false,

    pub fn start(def: *const DialogueDef) DefError!Conversation {
        const n = findNode(def, def.start) orelse return DefError.UnknownStart;
        return .{ .def = def, .node = n };
    }

    /// Visible options for current node (requirements checked).
    /// Returns count; indices 0..count map to the underlying options.
    pub fn visible(self: Conversation, flags: *const Flags, out: []u8) usize {
        var n: usize = 0;
        for (self.node.options, 0..) |*o, i| {
            if (i >= 255) break;
            if (!flags.satisfies(o.requires)) continue;
            if (n >= out.len) break;
            out[n] = @intCast(i);
            n += 1;
        }
        return n;
    }

    pub const Picked = struct {
        ended: bool,
        mission_choice: ?u32,
    };

    /// Pick a *visible* option index (see `visible`). Applies `set` flags,
    /// follows `goto`, reports mission answers. Game closes on `ended`.
    pub fn select(self: *Conversation, flags: *Flags, visible_idx: usize) !Picked {
        var map: [16]u8 = undefined;
        const n = self.visible(flags, &map);
        if (visible_idx >= n) return error.BadOption;
        const o = &self.node.options[map[visible_idx]];
        for (o.set) |f| try flags.set(f, true);
        const choice = o.mission_choice;
        if (o.goto.len == 0) {
            self.over = true;
            return .{ .ended = true, .mission_choice = choice };
        }
        self.node = findNode(self.def, o.goto) orelse return error.BadGoto;
        return .{ .ended = false, .mission_choice = choice };
    }
};

const std = @import("std");

const DLG_JSON =
    \\{"id":"t","start":"a","nodes":[
    \\{"id":"a","speaker":"X","text":"Q?","options":[
    \\{"text":"Yes","goto":"b","set":["said_yes"]},
    \\{"text":"Secret","goto":"b","requires":["knows"]},
    \\{"text":"Bye","goto":""}]},
    \\{"id":"b","speaker":"X","text":"Done.","options":[]}]}
;

test "parse + validate ok" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const d = try loadDefJson(arena.allocator(), DLG_JSON);
    try validate(&d);
    try std.testing.expectEqualStrings("t", d.id);
}

test "validate rejects broken defs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const no_start = try loadDefJson(arena.allocator(),
        \\{"id":"x","start":"missing","nodes":[{"id":"a","text":""}]}
    );
    try std.testing.expectError(DefError.UnknownStart, validate(&no_start));
    const bad_goto = try loadDefJson(arena.allocator(),
        \\{"id":"x","start":"a","nodes":[{"id":"a","text":"","options":[{"text":"?","goto":"nowhere"}]}]}
    );
    try std.testing.expectError(DefError.UnknownGoto, validate(&bad_goto));
}

test "linear flow sets flags and ends" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const d = try loadDefJson(arena.allocator(), DLG_JSON);
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();
    var c = try Conversation.start(&d);
    try std.testing.expectEqualStrings("Q?", c.node.text);
    // "Secret" hidden without the flag: only 2 visible.
    var map: [8]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 2), c.visible(&flags, &map));
    const r = try c.select(&flags, 0);
    try std.testing.expect(!r.ended);
    try std.testing.expect(flags.get("said_yes"));
    try std.testing.expectEqualStrings("Done.", c.node.text);
    // End node has no options.
    try std.testing.expectEqual(@as(usize, 0), c.visible(&flags, &map));
}

test "requires gate options" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const d = try loadDefJson(arena.allocator(), DLG_JSON);
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();
    try flags.set("knows", true);
    var c = try Conversation.start(&d);
    var map: [8]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 3), c.visible(&flags, &map));
}

test "mission_choice passes through" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const d = try loadDefJson(arena.allocator(),
        \\{"id":"m","start":"a","nodes":[{"id":"a","speaker":"F","text":"Pick.","options":[
        \\{"text":"One","mission_choice":0},
        \\{"text":"Two","mission_choice":1}]}]}
    );
    var flags = Flags.init(std.testing.allocator);
    defer flags.deinit();
    var c = try Conversation.start(&d);
    const r = try c.select(&flags, 1);
    try std.testing.expect(r.ended);
    try std.testing.expectEqual(@as(?u32, 1), r.mission_choice);
}
