//! Parameters of the feedback loop that are not camera geometry.
const std = @import("std");

pub const min_tail: f32 = 0;
pub const max_tail: f32 = 0.995;

pub const Params = struct {
    /// Per-frame gain applied to the previous image (0 = no trail, ~1 = endless trail).
    tail: f32 = 0.94,
    /// Hue rotation applied per feedback pass (radians).
    hue_shift: f32 = 0.03,

    /// Lengthens (positive steps) or shortens (negative) the tail. Steps act on the
    /// remaining distance to 1 so control stays fine-grained near long tails.
    pub fn adjustTail(self: *Params, steps: f32) void {
        const decay = 1 - self.tail;
        const next = 1 - decay * std.math.pow(f32, 0.85, steps);
        self.tail = std.math.clamp(next, min_tail, max_tail);
    }

    pub fn adjustHue(self: *Params, d: f32) void {
        self.hue_shift = std.math.clamp(self.hue_shift + d, -0.5, 0.5);
    }

    /// Frames until a pixel decays to 1% of its brightness.
    pub fn tailFrames(self: Params) f32 {
        if (self.tail <= 0) return 0;
        return @log(0.01) / @log(self.tail);
    }
};

test "tail adjustment is monotonic and clamped" {
    var p: Params = .{};
    const start = p.tail;
    p.adjustTail(1);
    try std.testing.expect(p.tail > start);
    p.adjustTail(-2);
    try std.testing.expect(p.tail < start);
    p.adjustTail(1000);
    try std.testing.expectEqual(max_tail, p.tail);
    p.adjustTail(-1000);
    try std.testing.expect(p.tail >= min_tail and p.tail < 0.01);
}

test "tail frames" {
    const p: Params = .{ .tail = 0.9 };
    try std.testing.expectApproxEqAbs(@as(f32, 43.7), p.tailFrames(), 0.1);
}
