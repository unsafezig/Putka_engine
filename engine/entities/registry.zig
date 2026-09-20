//! Slot-map registry: dense slots, generational ids, free-list reuse.
//! Components live elsewhere; this only manages lifetimes.

const EntityId = @import("id.zig").EntityId;

const Slot = struct {
    generation: u32 = 0,
    alive: bool = false,
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    slots: std.ArrayList(Slot),
    free: std.ArrayList(u32),
    alive_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .slots = .empty,
            .free = .empty,
        };
    }

    pub fn deinit(self: *Registry) void {
        self.slots.deinit(self.allocator);
        self.free.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn spawn(self: *Registry) !EntityId {
        if (self.free.pop()) |index| {
            const slot = &self.slots.items[index];
            slot.alive = true;
            self.alive_count += 1;
            return .{ .index = index, .generation = slot.generation };
        } else {
            const index: u32 = @intCast(self.slots.items.len);
            try self.slots.append(self.allocator, .{ .alive = true });
            self.alive_count += 1;
            return .{ .index = index, .generation = 0 };
        }
    }

    pub fn despawn(self: *Registry, id: EntityId) bool {
        if (!self.isAlive(id)) return false;
        const slot = &self.slots.items[id.index];
        slot.alive = false;
        slot.generation +|= 1;
        self.free.append(self.allocator, id.index) catch return true;
        self.alive_count -= 1;
        return true;
    }

    pub fn isAlive(self: Registry, id: EntityId) bool {
        if (id.isNull()) return false;
        if (id.index >= self.slots.items.len) return false;
        const slot = self.slots.items[id.index];
        return slot.alive and slot.generation == id.generation;
    }
};

const std = @import("std");

test "spawn / despawn / stale handle" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    const a = try reg.spawn();
    const b = try reg.spawn();
    try std.testing.expect(reg.isAlive(a));
    try std.testing.expect(reg.isAlive(b));
    try std.testing.expect(reg.despawn(a));
    try std.testing.expect(!reg.isAlive(a));
    try std.testing.expect(reg.isAlive(b));
    // Recycled index must invalidate the old handle.
    const c = try reg.spawn();
    try std.testing.expect(reg.isAlive(c));
    try std.testing.expect(!reg.isAlive(a));
}

test "despawn invalid is false" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    try std.testing.expect(!reg.despawn(.{ .index = 999, .generation = 0 }));
    try std.testing.expect(!reg.despawn(EntityId.NULL));
}
