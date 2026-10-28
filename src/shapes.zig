//! Procedural vector content authored as quadratic/cubic paths and packed by slughorn.
//!
//! Every function takes a generic `sink` with moveTo/lineTo/quadTo/cubicTo/close
//! (slughorn.Atlas, or `Bounds` in tests). Outer contours wind counter-clockwise and
//! holes clockwise.
const std = @import("std");

/// Atlas keys for non-glyph shapes; glyphs use their ASCII codepoint.
pub const Key = enum(u32) {
    star = 0x10000,
    ring,
    heart,
    flower,
    spiral,
    /// Unit square, used for HUD panels.
    box,
};

/// Monospace advance of the stroke font, in em.
pub const glyph_advance: f32 = 0.625;
/// Stroke font grid cell (glyph grid is 4 x 6 cells; cap height = 0.75 em).
const grid: f32 = 0.125;
const stroke_half: f32 = 0.055;

// Kappa for approximating a quarter circle with one cubic.
const kappa: f32 = 0.5522847498;

pub fn star(sink: anytype, points: u32, outer: f32, inner: f32) void {
    const n = points * 2;
    for (0..n) |i| {
        const a = std.math.pi / 2.0 + @as(f32, @floatFromInt(i)) * std.math.pi / @as(f32, @floatFromInt(points));
        const r = if (i % 2 == 0) outer else inner;
        const x = r * @cos(a);
        const y = r * @sin(a);
        if (i == 0) sink.moveTo(x, y) else sink.lineTo(x, y);
    }
    sink.close();
}

/// Circle of radius r around (cx, cy); `ccw` selects winding.
pub fn circle(sink: anytype, cx: f32, cy: f32, r: f32, ccw: bool) void {
    const k = r * kappa;
    const s: f32 = if (ccw) 1 else -1;
    sink.moveTo(cx + r, cy);
    sink.cubicTo(cx + r, cy + s * k, cx + k, cy + s * r, cx, cy + s * r);
    sink.cubicTo(cx - k, cy + s * r, cx - r, cy + s * k, cx - r, cy);
    sink.cubicTo(cx - r, cy - s * k, cx - k, cy - s * r, cx, cy - s * r);
    sink.cubicTo(cx + k, cy - s * r, cx + r, cy - s * k, cx + r, cy);
    sink.close();
}

pub fn ring(sink: anytype, outer: f32, inner: f32) void {
    circle(sink, 0, 0, outer, true);
    circle(sink, 0, 0, inner, false);
}

pub fn heart(sink: anytype) void {
    sink.moveTo(0, -0.45);
    sink.cubicTo(0.25, -0.2, 0.5, -0.05, 0.5, 0.2);
    sink.cubicTo(0.5, 0.42, 0.2, 0.5, 0, 0.28);
    sink.cubicTo(-0.2, 0.5, -0.5, 0.42, -0.5, 0.2);
    sink.cubicTo(-0.5, -0.05, -0.25, -0.2, 0, -0.45);
    sink.close();
}

/// Petals built from quadratic curves bulging out between rim points.
pub fn flower(sink: anytype, petals: u32) void {
    const step = 2.0 * std.math.pi / @as(f32, @floatFromInt(petals));
    const r: f32 = 0.18;
    sink.moveTo(r, 0);
    for (0..petals) |i| {
        const a0 = @as(f32, @floatFromInt(i)) * step;
        const a1 = a0 + step;
        const am = (a0 + a1) / 2;
        sink.quadTo(1.1 * @cos(am), 1.1 * @sin(am), r * @cos(a1), r * @sin(a1));
    }
    sink.close();
    circle(sink, 0, 0, 0.1, false);
}

/// A thick Archimedean spiral band, outer edge out and inner edge back.
pub fn spiral(sink: anytype, turns: f32) void {
    const segments: u32 = 96;
    const width: f32 = 0.06;
    const total = turns * 2.0 * std.math.pi;
    const k = 0.45 / total;
    for (0..segments + 1) |i| {
        const a = total * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments));
        const r = 0.04 + k * a + width / 2;
        if (i == 0) sink.moveTo(r * @cos(a), r * @sin(a)) else sink.lineTo(r * @cos(a), r * @sin(a));
    }
    var i: u32 = segments + 1;
    while (i > 0) {
        i -= 1;
        const a = total * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments));
        const r = 0.04 + k * a - width / 2;
        sink.lineTo(r * @cos(a), r * @sin(a));
    }
    sink.close();
}

/// Stroke-font polylines on a 4x6 grid: ';' separates strokes, ' ' separates points.
pub fn glyphStrokes(ch: u8) ?[]const u8 {
    return switch (std.ascii.toUpper(ch)) {
        '0' => "0,0 4,0 4,6 0,6 0,0;0,0 4,6",
        '1' => "1,5 2,6 2,0;1,0 3,0",
        '2' => "0,6 4,6 4,3 0,3 0,0 4,0",
        '3' => "0,6 4,6 4,0 0,0;1,3 4,3",
        '4' => "0,6 0,3 4,3;4,6 4,0",
        '5', 'S' => "4,6 0,6 0,3 4,3 4,0 0,0",
        '6' => "4,6 0,6 0,0 4,0 4,3 0,3",
        '7' => "0,6 4,6 2,0",
        '8' => "0,0 4,0 4,6 0,6 0,0;0,3 4,3",
        '9' => "4,3 0,3 0,6 4,6 4,0 0,0",
        'A' => "0,0 0,4 2,6 4,4 4,0;0,3 4,3",
        'B' => "0,0 0,6 3,6 4,5 4,4 3,3 0,3;3,3 4,2 4,1 3,0 0,0",
        'C' => "4,6 0,6 0,0 4,0",
        'D' => "0,0 0,6 2,6 4,4 4,2 2,0 0,0",
        'E' => "4,6 0,6 0,0 4,0;0,3 3,3",
        'F' => "4,6 0,6 0,0;0,3 3,3",
        'G' => "4,6 0,6 0,0 4,0 4,3 2,3",
        'H' => "0,0 0,6;4,0 4,6;0,3 4,3",
        'I' => "1,6 3,6;2,6 2,0;1,0 3,0",
        'J' => "4,6 4,0 0,0 0,2",
        'K' => "0,0 0,6;4,6 0,3 4,0",
        'L' => "0,6 0,0 4,0",
        'M' => "0,0 0,6 2,3 4,6 4,0",
        'N' => "0,0 0,6 4,0 4,6",
        'O' => "0,0 4,0 4,6 0,6 0,0",
        'P' => "0,0 0,6 4,6 4,3 0,3",
        'Q' => "0,0 4,0 4,6 0,6 0,0;2,2 4,0",
        'R' => "0,0 0,6 4,6 4,3 0,3 4,0",
        'T' => "0,6 4,6;2,6 2,0",
        'U' => "0,6 0,0 4,0 4,6",
        'V' => "0,6 2,0 4,6",
        'W' => "0,6 1,0 2,3 3,0 4,6",
        'X' => "0,0 4,6;0,6 4,0",
        'Y' => "0,6 2,3 4,6;2,3 2,0",
        'Z' => "0,6 4,6 0,0 4,0",
        '.' => "2,0",
        ',' => "2,1 1,-1",
        ':' => "2,1;2,5",
        '-' => "1,3 3,3",
        '+' => "0,3 4,3;2,1 2,5",
        '=' => "0,2 4,2;0,4 4,4",
        '/' => "0,0 4,6",
        '%' => "0,0 4,6;0,6;4,0",
        '[' => "3,6 1,6 1,0 3,0",
        ']' => "1,6 3,6 3,0 1,0",
        '<' => "4,6 0,3 4,0",
        '>' => "0,6 4,3 0,0",
        '(' => "3,6 1,4 1,2 3,0",
        ')' => "1,6 3,4 3,2 1,0",
        else => null,
    };
}

/// Emits a glyph as one CCW rectangle per stroke segment (a lone point becomes a square).
/// Overlapping same-winding contours union cleanly under Slug's coverage.
pub fn glyph(sink: anytype, ch: u8) bool {
    const spec = glyphStrokes(ch) orelse return false;
    var strokes = std.mem.splitScalar(u8, spec, ';');
    while (strokes.next()) |stroke| {
        var pts = std.mem.tokenizeScalar(u8, stroke, ' ');
        var prev: ?[2]f32 = null;
        var count: usize = 0;
        while (pts.next()) |pt| : (count += 1) {
            const p = parsePoint(pt);
            if (prev) |q| segment(sink, q, p);
            prev = p;
        }
        if (count == 1) segment(sink, prev.?, prev.?);
    }
    return true;
}

fn parsePoint(s: []const u8) [2]f32 {
    const comma = std.mem.indexOfScalar(u8, s, ',').?;
    const x = std.fmt.parseFloat(f32, s[0..comma]) catch unreachable;
    const y = std.fmt.parseFloat(f32, s[comma + 1 ..]) catch unreachable;
    return .{ x * grid, y * grid };
}

fn segment(sink: anytype, a: [2]f32, b: [2]f32) void {
    var dx = b[0] - a[0];
    var dy = b[1] - a[1];
    const len = @sqrt(dx * dx + dy * dy);
    if (len < 1e-6) {
        dx = 1;
        dy = 0;
    } else {
        dx /= len;
        dy /= len;
    }
    const h = stroke_half;
    // Normal to the left of the direction, so a->b->c->d below is counter-clockwise.
    const nx = -dy * h;
    const ny = dx * h;
    const ex = dx * h;
    const ey = dy * h;
    sink.moveTo(a[0] - ex - nx, a[1] - ey - ny);
    sink.lineTo(b[0] + ex - nx, b[1] + ey - ny);
    sink.lineTo(b[0] + ex + nx, b[1] + ey + ny);
    sink.lineTo(a[0] - ex + nx, a[1] - ey + ny);
    sink.close();
}

/// Registers every shape and glyph in `atlas` (anything with the sink API plus
/// beginShape/endShape(key)).
pub fn registerAll(atlas: anytype) !void {
    atlas.beginShape();
    star(atlas, 5, 0.5, 0.2);
    try atlas.endShape(@intFromEnum(Key.star));

    atlas.beginShape();
    ring(atlas, 0.5, 0.38);
    try atlas.endShape(@intFromEnum(Key.ring));

    atlas.beginShape();
    heart(atlas);
    try atlas.endShape(@intFromEnum(Key.heart));

    atlas.beginShape();
    flower(atlas, 7);
    try atlas.endShape(@intFromEnum(Key.flower));

    atlas.beginShape();
    spiral(atlas, 3);
    try atlas.endShape(@intFromEnum(Key.spiral));

    atlas.beginShape();
    atlas.moveTo(0, 0);
    atlas.lineTo(1, 0);
    atlas.lineTo(1, 1);
    atlas.lineTo(0, 1);
    atlas.close();
    try atlas.endShape(@intFromEnum(Key.box));

    for (0..128) |ch| {
        atlas.beginShape();
        if (glyph(atlas, @intCast(ch))) try atlas.endShape(@intCast(ch));
    }
}

/// Test sink: accumulates bounds and signed area (shoelace over curve endpoints).
pub const Bounds = struct {
    min: [2]f32 = .{ std.math.inf(f32), std.math.inf(f32) },
    max: [2]f32 = .{ -std.math.inf(f32), -std.math.inf(f32) },
    cur: [2]f32 = .{ 0, 0 },
    start: [2]f32 = .{ 0, 0 },
    area2: f32 = 0,
    contours: usize = 0,
    curves: usize = 0,

    fn add(self: *Bounds, x: f32, y: f32) void {
        self.min = .{ @min(self.min[0], x), @min(self.min[1], y) };
        self.max = .{ @max(self.max[0], x), @max(self.max[1], y) };
    }

    fn edge(self: *Bounds, x: f32, y: f32) void {
        self.area2 += self.cur[0] * y - x * self.cur[1];
        self.cur = .{ x, y };
        self.add(x, y);
        self.curves += 1;
    }

    pub fn moveTo(self: *Bounds, x: f32, y: f32) void {
        self.cur = .{ x, y };
        self.start = .{ x, y };
        self.add(x, y);
        self.contours += 1;
    }
    pub fn lineTo(self: *Bounds, x: f32, y: f32) void {
        self.edge(x, y);
    }
    pub fn quadTo(self: *Bounds, cx: f32, cy: f32, x: f32, y: f32) void {
        self.add(cx, cy);
        self.edge(x, y);
    }
    pub fn cubicTo(self: *Bounds, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x: f32, y: f32) void {
        self.add(c1x, c1y);
        self.add(c2x, c2y);
        self.edge(x, y);
    }
    pub fn close(self: *Bounds) void {
        if (self.cur[0] != self.start[0] or self.cur[1] != self.start[1]) self.edge(self.start[0], self.start[1]);
    }
};

test "star is centred and counter-clockwise" {
    var b: Bounds = .{};
    star(&b, 5, 0.5, 0.2);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), b.max[1], 1e-5);
    try std.testing.expectEqual(@as(usize, 10), b.curves);
    try std.testing.expect(b.area2 > 0);
}

test "ring hole cancels part of the outer area" {
    var outer: Bounds = .{};
    circle(&outer, 0, 0, 0.5, true);
    var r: Bounds = .{};
    ring(&r, 0.5, 0.38);
    try std.testing.expectEqual(@as(usize, 2), r.contours);
    try std.testing.expect(r.area2 > 0 and r.area2 < outer.area2);
}

test "every glyph stroke is counter-clockwise and inside the cell" {
    for (0..128) |ch| {
        var b: Bounds = .{};
        if (!glyph(&b, @intCast(ch))) continue;
        try std.testing.expect(b.contours > 0);
        try std.testing.expect(b.min[0] >= -std.math.sqrt2 * stroke_half - 1e-4);
        try std.testing.expect(b.max[0] <= 4 * grid + std.math.sqrt2 * stroke_half + 1e-4);
        try std.testing.expect(b.area2 > 0);
    }
}

test "glyph lookup is case-insensitive and rejects unknown characters" {
    try std.testing.expect(glyphStrokes('a') != null);
    try std.testing.expectEqualStrings(glyphStrokes('a').?, glyphStrokes('A').?);
    try std.testing.expect(glyphStrokes('~') == null);
    try std.testing.expect(glyphStrokes(' ') == null);
}
