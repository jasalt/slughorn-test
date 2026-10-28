//! The "picture plane": a rectangle showing the previous frame, viewed through a virtual
//! camera. Moving it relative to the camera is what drives the video-feedback image, just
//! like pointing a real camera at the monitor it feeds.
const std = @import("std");
const Mat4 = @import("math.zig").Mat4;

/// Camera distance from the plane. With fovy = 2*atan(1/distance) an untransformed
/// plane spanning [-aspect, aspect] x [-1, 1] exactly fills the viewport.
pub const distance: f32 = 2.0;
pub const fovy: f32 = 2.0 * std.math.atan(1.0 / distance);

pub const min_zoom: f32 = 0.2;
pub const max_zoom: f32 = 5.0;
pub const max_tilt: f32 = 1.2;

pub const Plane = struct {
    /// Offset of the plane centre, in units of half the viewport height.
    pan_x: f32 = 0,
    pan_y: f32 = 0,
    /// Rotation around the view axis (radians).
    roll: f32 = 0.02,
    /// Rotation around the plane's vertical / horizontal axes (radians).
    yaw: f32 = 0,
    pitch: f32 = 0,
    /// Uniform scale of the plane; >1 makes the feedback tunnel expand outward.
    zoom: f32 = 1.03,

    pub fn reset(self: *Plane) void {
        self.* = .{};
    }

    pub fn pan(self: *Plane, dx: f32, dy: f32) void {
        self.pan_x = std.math.clamp(self.pan_x + dx, -2, 2);
        self.pan_y = std.math.clamp(self.pan_y + dy, -2, 2);
    }

    pub fn rotate(self: *Plane, d: f32) void {
        self.roll = wrapAngle(self.roll + d);
    }

    pub fn tilt(self: *Plane, dyaw: f32, dpitch: f32) void {
        self.yaw = std.math.clamp(self.yaw + dyaw, -max_tilt, max_tilt);
        self.pitch = std.math.clamp(self.pitch + dpitch, -max_tilt, max_tilt);
    }

    /// Multiplicative zoom: `factor` of 1 leaves it unchanged.
    pub fn zoomBy(self: *Plane, factor: f32) void {
        self.zoom = std.math.clamp(self.zoom * factor, min_zoom, max_zoom);
    }

    pub fn model(self: Plane) Mat4 {
        return Mat4.translate(self.pan_x, self.pan_y, 0)
            .mul(Mat4.rotateZ(self.roll))
            .mul(Mat4.rotateY(self.yaw))
            .mul(Mat4.rotateX(self.pitch))
            .mul(Mat4.scale(self.zoom, self.zoom, 1));
    }

    /// Full model-view-projection for drawing the plane quad (corners at (±aspect, ±1, 0)).
    pub fn mvp(self: Plane, aspect: f32) Mat4 {
        const proj = Mat4.perspective(fovy, aspect, 0.05, 50);
        const view = Mat4.translate(0, 0, -distance);
        return proj.mul(view).mul(self.model());
    }
};

fn wrapAngle(a: f32) f32 {
    const tau = 2.0 * std.math.pi;
    return a - tau * @floor((a + std.math.pi) / tau);
}

test "identity plane fills the viewport exactly" {
    const p: Plane = .{ .roll = 0, .zoom = 1 };
    const aspect: f32 = 16.0 / 9.0;
    const m = p.mvp(aspect);
    const tl = m.project(.{ -aspect, 1, 0 });
    const br = m.project(.{ aspect, -1, 0 });
    try std.testing.expectApproxEqAbs(@as(f32, -1), tl[0], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 1), tl[1], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 1), br[0], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, -1), br[1], 1e-4);
}

test "zoom scales the projected plane" {
    const p: Plane = .{ .roll = 0, .zoom = 2 };
    const c = p.mvp(1).project(.{ 0.5, 0, 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 1), c[0], 1e-4);
}

test "pan moves the plane centre" {
    var p: Plane = .{ .roll = 0, .zoom = 1 };
    p.pan(0.5, -0.25);
    const c = p.mvp(1).project(.{ 0, 0, 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), c[0], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, -0.25), c[1], 1e-4);
}

test "yaw makes the plane trapezoidal" {
    var p: Plane = .{ .roll = 0, .zoom = 1 };
    p.tilt(0.5, 0);
    const m = p.mvp(1);
    const left_h = m.project(.{ -1, 1, 0 })[1];
    const right_h = m.project(.{ 1, 1, 0 })[1];
    try std.testing.expect(@abs(left_h - right_h) > 0.05);
}

test "controls are clamped and wrapped" {
    var p: Plane = .{};
    p.zoomBy(1000);
    try std.testing.expectEqual(max_zoom, p.zoom);
    p.tilt(10, -10);
    try std.testing.expectEqual(max_tilt, p.yaw);
    try std.testing.expectEqual(-max_tilt, p.pitch);
    p.rotate(7);
    try std.testing.expect(p.roll >= -std.math.pi and p.roll <= std.math.pi);
    p.reset();
    try std.testing.expectEqual(Plane{}, p);
}
