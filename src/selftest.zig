//! On-device validation run by `--selftest` (native) and `?selftest` (web). It drives the
//! real renderer and reads framebuffers back, so it needs a live GL/WebGL context.
//!
//! `platform` provides:
//!   frame() app.Frame          current time, drawable size, input
//!   present() void             show the rendered frame (swap, pump events)
//!   resize(w: u32, h: u32) void request a new drawable size
const std = @import("std");
const App = @import("app.zig").App;

pub fn run(app: *App, platform: anytype) !void {
    try step(app, platform);
    const w = app.size[0];
    const h = app.size[1];
    const buf = try app.gpa.alloc(u8, @as(usize, w) * h * 4);
    defer app.gpa.free(buf);
    var failures: u32 = 0;

    // Read the window before presenting: after a swap its contents are undefined.
    try app.render(platform.frame());
    app.renderer.readPixels(.screen, w, h, buf);
    platform.present();
    const screen_lit = litFraction(buf, w, 0, 0, w, h, 16);
    // HUD panel sits in the top-left corner (GL rows are bottom-up).
    const hud_lit = litFraction(buf, w, 16, h - 60, 200, 40, 200);
    failures += check("screen has rendered content", screen_lit > 0.02, screen_lit);
    failures += check("HUD text is drawn", hud_lit > 0.02, hud_lit);
    failures += check("FPS was measured", app.counter.average > 0, app.counter.average);

    app.renderer.readPixels(.feedback, w, h, buf);
    const seeded = litFraction(buf, w, 0, 0, w, h, 8);

    // Remove the seed: whatever remains must come from the feedback loop alone.
    app.state.seed = .none;
    app.state.show_hud = false;
    try step(app, platform);
    app.renderer.readPixels(.feedback, w, h, buf);
    const echoed = litFraction(buf, w, 0, 0, w, h, 8);
    failures += check("feedback persists without a seed", echoed > seeded * 0.5 and echoed > 0.01, echoed);

    // Moving the picture plane must move the echo.
    const before = try app.gpa.dupe(u8, buf);
    defer app.gpa.free(before);
    app.state.plane.pan(0.5, 0);
    try step(app, platform);
    app.renderer.readPixels(.feedback, w, h, buf);
    var changed: usize = 0;
    for (0..buf.len / 4) |i| {
        if (@abs(@as(i16, buf[i * 4]) - before[i * 4]) > 8) changed += 1;
    }
    const moved = @as(f64, @floatFromInt(changed)) / @as(f64, @floatFromInt(@as(usize, w) * h));
    failures += check("panning the plane moves the image", moved > 0.005, moved);

    app.state.params.tail = 0;
    try step(app, platform);
    try step(app, platform);
    app.renderer.readPixels(.feedback, w, h, buf);
    const extinguished = litFraction(buf, w, 0, 0, w, h, 2);
    failures += check("zero tail clears the loop", extinguished < 0.001, extinguished);

    // Resizing must rebuild the feedback buffers and keep rendering.
    platform.resize(w / 2, h / 2);
    app.state.params = .{};
    app.state.seed = .stars;
    for (0..20) |_| try step(app, platform);
    const rs = app.size;
    app.renderer.readPixels(.feedback, rs[0], rs[1], buf);
    const resized_lit = litFraction(buf, rs[0], 0, 0, rs[0], rs[1], 16);
    failures += check("resize rebuilds the feedback buffers", rs[0] == w / 2 and app.renderer.size[0] == w / 2 and resized_lit > 0.02, resized_lit);

    if (failures > 0) {
        std.log.err("selftest: {d} check(s) failed", .{failures});
        return error.SelftestFailed;
    }
    std.log.info("selftest: all checks passed ({d}x{d}, {d:.1} fps)", .{ w, h, app.counter.average });
}

fn step(app: *App, platform: anytype) !void {
    try app.render(platform.frame());
    platform.present();
}

/// Fraction of pixels in the (x0, y0, w, h) region whose brightest channel exceeds `threshold`.
fn litFraction(rgba: []const u8, stride: u32, x0: u32, y0: u32, w: u32, h: u32, threshold: u8) f64 {
    var lit: usize = 0;
    for (y0..y0 + h) |y| {
        for (x0..x0 + w) |x| {
            const p = rgba[(y * stride + x) * 4 ..][0..3];
            if (@max(p[0], p[1], p[2]) > threshold) lit += 1;
        }
    }
    return @as(f64, @floatFromInt(lit)) / @as(f64, @floatFromInt(@as(usize, w) * h));
}

fn check(name: []const u8, ok: bool, value: anytype) u32 {
    if (ok) {
        std.log.info("PASS {s} ({d:.4})", .{ name, value });
        return 0;
    }
    std.log.err("FAIL {s} ({d:.4})", .{ name, value });
    return 1;
}
