//! Fixed-timestep accumulator for deterministic simulation.
//! Rendering can run at any fps; simulation always steps at `dt`.

pub const FixedStep = struct {
    dt: f32,
    accumulator: f32 = 0,

    pub fn init(dt: f32) FixedStep {
        std.debug.assert(dt > 0);
        return .{ .dt = dt };
    }

    /// Add frame time, return how many simulation steps to run.
    /// `frame_dt` should already be clamped by the caller.
    pub fn push(self: *FixedStep, frame_dt: f32) u32 {
        self.accumulator += frame_dt;
        var steps: u32 = 0;
        while (self.accumulator >= self.dt) {
            self.accumulator -= self.dt;
            steps += 1;
            if (steps >= 8) {
                // Spiral-of-death guard: drop excess time.
                self.accumulator = 0;
                break;
            }
        }
        return steps;
    }
};

const std = @import("std");

test "fixed step accumulates" {
    var fs = FixedStep.init(1.0 / 60.0);
    try std.testing.expectEqual(@as(u32, 1), fs.push(1.0 / 60.0));
    try std.testing.expectEqual(@as(u32, 0), fs.push(fs.dt * 0.1));
    // Fresh accumulator: 2.5 steps worth -> 2 steps, 0.5 dt remains.
    var fs2 = FixedStep.init(0.1);
    try std.testing.expectEqual(@as(u32, 2), fs2.push(0.25));
    try std.testing.expectApproxEqAbs(@as(f32, 0.05), fs2.accumulator, 1e-5);
}

test "fixed step spiral guard" {
    var fs = FixedStep.init(1.0 / 60.0);
    const steps = fs.push(10.0);
    try std.testing.expect(steps <= 8);
    try std.testing.expectEqual(@as(f32, 0), fs.accumulator);
}
