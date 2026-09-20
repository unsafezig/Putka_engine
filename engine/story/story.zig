//! Explicit story state: named boolean flags.
//! Choices and mission completion set flags; mission availability reads
//! them. Serialized as a key/value list inside the save snapshot.

pub const Flag = struct {
    key: []const u8 = "",
    value: bool = false,
};

pub const Flags = struct {
    map: std.StringHashMap(bool),

    pub fn init(allocator: std.mem.Allocator) Flags {
        return .{ .map = std.StringHashMap(bool).init(allocator) };
    }

    pub fn deinit(self: *Flags) void {
        self.map.deinit();
        self.* = undefined;
    }

    /// Key is borrowed, not copied: it must outlive `Flags`
    /// (static strings, def data, or a caller-owned arena).
    pub fn set(self: *Flags, key: []const u8, value: bool) !void {
        try self.map.put(key, value);
    }

    pub fn get(self: Flags, key: []const u8) bool {
        return self.map.get(key) orelse false;
    }

    /// All `required` must be true.
    pub fn satisfies(self: Flags, required: []const []const u8) bool {
        for (required) |key| {
            if (!self.get(key)) return false;
        }
        return true;
    }

    pub fn toList(self: Flags, alloc: std.mem.Allocator) ![]Flag {
        var out = try alloc.alloc(Flag, self.map.count());
        var it = self.map.iterator();
        var i: usize = 0;
        while (it.next()) |kv| {
            out[i] = .{ .key = kv.key_ptr.*, .value = kv.value_ptr.* };
            i += 1;
        }
        return out;
    }

    pub fn loadList(self: *Flags, flags: []const Flag) !void {
        for (flags) |f| try self.set(f.key, f.value);
    }
};

const std = @import("std");

test "set/get/satisfies" {
    var f = Flags.init(std.testing.allocator);
    defer f.deinit();
    try std.testing.expect(!f.get("met_timo"));
    try f.set("met_timo", true);
    try std.testing.expect(f.get("met_timo"));
    try std.testing.expect(f.satisfies(&.{ "met_timo" }));
    try std.testing.expect(!f.satisfies(&.{ "met_timo", "owes_money" }));
}

test "list roundtrip" {
    var f = Flags.init(std.testing.allocator);
    defer f.deinit();
    try f.set("a", true);
    try f.set("b", false);
    const list = try f.toList(std.testing.allocator);
    defer std.testing.allocator.free(list);
    try std.testing.expectEqual(@as(usize, 2), list.len);
    var g = Flags.init(std.testing.allocator);
    defer g.deinit();
    try g.loadList(list);
    try std.testing.expect(g.get("a"));
    try std.testing.expect(!g.get("b"));
}
