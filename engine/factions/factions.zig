//! Factions: who hates whom. Small fixed set (engine-generic concepts);
//! the game assigns these to its characters. Symmetric relationships.

pub const Faction = enum(u8) {
    player = 0,
    police = 1,
    civilians = 2,
    gang_a = 3,
    gang_b = 4,
};

pub const Relation = enum {
    friendly,
    neutral,
    hostile,
};

pub const COUNT: usize = 5;

pub const Matrix = struct {
    rel: [COUNT][COUNT]Relation,

    pub fn initDefaults() Matrix {
        var m = Matrix{ .rel = .{.{.neutral} ** COUNT} ** COUNT };
        // Everyone likes themselves.
        for (0..COUNT) |i| m.rel[i][i] = .friendly;
        m.set(.gang_a, .gang_b, .hostile);
        m.set(.gang_a, .player, .hostile);
        m.set(.gang_b, .player, .hostile);
        m.set(.police, .gang_a, .hostile);
        m.set(.police, .gang_b, .hostile);
        // Police vs player starts neutral; wanted level drives hostility
        // in game logic (see police/wanted.zig).
        return m;
    }

    pub fn set(self: *Matrix, a: Faction, b: Faction, r: Relation) void {
        self.rel[@intFromEnum(a)][@intFromEnum(b)] = r;
        self.rel[@intFromEnum(b)][@intFromEnum(a)] = r;
    }

    pub fn get(self: Matrix, a: Faction, b: Faction) Relation {
        return self.rel[@intFromEnum(a)][@intFromEnum(b)];
    }
};

const std = @import("std");

test "defaults and symmetry" {
    var m = Matrix.initDefaults();
    try std.testing.expect(m.get(.player, .player) == .friendly);
    try std.testing.expect(m.get(.gang_a, .gang_b) == .hostile);
    try std.testing.expect(m.get(.police, .player) == .neutral);
    try std.testing.expect(m.get(.civilians, .gang_a) == .neutral);
    m.set(.police, .player, .hostile);
    try std.testing.expect(m.get(.player, .police) == .hostile);
}
