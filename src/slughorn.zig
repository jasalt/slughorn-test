//! Zig wrapper over the slughorn C shim (src/c/slughorn_c.h).
const std = @import("std");
const c = @import("slughorn_c");

pub const Error = error{ OutOfMemory, SlughornFailure };

pub const TextureFormat = enum(u32) {
    rgba32f = c.SH_FORMAT_RGBA32F,
    rgba16f = c.SH_FORMAT_RGBA16F,
    rgba16ui = c.SH_FORMAT_RGBA16UI,
    rg16ui = c.SH_FORMAT_RG16UI,
    _,
};

pub const Texture = struct {
    bytes: []const u8,
    width: u32,
    height: u32,
    format: TextureFormat,
};

/// Packed per-shape data needed by the Slug shader (see slughorn::Atlas::Shape).
pub const Shape = struct {
    band_tex: [2]u32,
    band_max: [2]u32,
    band_scale: [2]f32,
    band_offset: [2]f32,
    bearing_x: f32,
    bearing_y: f32,
    width: f32,
    height: f32,
    advance: f32,
};

pub const Atlas = struct {
    handle: *c.sh_atlas,

    pub fn init() Error!Atlas {
        return .{ .handle = c.sh_atlas_create() orelse return error.OutOfMemory };
    }

    pub fn deinit(self: *Atlas) void {
        c.sh_atlas_destroy(self.handle);
        self.* = undefined;
    }

    pub fn lastError(self: Atlas) []const u8 {
        return std.mem.span(c.sh_last_error(self.handle));
    }

    pub fn beginShape(self: Atlas) void {
        c.sh_begin_shape(self.handle);
    }

    pub fn moveTo(self: Atlas, x: f32, y: f32) void {
        c.sh_move_to(self.handle, x, y);
    }

    pub fn lineTo(self: Atlas, x: f32, y: f32) void {
        c.sh_line_to(self.handle, x, y);
    }

    pub fn quadTo(self: Atlas, cx: f32, cy: f32, x: f32, y: f32) void {
        c.sh_quad_to(self.handle, cx, cy, x, y);
    }

    pub fn cubicTo(self: Atlas, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x: f32, y: f32) void {
        c.sh_cubic_to(self.handle, c1x, c1y, c2x, c2y, x, y);
    }

    pub fn close(self: Atlas) void {
        c.sh_close(self.handle);
    }

    pub fn pendingCurveCount(self: Atlas) usize {
        return c.sh_pending_curve_count(self.handle);
    }

    pub fn endShape(self: Atlas, key: u32) Error!void {
        if (c.sh_end_shape(self.handle, key) != 0) return error.SlughornFailure;
    }

    pub fn build(self: Atlas) Error!void {
        if (c.sh_build(self.handle) != 0) return error.SlughornFailure;
    }

    pub fn curveTexture(self: Atlas) Texture {
        var t: c.sh_texture = undefined;
        c.sh_curve_texture(self.handle, &t);
        return toTexture(t);
    }

    pub fn bandTexture(self: Atlas) Texture {
        var t: c.sh_texture = undefined;
        c.sh_band_texture(self.handle, &t);
        return toTexture(t);
    }

    pub fn shape(self: Atlas, key: u32) ?Shape {
        var s: c.sh_shape = undefined;
        if (c.sh_get_shape(self.handle, key, &s) == 0) return null;
        return .{
            .band_tex = .{ s.band_tex_x, s.band_tex_y },
            .band_max = .{ s.band_max_x, s.band_max_y },
            .band_scale = .{ s.band_scale_x, s.band_scale_y },
            .band_offset = .{ s.band_offset_x, s.band_offset_y },
            .bearing_x = s.bearing_x,
            .bearing_y = s.bearing_y,
            .width = s.width,
            .height = s.height,
            .advance = s.advance,
        };
    }

    fn toTexture(t: c.sh_texture) Texture {
        const bytes: [*]const u8 = if (t.bytes) |p| @ptrCast(p) else &.{};
        return .{
            .bytes = bytes[0..t.size],
            .width = t.width,
            .height = t.height,
            .format = @enumFromInt(t.format),
        };
    }
};

test "atlas packs a square into Slug textures" {
    var atlas = try Atlas.init();
    defer atlas.deinit();

    atlas.beginShape();
    atlas.moveTo(0, 0);
    atlas.lineTo(1, 0);
    atlas.lineTo(1, 1);
    atlas.lineTo(0, 1);
    atlas.close();
    try std.testing.expectEqual(@as(usize, 4), atlas.pendingCurveCount());
    try atlas.endShape(42);
    try atlas.build();

    const s = atlas.shape(42) orelse return error.TestUnexpectedResult;
    try std.testing.expectApproxEqAbs(@as(f32, 1), s.width, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), s.height, 1e-5);
    try std.testing.expect(atlas.shape(43) == null);

    const curves = atlas.curveTexture();
    try std.testing.expectEqual(TextureFormat.rgba32f, curves.format);
    try std.testing.expectEqual(@as(usize, curves.width) * curves.height * 16, curves.bytes.len);

    const bands = atlas.bandTexture();
    try std.testing.expectEqual(TextureFormat.rg16ui, bands.format);
    try std.testing.expect(bands.bytes.len > 0);
}

test "non-finite coordinates are reported, not thrown across the ABI" {
    var atlas = try Atlas.init();
    defer atlas.deinit();

    atlas.beginShape();
    atlas.moveTo(0, 0);
    atlas.lineTo(std.math.nan(f32), 1);
    try std.testing.expect(atlas.lastError().len > 0);
}
