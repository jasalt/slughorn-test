//! Keyboard bindings expressed in GLFW key codes. The numbers are GLFW's (stable, public
//! API values) so the same table serves the native build and the web build, whose JS
//! translates KeyboardEvent.code into these codes.
const std = @import("std");
const controls = @import("controls.zig");

pub const code = struct {
    pub const space = 32;
    pub const comma = 44;
    pub const minus = 45;
    pub const period = 46;
    pub const digit_0 = 48;
    pub const equal = 61;
    pub const letter_a = 65;
    pub const left_bracket = 91;
    pub const right_bracket = 93;
    pub const escape = 256;
    pub const tab = 258;
    pub const right = 262;
    pub const left = 263;
    pub const down = 264;
    pub const up = 265;
    pub const f1 = 290;
    pub const kp_0 = 320;
    pub const kp_subtract = 333;
    pub const kp_add = 334;
    /// One past the largest code used above.
    pub const count = 335;

    pub inline fn letter(comptime ch: u8) c_int {
        return letter_a + (ch - 'A');
    }
};

/// Keys bound to each held (continuous) control.
pub fn heldBindings(k: controls.Key) []const c_int {
    const l = code.letter;
    return switch (k) {
        .pan_left => &.{code.left},
        .pan_right => &.{code.right},
        .pan_up => &.{code.up},
        .pan_down => &.{code.down},
        .roll_ccw => &.{l('Q')},
        .roll_cw => &.{l('E')},
        .zoom_in => &.{ l('W'), code.equal, code.kp_add },
        .zoom_out => &.{ l('S'), code.minus, code.kp_subtract },
        .yaw_left => &.{l('J')},
        .yaw_right => &.{l('L')},
        .pitch_up => &.{l('I')},
        .pitch_down => &.{l('K')},
        .tail_longer => &.{code.right_bracket},
        .tail_shorter => &.{code.left_bracket},
        .hue_up => &.{code.period},
        .hue_down => &.{code.comma},
        else => &.{},
    };
}

/// One-shot control for a key press, if any.
pub fn pressed(key: c_int) ?controls.Key {
    const l = code.letter;
    return switch (key) {
        code.digit_0, code.kp_0 => .seed_0,
        code.digit_0 + 1, code.kp_0 + 1 => .seed_1,
        code.digit_0 + 2, code.kp_0 + 2 => .seed_2,
        code.digit_0 + 3, code.kp_0 + 3 => .seed_3,
        code.digit_0 + 4, code.kp_0 + 4 => .seed_4,
        code.tab => .seed_next,
        code.space => .pause,
        l('C') => .clear,
        l('R') => .reset,
        l('H') => .toggle_hud,
        code.f1 => .toggle_help,
        l('B') => .toggle_border,
        l('M') => .toggle_follow,
        l('V') => .toggle_vsync,
        code.escape => .quit,
        else => null,
    };
}

/// Held controls given a predicate telling whether a key code is down.
pub fn heldKeys(is_down: anytype) std.EnumSet(controls.Key) {
    var set: std.EnumSet(controls.Key) = .empty;
    for (controls.held_keys) |k| {
        for (heldBindings(k)) |c| {
            if (is_down.isDown(c)) {
                set.insert(k);
                break;
            }
        }
    }
    return set;
}

test "bindings resolve both ways" {
    try std.testing.expectEqual(controls.Key.seed_3, pressed(code.kp_0 + 3).?);
    try std.testing.expectEqual(controls.Key.toggle_help, pressed(code.f1).?);
    try std.testing.expect(pressed(code.letter('Z')) == null);

    const Down = struct {
        fn isDown(_: @This(), c: c_int) bool {
            return c == code.kp_add or c == code.left;
        }
    };
    const held = heldKeys(Down{});
    try std.testing.expect(held.contains(.zoom_in));
    try std.testing.expect(held.contains(.pan_left));
    try std.testing.expectEqual(@as(usize, 2), held.count());
}
