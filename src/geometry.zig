//! Builds the vertex stream for Slug-rendered quads: each placed shape becomes two
//! triangles carrying em-space coordinates and the band lookup data the shader needs.
const std = @import("std");
const slughorn = @import("slughorn.zig");
const shapes = @import("shapes.zig");

pub const Shape = slughorn.Shape;

pub const Vertex = extern struct {
    pos: [2]f32,
    color: [4]f32,
    em: [2]f32,
    /// bandScaleX/Y, bandOffsetX/Y
    band_transform: [4]f32,
    /// bandTexX/Y, bandMaxX/Y
    shape_data: [4]f32,
};

/// Screen pixels the quad is grown by so antialiased edges are not clipped.
pub const aa_pad_px: f32 = 1.5;

/// Where and how large to draw a shape: em-space (0, 0) lands on (x, y) pixels,
/// one em spans `size` pixels, rotated by `angle` radians counter-clockwise.
pub const Placement = struct {
    x: f32,
    y: f32,
    size: f32,
    angle: f32 = 0,
    /// Non-uniform stretch applied before rotation (HUD panels).
    stretch: [2]f32 = .{ 1, 1 },
};

/// Shape metrics for every atlas key we use, captured once after build().
pub const ShapeTable = struct {
    glyphs: [128]?Shape = @splat(null),
    named: [std.enums.values(shapes.Key).len]?Shape = @splat(null),

    pub fn load(atlas: slughorn.Atlas) ShapeTable {
        var t: ShapeTable = .{};
        for (&t.glyphs, 0..) |*g, ch| g.* = atlas.shape(@intCast(ch));
        for (std.enums.values(shapes.Key), 0..) |k, i| t.named[i] = atlas.shape(@intFromEnum(k));
        return t;
    }

    pub fn get(self: ShapeTable, key: shapes.Key) ?Shape {
        return self.named[@intFromEnum(key) - @intFromEnum(shapes.Key.star)];
    }

    pub fn glyph(self: ShapeTable, ch: u8) ?Shape {
        return if (ch < 128) self.glyphs[std.ascii.toUpper(ch)] else null;
    }
};

pub const Batch = struct {
    vertices: std.ArrayList(Vertex) = .empty,

    pub fn deinit(self: *Batch, gpa: std.mem.Allocator) void {
        self.vertices.deinit(gpa);
    }

    pub fn clear(self: *Batch) void {
        self.vertices.clearRetainingCapacity();
    }

    pub fn addShape(self: *Batch, gpa: std.mem.Allocator, shape: Shape, p: Placement, color: [4]f32) !void {
        const sx = p.size * p.stretch[0];
        const sy = p.size * p.stretch[1];
        const pad_x = aa_pad_px / sx;
        const pad_y = aa_pad_px / sy;
        const e0 = [2]f32{ shape.bearing_x - pad_x, shape.bearing_y - shape.height - pad_y };
        const e1 = [2]f32{ shape.bearing_x + shape.width + pad_x, shape.bearing_y + pad_y };
        const corners = [4][2]f32{ e0, .{ e1[0], e0[1] }, e1, .{ e0[0], e1[1] } };

        const c = @cos(p.angle);
        const s = @sin(p.angle);
        var verts: [4]Vertex = undefined;
        for (corners, &verts) |em, *v| {
            const lx = em[0] * sx;
            const ly = em[1] * sy;
            v.* = .{
                .pos = .{ p.x + lx * c - ly * s, p.y + lx * s + ly * c },
                .color = color,
                .em = em,
                .band_transform = .{ shape.band_scale[0], shape.band_scale[1], shape.band_offset[0], shape.band_offset[1] },
                .shape_data = .{
                    @floatFromInt(shape.band_tex[0]), @floatFromInt(shape.band_tex[1]),
                    @floatFromInt(shape.band_max[0]), @floatFromInt(shape.band_max[1]),
                },
            };
        }
        try self.vertices.appendSlice(gpa, &.{ verts[0], verts[1], verts[2], verts[0], verts[2], verts[3] });
    }

    /// Lays out `text` in the monospace stroke font with the baseline-left at (x, y).
    /// '\n' starts a new line below. Returns the width in pixels of the longest line.
    pub fn addText(self: *Batch, gpa: std.mem.Allocator, table: ShapeTable, text: []const u8, x: f32, y: f32, size: f32, color: [4]f32) !f32 {
        var pen_x = x;
        var pen_y = y;
        var widest: f32 = 0;
        for (text) |ch| {
            if (ch == '\n') {
                pen_x = x;
                pen_y -= size * line_height;
                continue;
            }
            if (table.glyph(ch)) |g| try self.addShape(gpa, g, .{ .x = pen_x, .y = pen_y, .size = size }, color);
            pen_x += size * shapes.glyph_advance;
            widest = @max(widest, pen_x - x);
        }
        return widest;
    }
};

pub const line_height: f32 = 1.2;

pub fn textWidth(text: []const u8, size: f32) f32 {
    var widest: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |l| widest = @max(widest, l.len);
    return @as(f32, @floatFromInt(widest)) * size * shapes.glyph_advance;
}

/// HSV (all components 0..1) to RGB.
pub fn hsv(h: f32, s: f32, v: f32) [3]f32 {
    const hh = (h - @floor(h)) * 6;
    const i: u32 = @intFromFloat(@floor(hh));
    const f = hh - @floor(hh);
    const p = v * (1 - s);
    const q = v * (1 - s * f);
    const t = v * (1 - s * (1 - f));
    return switch (i) {
        0 => .{ v, t, p },
        1 => .{ q, v, p },
        2 => .{ p, v, t },
        3 => .{ p, q, v },
        4 => .{ t, p, v },
        else => .{ v, p, q },
    };
}

const test_shape: Shape = .{
    .band_tex = .{ 3, 4 },
    .band_max = .{ 1, 2 },
    .band_scale = .{ 8, 8 },
    .band_offset = .{ 0, 0 },
    .bearing_x = 0,
    .bearing_y = 1,
    .width = 1,
    .height = 1,
    .advance = 1,
};

test "shape quad covers the padded em box at the requested size" {
    const gpa = std.testing.allocator;
    var b: Batch = .{};
    defer b.deinit(gpa);
    try b.addShape(gpa, test_shape, .{ .x = 10, .y = 20, .size = 100 }, .{ 1, 1, 1, 1 });
    try std.testing.expectEqual(@as(usize, 6), b.vertices.items.len);
    const v0 = b.vertices.items[0];
    const v2 = b.vertices.items[2];
    try std.testing.expectApproxEqAbs(@as(f32, 10 - aa_pad_px), v0.pos[0], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 110 + aa_pad_px), v2.pos[0], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 120 + aa_pad_px), v2.pos[1], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, -aa_pad_px / 100), v0.em[0], 1e-6);
    try std.testing.expectEqual([4]f32{ 3, 4, 1, 2 }, v0.shape_data);
}

test "rotation pivots around the em origin" {
    const gpa = std.testing.allocator;
    var b: Batch = .{};
    defer b.deinit(gpa);
    try b.addShape(gpa, test_shape, .{ .x = 0, .y = 0, .size = 10, .angle = std.math.pi / 2.0 }, .{ 1, 1, 1, 1 });
    // em (1+pad, 0-pad) corner rotates to approximately (pad, 1+pad) * size.
    const v1 = b.vertices.items[1];
    try std.testing.expectApproxEqAbs(@as(f32, aa_pad_px), v1.pos[0], 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 10 + aa_pad_px), v1.pos[1], 1e-3);
}

test "text skips unknown glyphs but still advances" {
    const gpa = std.testing.allocator;
    var table: ShapeTable = .{};
    table.glyphs['A'] = test_shape;
    var b: Batch = .{};
    defer b.deinit(gpa);
    const w = try b.addText(gpa, table, "a A\nA", 0, 0, 10, .{ 1, 1, 1, 1 });
    try std.testing.expectEqual(@as(usize, 18), b.vertices.items.len);
    try std.testing.expectApproxEqAbs(3 * 10 * shapes.glyph_advance, w, 1e-4);
    try std.testing.expectApproxEqAbs(w, textWidth("a A\nA", 10), 1e-4);
    // Third glyph is on the second line.
    try std.testing.expect(b.vertices.items[12].pos[1] < b.vertices.items[0].pos[1]);
}

test "shape table resolves every named key from a built atlas" {
    var atlas = try slughorn.Atlas.init();
    defer atlas.deinit();
    try shapes.registerAll(atlas);
    try atlas.build();
    const t = ShapeTable.load(atlas);
    for (std.enums.values(shapes.Key)) |k| try std.testing.expect(t.get(k) != null);
    try std.testing.expect(t.glyph('f') != null);
    try std.testing.expect(t.glyph(' ') == null);
}

test "hsv primaries" {
    try std.testing.expectEqual([3]f32{ 1, 0, 0 }, hsv(0, 1, 1));
    try std.testing.expectEqual([3]f32{ 0, 0, 1 }, hsv(2.0 / 3.0, 1, 1));
}
