//! Backend-independent input intent.
//! raylib/SDL/etc. map physical keys into this struct; simulation only
//! reads `Intent`. This keeps gameplay deterministic and testable.

const Vec2 = @import("../math/vec2.zig").Vec2;

pub const Intent = struct {
    move: Vec2 = .{}, // normalized-ish wish direction, length 0..1
    action: bool = false, // E / interact: enter/exit vehicle, talk, ...
    sprint: bool = false,

    pub fn fromKeys(up: bool, down: bool, left: bool, right: bool) Intent {
        var m: Vec2 = .{};
        if (up) m.y -= 1;
        if (down) m.y += 1;
        if (left) m.x -= 1;
        if (right) m.x += 1;
        if (m.lengthSq() > 1) m = m.normalized();
        return .{ .move = m };
    }
};

const std = @import("std");

test "intent cardinal + diagonal normalize" {
    const i = Intent.fromKeys(true, false, false, false);
    try std.testing.expect(i.move.eql(.{ .x = 0, .y = -1 }));
    const d = Intent.fromKeys(true, false, false, true);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), d.move.length(), 1e-5);
    const none = Intent.fromKeys(false, false, false, false);
    try std.testing.expect(none.move.eql(.{}));
}
