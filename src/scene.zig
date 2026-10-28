//! What gets drawn each frame, independent of GL: the animated vector "seed" injected
//! into the feedback loop and the HUD overlay (FPS, tail and camera readouts, help).
const std = @import("std");
const geometry = @import("geometry.zig");
const shapes = @import("shapes.zig");
const controls = @import("controls.zig");
const Batch = geometry.Batch;
const ShapeTable = geometry.ShapeTable;

pub const hud_text_size: f32 = 18;
const hud_margin: f32 = 12;
const hud_color = [4]f32{ 0.95, 0.95, 0.95, 1 };
const hud_panel = [4]f32{ 0, 0, 0, 0.6 };

pub const help_text =
    \\MOUSE
    \\  LEFT DRAG      PAN PLANE
    \\  RIGHT DRAG     ROLL + ZOOM
    \\  MIDDLE DRAG    TILT (OR SHIFT+LEFT)
    \\  WHEEL          ZOOM
    \\KEYS
    \\  ARROWS         PAN
    \\  Q E            ROLL
    \\  W S            ZOOM
    \\  J L / I K      YAW / PITCH
    \\  [ ]            TAIL SHORTER / LONGER
    \\  , .            HUE SHIFT
    \\  0-4 TAB        SEED SHAPE
    \\  SPACE          PAUSE SEED
    \\  B M            BORDER / FOLLOW MOUSE
    \\  C R            CLEAR / RESET
    \\  H V F1 ESC     HUD / VSYNC / HELP / QUIT
;

/// Appends the seed for `seed` at time `t` (seconds) centred on (cx, cy), with `unit`
/// pixels being the reference size (typically a fraction of the viewport height).
pub fn buildSeed(batch: *Batch, gpa: std.mem.Allocator, table: ShapeTable, seed: controls.Seed, t: f32, cx: f32, cy: f32, unit: f32) !void {
    const hue = t * 0.07;
    switch (seed) {
        .none => {},
        .stars => {
            if (table.get(.star)) |s| try batch.addShape(gpa, s, .{ .x = cx, .y = cy, .size = unit * 0.45, .angle = t * 0.9 }, color(hue, 1));
            if (table.get(.heart)) |s| {
                for (0..3) |i| {
                    const a = t * 1.3 + @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / 3.0;
                    const r = unit * 0.38;
                    try batch.addShape(gpa, s, .{
                        .x = cx + r * @cos(a),
                        .y = cy + r * @sin(a),
                        .size = unit * 0.14,
                        .angle = a - std.math.pi / 2.0,
                    }, color(hue + 0.33 + @as(f32, @floatFromInt(i)) * 0.1, 1));
                }
            }
        },
        .rings => {
            const pulse = 0.5 + 0.5 * @sin(t * 2.2);
            if (table.get(.ring)) |s| try batch.addShape(gpa, s, .{ .x = cx, .y = cy, .size = unit * (0.3 + 0.25 * pulse) }, color(hue, 1));
            if (table.get(.flower)) |s| {
                for (0..2) |i| {
                    const dir: f32 = if (i == 0) 1 else -1;
                    try batch.addShape(gpa, s, .{
                        .x = cx + dir * unit * 0.45 * @cos(t * 0.7),
                        .y = cy + dir * unit * 0.25 * @sin(t * 1.1),
                        .size = unit * 0.2,
                        .angle = dir * t * 1.5,
                    }, color(hue + 0.5, 0.9));
                }
            }
        },
        .text => {
            const word = "SLUGHORN";
            const size = unit * 0.16;
            const w = geometry.textWidth(word, size);
            const y = cy + unit * 0.3 * @sin(t * 1.4);
            for (word, 0..) |ch, i| {
                const g = table.glyph(ch) orelse continue;
                const fi: f32 = @floatFromInt(i);
                try batch.addShape(gpa, g, .{
                    .x = cx - w / 2 + fi * size * shapes.glyph_advance,
                    .y = y + size * 0.25 * @sin(t * 4 + fi * 0.7) - size * 0.375,
                    .size = size,
                }, color(hue + fi * 0.06, 1));
            }
        },
        .spiral => {
            if (table.get(.spiral)) |s| try batch.addShape(gpa, s, .{ .x = cx, .y = cy, .size = unit * 0.9, .angle = -t * 1.6 }, color(hue, 1));
        },
    }
}

fn color(hue: f32, alpha: f32) [4]f32 {
    const rgb = geometry.hsv(hue, 0.85, 1);
    return .{ rgb[0], rgb[1], rgb[2], alpha };
}

pub const HudInfo = struct {
    fps: f64,
    frame_ms: f64,
    state: *const controls.State,
};

/// Appends the HUD (top-left status panel, optional centred help panel) for a
/// `width` x `height` pixel viewport.
pub fn buildHud(batch: *Batch, gpa: std.mem.Allocator, table: ShapeTable, info: HudInfo, width: f32, height: f32) !void {
    const s = info.state;
    var buf: [512]u8 = undefined;
    const p = s.plane;
    const text = std.fmt.bufPrint(&buf,
        \\FPS {d:.1}  {d:.2} MS
        \\TAIL {d:.3}  {d:.0} FRAMES
        \\HUE {s}{d:.3}
        \\ZOOM {d:.3}  ROLL {s}{d:.1}
        \\YAW {s}{d:.1}  PITCH {s}{d:.1}
        \\SEED {s}{s}  F1 HELP
    , .{
        info.fps,                      info.frame_ms,
        s.params.tail,                 s.params.tailFrames(),
        sign(s.params.hue_shift),      @abs(s.params.hue_shift),
        p.zoom,                        sign(p.roll),
        @abs(std.math.radiansToDegrees(p.roll)), sign(p.yaw),
        @abs(std.math.radiansToDegrees(p.yaw)), sign(p.pitch),
        @abs(std.math.radiansToDegrees(p.pitch)), s.seed.label(),
        if (s.paused) "  PAUSED" else "",
    }) catch unreachable;
    try panel(batch, gpa, table, text, hud_margin, height - hud_margin);

    if (s.show_help) {
        const w = geometry.textWidth(help_text, hud_text_size);
        const lines: f32 = @floatFromInt(std.mem.count(u8, help_text, "\n") + 1);
        const h = lines * hud_text_size * geometry.line_height;
        try panel(batch, gpa, table, help_text, (width - w) / 2, (height + h) / 2);
    }
}

fn sign(x: f32) []const u8 {
    return if (x < 0) "-" else "+";
}

/// Text on a translucent box whose top-left corner is at (x, top).
fn panel(batch: *Batch, gpa: std.mem.Allocator, table: ShapeTable, text: []const u8, x: f32, top: f32) !void {
    const size = hud_text_size;
    const lines: f32 = @floatFromInt(std.mem.count(u8, text, "\n") + 1);
    const pad = size * 0.5;
    const h = lines * size * geometry.line_height;
    const w = geometry.textWidth(text, size);
    if (table.get(.box)) |b| {
        try batch.addShape(gpa, b, .{
            .x = x - pad,
            .y = top - h - pad,
            .size = 1,
            .stretch = .{ w + 2 * pad, h + 2 * pad },
        }, hud_panel);
    }
    _ = try batch.addText(gpa, table, text, x, top - size, size, hud_color);
}

fn testTable() !ShapeTable {
    const slughorn = @import("slughorn.zig");
    var atlas = try slughorn.Atlas.init();
    defer atlas.deinit();
    try shapes.registerAll(atlas);
    try atlas.build();
    return ShapeTable.load(atlas);
}

test "every seed except none emits geometry inside a generous viewport" {
    const gpa = std.testing.allocator;
    const table = try testTable();
    var batch: Batch = .{};
    defer batch.deinit(gpa);
    for (std.enums.values(controls.Seed)) |seed| {
        batch.clear();
        try buildSeed(&batch, gpa, table, seed, 1.7, 400, 300, 300);
        if (seed == .none) {
            try std.testing.expectEqual(@as(usize, 0), batch.vertices.items.len);
            continue;
        }
        try std.testing.expect(batch.vertices.items.len >= 6);
        for (batch.vertices.items) |v| {
            try std.testing.expect(v.pos[0] > 0 and v.pos[0] < 800);
            try std.testing.expect(v.pos[1] > 0 and v.pos[1] < 600);
        }
    }
}

test "hud shows fps and grows with help" {
    const gpa = std.testing.allocator;
    const table = try testTable();
    var state: controls.State = .{};
    var batch: Batch = .{};
    defer batch.deinit(gpa);
    try buildHud(&batch, gpa, table, .{ .fps = 59.94, .frame_ms = 16.68, .state = &state }, 1280, 800);
    const base = batch.vertices.items.len;
    try std.testing.expect(base > 6 * 20);
    // Top-left panel stays in the top-left quadrant.
    for (batch.vertices.items) |v| try std.testing.expect(v.pos[0] < 640 and v.pos[1] > 400);

    state.show_help = true;
    batch.clear();
    try buildHud(&batch, gpa, table, .{ .fps = 0, .frame_ms = 0, .state = &state }, 1280, 800);
    try std.testing.expect(batch.vertices.items.len > base * 2);
}
