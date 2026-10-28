//! Maps device-independent mouse/keyboard events onto the picture plane and feedback
//! parameters. Kept free of GLFW so it can be tested headless.
const std = @import("std");
const Plane = @import("camera.zig").Plane;
const feedback = @import("feedback.zig");

pub const Button = enum { left, right, middle };

pub const Key = enum {
    pan_left,
    pan_right,
    pan_up,
    pan_down,
    roll_ccw,
    roll_cw,
    zoom_in,
    zoom_out,
    yaw_left,
    yaw_right,
    pitch_up,
    pitch_down,
    tail_longer,
    tail_shorter,
    hue_up,
    hue_down,
    seed_next,
    seed_0,
    seed_1,
    seed_2,
    seed_3,
    seed_4,
    pause,
    clear,
    reset,
    toggle_hud,
    toggle_help,
    toggle_border,
    toggle_follow,
    toggle_vsync,
    quit,
};

/// Keys that act continuously while held (scaled by frame time).
pub const held_keys = [_]Key{
    .pan_left,  .pan_right, .pan_up,      .pan_down,     .roll_ccw, .roll_cw,
    .zoom_in,   .zoom_out,  .yaw_left,    .yaw_right,    .pitch_up, .pitch_down,
    .hue_up,    .hue_down,  .tail_longer, .tail_shorter,
};

pub const Seed = enum {
    none,
    stars,
    rings,
    text,
    spiral,

    pub fn label(self: Seed) []const u8 {
        return switch (self) {
            .none => "NONE",
            .stars => "STARS",
            .rings => "RINGS",
            .text => "TEXT",
            .spiral => "SPIRAL",
        };
    }
};

// Rates per second for held keys, and per pixel for mouse drags.
const pan_rate: f32 = 0.6;
const roll_rate: f32 = 0.8;
const zoom_rate: f32 = 0.5;
const tilt_rate: f32 = 0.6;
const hue_rate: f32 = 0.1;
const tail_rate: f32 = 4;
const drag_roll: f32 = 0.005;
const drag_zoom: f32 = 0.004;
const drag_tilt: f32 = 0.004;
const wheel_zoom: f32 = 0.02;

pub const State = struct {
    plane: Plane = .{},
    params: feedback.Params = .{},
    seed: Seed = .stars,
    paused: bool = false,
    show_hud: bool = true,
    show_help: bool = false,
    border: bool = false,
    /// Seed shapes are drawn at the mouse cursor instead of the screen centre.
    follow_cursor: bool = false,
    vsync: bool = true,
    quit: bool = false,
    /// Set when the feedback buffers should be wiped; the renderer clears it.
    clear_requested: bool = false,

    cursor: [2]f64 = .{ 0, 0 },
    buttons: std.EnumSet(Button) = .empty,
    /// Shift/ctrl held when the left button went down; turns a left drag into a tilt.
    left_tilts: bool = false,

    pub fn mouseButton(self: *State, button: Button, pressed: bool, modifier: bool) void {
        if (pressed) self.buttons.insert(button) else self.buttons.remove(button);
        if (button == .left and pressed) self.left_tilts = modifier;
    }

    /// Cursor moved to (x, y) in window pixels (y down); `height` is the window height.
    pub fn cursorMoved(self: *State, x: f64, y: f64, height: f64) void {
        const dx: f32 = @floatCast(x - self.cursor[0]);
        const dy: f32 = @floatCast(y - self.cursor[1]);
        self.cursor = .{ x, y };

        if (self.buttons.contains(.left)) {
            if (self.left_tilts) {
                self.plane.tilt(dx * drag_tilt, dy * drag_tilt);
            } else {
                // Plane units are half the viewport height.
                const scale: f32 = @floatCast(2.0 / @max(height, 1));
                self.plane.pan(dx * scale, -dy * scale);
            }
        }
        if (self.buttons.contains(.right)) {
            self.plane.rotate(-dx * drag_roll);
            self.plane.zoomBy(@exp(-dy * drag_zoom));
        }
        if (self.buttons.contains(.middle)) self.plane.tilt(dx * drag_tilt, dy * drag_tilt);
    }

    pub fn scroll(self: *State, dy: f64) void {
        self.plane.zoomBy(@exp(@as(f32, @floatCast(dy)) * wheel_zoom));
    }

    /// One-shot key press.
    pub fn keyPressed(self: *State, key: Key) void {
        switch (key) {
            .seed_next => self.seed = @enumFromInt((@intFromEnum(self.seed) + 1) % std.enums.values(Seed).len),
            .seed_0 => self.seed = .none,
            .seed_1 => self.seed = .stars,
            .seed_2 => self.seed = .rings,
            .seed_3 => self.seed = .text,
            .seed_4 => self.seed = .spiral,
            .pause => self.paused = !self.paused,
            .clear => self.clear_requested = true,
            .reset => {
                self.plane.reset();
                self.params = .{};
                self.clear_requested = true;
            },
            .toggle_hud => self.show_hud = !self.show_hud,
            .toggle_help => self.show_help = !self.show_help,
            .toggle_border => self.border = !self.border,
            .toggle_follow => self.follow_cursor = !self.follow_cursor,
            .toggle_vsync => self.vsync = !self.vsync,
            .quit => self.quit = true,
            else => {},
        }
    }

    /// Continuous adjustment for a key held during a frame of `dt` seconds.
    pub fn keyHeld(self: *State, key: Key, dt: f32) void {
        switch (key) {
            .pan_left => self.plane.pan(-pan_rate * dt, 0),
            .pan_right => self.plane.pan(pan_rate * dt, 0),
            .pan_up => self.plane.pan(0, pan_rate * dt),
            .pan_down => self.plane.pan(0, -pan_rate * dt),
            .roll_ccw => self.plane.rotate(roll_rate * dt),
            .roll_cw => self.plane.rotate(-roll_rate * dt),
            .zoom_in => self.plane.zoomBy(@exp(zoom_rate * dt)),
            .zoom_out => self.plane.zoomBy(@exp(-zoom_rate * dt)),
            .yaw_left => self.plane.tilt(-tilt_rate * dt, 0),
            .yaw_right => self.plane.tilt(tilt_rate * dt, 0),
            .pitch_up => self.plane.tilt(0, -tilt_rate * dt),
            .pitch_down => self.plane.tilt(0, tilt_rate * dt),
            .hue_up => self.params.adjustHue(hue_rate * dt),
            .hue_down => self.params.adjustHue(-hue_rate * dt),
            .tail_longer => self.params.adjustTail(tail_rate * dt),
            .tail_shorter => self.params.adjustTail(-tail_rate * dt),
            else => {},
        }
    }
};

test "left drag pans by viewport-relative distance" {
    var s: State = .{ .plane = .{ .roll = 0 } };
    s.cursorMoved(100, 100, 600);
    s.mouseButton(.left, true, false);
    s.cursorMoved(400, 100, 600);
    try std.testing.expectApproxEqAbs(@as(f32, 1), s.plane.pan_x, 1e-5);
    s.cursorMoved(400, 250, 600);
    try std.testing.expectApproxEqAbs(@as(f32, -0.5), s.plane.pan_y, 1e-5);
    s.mouseButton(.left, false, false);
    s.cursorMoved(0, 0, 600);
    try std.testing.expectApproxEqAbs(@as(f32, 1), s.plane.pan_x, 1e-5);
}

test "modified left drag and middle drag tilt the plane" {
    var s: State = .{};
    s.mouseButton(.left, true, true);
    s.cursorMoved(50, 0, 600);
    try std.testing.expect(s.plane.yaw > 0);
    try std.testing.expectEqual(@as(f32, 0), s.plane.pan_x);
    s.mouseButton(.left, false, false);
    s.mouseButton(.middle, true, false);
    s.cursorMoved(50, 40, 600);
    try std.testing.expect(s.plane.pitch > 0);
}

test "right drag rolls and zooms, wheel zooms" {
    var s: State = .{};
    const roll0 = s.plane.roll;
    const zoom0 = s.plane.zoom;
    s.mouseButton(.right, true, false);
    s.cursorMoved(-20, -30, 600);
    try std.testing.expect(s.plane.roll > roll0);
    try std.testing.expect(s.plane.zoom > zoom0);
    const zoom1 = s.plane.zoom;
    s.scroll(-3);
    try std.testing.expect(s.plane.zoom < zoom1);
}

test "held keys scale with frame time" {
    var a: State = .{};
    var b: State = .{};
    a.keyHeld(.pan_right, 0.1);
    b.keyHeld(.pan_right, 0.05);
    b.keyHeld(.pan_right, 0.05);
    try std.testing.expectApproxEqAbs(a.plane.pan_x, b.plane.pan_x, 1e-6);

    const tail0 = a.params.tail;
    a.keyHeld(.tail_longer, 0.5);
    try std.testing.expect(a.params.tail > tail0);
}

test "key presses toggle state and reset restores defaults" {
    var s: State = .{};
    s.keyPressed(.seed_next);
    try std.testing.expectEqual(Seed.rings, s.seed);
    s.keyPressed(.seed_4);
    s.keyPressed(.seed_next);
    try std.testing.expectEqual(Seed.none, s.seed);
    s.keyPressed(.pause);
    try std.testing.expect(s.paused);
    s.keyHeld(.zoom_in, 1);
    s.keyPressed(.reset);
    try std.testing.expectEqual(Plane{}, s.plane);
    try std.testing.expect(s.clear_requested);
    s.keyPressed(.quit);
    try std.testing.expect(s.quit);
}
