//! Minimal column-major 4x4 matrix math (matches GLSL mat4 layout).
const std = @import("std");

pub const Mat4 = struct {
    m: [16]f32,

    pub const identity: Mat4 = .{ .m = .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    } };

    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var out: Mat4 = undefined;
        for (0..4) |c| {
            for (0..4) |r| {
                var sum: f32 = 0;
                for (0..4) |k| sum += a.m[k * 4 + r] * b.m[c * 4 + k];
                out.m[c * 4 + r] = sum;
            }
        }
        return out;
    }

    pub fn translate(x: f32, y: f32, z: f32) Mat4 {
        var out = identity;
        out.m[12] = x;
        out.m[13] = y;
        out.m[14] = z;
        return out;
    }

    pub fn scale(x: f32, y: f32, z: f32) Mat4 {
        var out = identity;
        out.m[0] = x;
        out.m[5] = y;
        out.m[10] = z;
        return out;
    }

    pub fn rotateX(a: f32) Mat4 {
        const c = @cos(a);
        const s = @sin(a);
        var out = identity;
        out.m[5] = c;
        out.m[6] = s;
        out.m[9] = -s;
        out.m[10] = c;
        return out;
    }

    pub fn rotateY(a: f32) Mat4 {
        const c = @cos(a);
        const s = @sin(a);
        var out = identity;
        out.m[0] = c;
        out.m[2] = -s;
        out.m[8] = s;
        out.m[10] = c;
        return out;
    }

    pub fn rotateZ(a: f32) Mat4 {
        const c = @cos(a);
        const s = @sin(a);
        var out = identity;
        out.m[0] = c;
        out.m[1] = s;
        out.m[4] = -s;
        out.m[5] = c;
        return out;
    }

    pub fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const f = 1.0 / @tan(fovy * 0.5);
        var out: Mat4 = .{ .m = @splat(0) };
        out.m[0] = f / aspect;
        out.m[5] = f;
        out.m[10] = (far + near) / (near - far);
        out.m[11] = -1;
        out.m[14] = (2 * far * near) / (near - far);
        return out;
    }

    pub fn ortho(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Mat4 {
        var out: Mat4 = .{ .m = @splat(0) };
        out.m[0] = 2 / (right - left);
        out.m[5] = 2 / (top - bottom);
        out.m[10] = -2 / (far - near);
        out.m[12] = -(right + left) / (right - left);
        out.m[13] = -(top + bottom) / (top - bottom);
        out.m[14] = -(far + near) / (far - near);
        out.m[15] = 1;
        return out;
    }

    /// Transforms a point (w = 1) and performs the perspective divide.
    pub fn project(a: Mat4, p: [3]f32) [3]f32 {
        var v: [4]f32 = undefined;
        for (0..4) |r| {
            v[r] = a.m[r] * p[0] + a.m[4 + r] * p[1] + a.m[8 + r] * p[2] + a.m[12 + r];
        }
        return .{ v[0] / v[3], v[1] / v[3], v[2] / v[3] };
    }
};

fn expectVec(expected: [3]f32, actual: [3]f32) !void {
    for (0..3) |i| try std.testing.expectApproxEqAbs(expected[i], actual[i], 1e-5);
}

test "identity multiply is a no-op" {
    const t = Mat4.translate(1, 2, 3);
    try std.testing.expectEqualSlices(f32, &t.m, &Mat4.identity.mul(t).m);
    try std.testing.expectEqualSlices(f32, &t.m, &t.mul(Mat4.identity).m);
}

test "rotateZ quarter turn maps x to y" {
    try expectVec(.{ 0, 1, 0 }, Mat4.rotateZ(std.math.pi / 2.0).project(.{ 1, 0, 0 }));
}

test "ortho maps corners to NDC" {
    const o = Mat4.ortho(0, 800, 0, 600, -1, 1);
    try expectVec(.{ -1, -1, 0 }, o.project(.{ 0, 0, 0 }));
    try expectVec(.{ 1, 1, 0 }, o.project(.{ 800, 600, 0 }));
}
