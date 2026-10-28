//! Frame-rate measurement: an exponentially-smoothed instantaneous rate plus a
//! once-per-interval average that is stable enough to read on screen.
const std = @import("std");

pub const Counter = struct {
    /// Seconds between updates of `average`.
    interval: f64 = 0.5,
    /// Frames per second averaged over the last full interval.
    average: f64 = 0,
    /// Smoothed instantaneous frame time in seconds.
    frame_time: f64 = 0,

    window_start: ?f64 = null,
    window_frames: u32 = 0,
    last: ?f64 = null,

    /// Records a frame presented at time `now` (seconds). Returns true when `average` changed.
    pub fn tick(self: *Counter, now: f64) bool {
        if (self.last) |last| {
            const dt = now - last;
            self.frame_time = if (self.frame_time == 0) dt else self.frame_time * 0.9 + dt * 0.1;
        }
        self.last = now;

        const start = self.window_start orelse {
            self.window_start = now;
            return false;
        };
        self.window_frames += 1;
        const elapsed = now - start;
        if (elapsed < self.interval) return false;

        self.average = @as(f64, @floatFromInt(self.window_frames)) / elapsed;
        self.window_frames = 0;
        self.window_start = now;
        return true;
    }
};

test "steady 60 Hz reports 60 fps" {
    var c: Counter = .{};
    var updated = false;
    for (0..61) |i| {
        if (c.tick(@as(f64, @floatFromInt(i)) / 60.0)) updated = true;
    }
    try std.testing.expect(updated);
    try std.testing.expectApproxEqAbs(@as(f64, 60), c.average, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 60.0), c.frame_time, 1e-6);
}

test "no average before the first interval elapses" {
    var c: Counter = .{};
    try std.testing.expect(!c.tick(0));
    try std.testing.expect(!c.tick(0.1));
    try std.testing.expectEqual(@as(f64, 0), c.average);
}
