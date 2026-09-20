//! Generic 6-level wanted system (0-5).
//! Crimes add heat (amounts from data, see `data/putka/crimes.json`);
//! heat continuously cools down. Level is a pure function of heat so
//! saves only need the heat value.

pub const CrimeTable = struct {
    gunshot: f32 = 8, // firing a weapon (noise)
    kill: f32 = 60, // killing a civilian
    carjack: f32 = 25, // stealing an occupied vehicle (reserved)
    runover: f32 = 45, // killing with a vehicle
};

pub fn loadCrimeTableJson(allocator: std.mem.Allocator, text: []const u8) !CrimeTable {
    const parsed = try std.json.parseFromSlice(CrimeTable, allocator, text, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    return parsed.value;
}

/// Heat thresholds at which each level starts.
pub const LEVEL_AT: [6]f32 = .{ 0, 25, 60, 100, 150, 190 };

pub const Wanted = struct {
    heat: f32 = 0,

    pub fn addHeat(self: *Wanted, amount: f32) void {
        self.heat = @min(self.heat + amount, 220);
    }

    pub fn level(self: Wanted) u8 {
        var l: u8 = 0;
        for (LEVEL_AT, 0..) |at, i| {
            if (self.heat >= at) l = @intCast(i);
        }
        return l;
    }

    /// Cool down. `calm` when the player is laying low.
    pub fn update(self: *Wanted, dt: f32, calm: bool) void {
        const rate: f32 = if (calm) 9 else 2.5;
        self.heat = @max(0, self.heat - rate * dt);
    }
};

const std = @import("std");

test "heat maps to levels" {
    var w = Wanted{};
    try std.testing.expectEqual(@as(u8, 0), w.level());
    w.addHeat(30);
    try std.testing.expectEqual(@as(u8, 1), w.level());
    w.addHeat(200);
    try std.testing.expectEqual(@as(u8, 5), w.level());
}

test "heat cools and level drops" {
    var w = Wanted{};
    w.addHeat(100);
    try std.testing.expectEqual(@as(u8, 3), w.level());
    w.update(10, true); // -90
    try std.testing.expect(w.level() < 3);
    w.update(100, true);
    try std.testing.expectEqual(@as(u8, 0), w.level());
}

test "crime table json parses" {
    const t = try loadCrimeTableJson(std.testing.allocator,
        \\{"gunshot":8.0,"kill":60.0}
    );
    try std.testing.expectApproxEqAbs(@as(f32, 8), t.gunshot, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 25), t.carjack, 1e-4); // default kept
}
