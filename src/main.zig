//! vector-feedback: a video-feedback device built on slughorn GPU vector graphics.
//!
//! The previous frame is shown on a picture plane in front of a virtual camera; moving
//! that plane (pan, roll, tilt, zoom) with the mouse or keyboard sculpts the recursive
//! image, while slughorn-rendered vector shapes keep feeding new light into the loop.
const std = @import("std");
const gl = @import("gl_c");
const slughorn = @import("slughorn.zig");
const shapes = @import("shapes.zig");
const geometry = @import("geometry.zig");
const controls = @import("controls.zig");
const scene = @import("scene.zig");
const fps = @import("fps.zig");
const feedback = @import("feedback.zig");
const Renderer = @import("renderer.zig").Renderer;

const usage =
    \\Usage: vector-feedback [options]
    \\
    \\  --width N          initial window width (default 1280)
    \\  --height N         initial window height (default 800)
    \\  --no-vsync         start with vsync off (uncapped FPS)
    \\  --seed NAME        initial seed: none, stars, rings, text, spiral (default stars)
    \\  --tail X           initial feedback gain per frame, 0..0.995 (default 0.94)
    \\  --show-help        start with the controls overlay visible
    \\  --frames N         quit after N frames
    \\  --screenshot FILE  write the last frame as a binary PPM on exit
    \\  --selftest         validate rendering and the feedback loop, exit non-zero on failure
    \\  --help             show this help
    \\
    \\Press F1 in the window for controls.
    \\
;

const Options = struct {
    width: u32 = 1280,
    height: u32 = 800,
    vsync: bool = true,
    frames: ?u64 = null,
    screenshot: ?[]const u8 = null,
    selftest: bool = false,
    help: bool = false,
    seed: controls.Seed = .stars,
    tail: ?f32 = null,
    show_help: bool = false,
};

fn parseOptions(args: []const [:0]const u8) !Options {
    var o: Options = .{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            o.help = true;
        } else if (std.mem.eql(u8, a, "--no-vsync")) {
            o.vsync = false;
        } else if (std.mem.eql(u8, a, "--selftest")) {
            o.selftest = true;
        } else if (std.mem.eql(u8, a, "--show-help")) {
            o.show_help = true;
        } else if (i + 1 < args.len and std.mem.eql(u8, a, "--seed")) {
            i += 1;
            o.seed = std.meta.stringToEnum(controls.Seed, args[i]) orelse return error.InvalidArguments;
        } else if (i + 1 < args.len and std.mem.eql(u8, a, "--tail")) {
            i += 1;
            o.tail = std.math.clamp(try std.fmt.parseFloat(f32, args[i]), feedback.min_tail, feedback.max_tail);
        } else if (i + 1 < args.len and std.mem.eql(u8, a, "--width")) {
            i += 1;
            o.width = try std.fmt.parseInt(u32, args[i], 10);
        } else if (i + 1 < args.len and std.mem.eql(u8, a, "--height")) {
            i += 1;
            o.height = try std.fmt.parseInt(u32, args[i], 10);
        } else if (i + 1 < args.len and std.mem.eql(u8, a, "--frames")) {
            i += 1;
            o.frames = try std.fmt.parseInt(u64, args[i], 10);
        } else if (i + 1 < args.len and std.mem.eql(u8, a, "--screenshot")) {
            i += 1;
            o.screenshot = args[i];
        } else {
            return error.InvalidArguments;
        }
    }
    if (o.selftest and o.frames == null) o.frames = 120;
    return o;
}

const App = struct {
    gpa: std.mem.Allocator,
    window: *gl.GLFWwindow,
    renderer: Renderer,
    table: geometry.ShapeTable,
    state: controls.State = .{},
    counter: fps.Counter = .{},
    seed_batch: geometry.Batch = .{},
    hud_batch: geometry.Batch = .{},
    /// Seed animation clock; stops while paused.
    seed_time: f32 = 0,
    last_time: f64 = 0,
    frame: u64 = 0,
    vsync_applied: bool = true,

    fn fromWindow(win: ?*gl.GLFWwindow) *App {
        return @ptrCast(@alignCast(gl.glfwGetWindowUserPointer(win).?));
    }

    fn framebufferSize(self: *App) [2]u32 {
        var w: c_int = 0;
        var h: c_int = 0;
        gl.glfwGetFramebufferSize(self.window, &w, &h);
        return .{ @intCast(@max(w, 1)), @intCast(@max(h, 1)) };
    }

    fn windowHeight(self: *App) f64 {
        var w: c_int = 0;
        var h: c_int = 0;
        gl.glfwGetWindowSize(self.window, &w, &h);
        return @floatFromInt(h);
    }

    fn step(self: *App) !void {
        const now = gl.glfwGetTime();
        const dt: f32 = @floatCast(@min(now - self.last_time, 0.1));
        self.last_time = now;

        for (controls.held_keys) |k| {
            for (keyBindings(k)) |glfw_key| {
                if (gl.glfwGetKey(self.window, glfw_key) == gl.GLFW_PRESS) {
                    self.state.keyHeld(k, dt);
                    break;
                }
            }
        }
        if (self.state.vsync != self.vsync_applied) {
            gl.glfwSwapInterval(@intFromBool(self.state.vsync));
            self.vsync_applied = self.state.vsync;
        }
        if (!self.state.paused) self.seed_time += dt;

        const size = self.framebufferSize();
        try self.renderer.resize(size[0], size[1]);
        if (self.state.clear_requested) {
            self.renderer.clearFeedback();
            self.state.clear_requested = false;
        }
        const w: f32 = @floatFromInt(size[0]);
        const h: f32 = @floatFromInt(size[1]);

        var center = [2]f32{ w / 2, h / 2 };
        if (self.state.follow_cursor) {
            // Cursor is in window coordinates (y down); framebuffer may be HiDPI-scaled.
            const scale: f32 = @floatCast(@as(f64, h) / self.windowHeight());
            center = .{ @as(f32, @floatCast(self.state.cursor[0])) * scale, h - @as(f32, @floatCast(self.state.cursor[1])) * scale };
        }
        self.seed_batch.clear();
        try scene.buildSeed(&self.seed_batch, self.gpa, self.table, self.state.seed, self.seed_time, center[0], center[1], h * 0.5);

        self.renderer.feedbackPass(.{
            .mvp = self.state.plane.mvp(w / h),
            .gain = self.state.params.tail,
            .hue = self.state.params.hue_shift,
            .border = if (self.state.border) 0.006 else 0,
        }, self.seed_batch.vertices.items);

        self.hud_batch.clear();
        if (self.state.show_hud) {
            try scene.buildHud(&self.hud_batch, self.gpa, self.table, .{
                .fps = self.counter.average,
                .frame_ms = self.counter.frame_time * 1000,
                .state = &self.state,
            }, w, h);
        }
        self.renderer.presentPass(size[0], size[1], self.hud_batch.vertices.items);

        gl.glfwSwapBuffers(self.window);
        self.frame += 1;
        if (self.counter.tick(gl.glfwGetTime())) {
            var buf: [96]u8 = undefined;
            const title = std.fmt.bufPrintSentinel(&buf, "vector-feedback  {d:.1} fps", .{self.counter.average}, 0) catch unreachable;
            gl.glfwSetWindowTitle(self.window, title.ptr);
        }
    }
};

/// GLFW keys bound to each held (continuous) control.
fn keyBindings(k: controls.Key) []const c_int {
    return switch (k) {
        .pan_left => &.{gl.GLFW_KEY_LEFT},
        .pan_right => &.{gl.GLFW_KEY_RIGHT},
        .pan_up => &.{gl.GLFW_KEY_UP},
        .pan_down => &.{gl.GLFW_KEY_DOWN},
        .roll_ccw => &.{gl.GLFW_KEY_Q},
        .roll_cw => &.{gl.GLFW_KEY_E},
        .zoom_in => &.{ gl.GLFW_KEY_W, gl.GLFW_KEY_EQUAL, gl.GLFW_KEY_KP_ADD },
        .zoom_out => &.{ gl.GLFW_KEY_S, gl.GLFW_KEY_MINUS, gl.GLFW_KEY_KP_SUBTRACT },
        .yaw_left => &.{gl.GLFW_KEY_J},
        .yaw_right => &.{gl.GLFW_KEY_L},
        .pitch_up => &.{gl.GLFW_KEY_I},
        .pitch_down => &.{gl.GLFW_KEY_K},
        .tail_longer => &.{gl.GLFW_KEY_RIGHT_BRACKET},
        .tail_shorter => &.{gl.GLFW_KEY_LEFT_BRACKET},
        .hue_up => &.{gl.GLFW_KEY_PERIOD},
        .hue_down => &.{gl.GLFW_KEY_COMMA},
        else => &.{},
    };
}

/// One-shot control for a GLFW key press, if any.
fn pressedKey(key: c_int) ?controls.Key {
    return switch (key) {
        gl.GLFW_KEY_0, gl.GLFW_KEY_KP_0 => .seed_0,
        gl.GLFW_KEY_1, gl.GLFW_KEY_KP_1 => .seed_1,
        gl.GLFW_KEY_2, gl.GLFW_KEY_KP_2 => .seed_2,
        gl.GLFW_KEY_3, gl.GLFW_KEY_KP_3 => .seed_3,
        gl.GLFW_KEY_4, gl.GLFW_KEY_KP_4 => .seed_4,
        gl.GLFW_KEY_TAB => .seed_next,
        gl.GLFW_KEY_SPACE => .pause,
        gl.GLFW_KEY_C => .clear,
        gl.GLFW_KEY_R => .reset,
        gl.GLFW_KEY_H => .toggle_hud,
        gl.GLFW_KEY_F1 => .toggle_help,
        gl.GLFW_KEY_B => .toggle_border,
        gl.GLFW_KEY_M => .toggle_follow,
        gl.GLFW_KEY_V => .toggle_vsync,
        gl.GLFW_KEY_ESCAPE => .quit,
        else => null,
    };
}

fn onKey(win: ?*gl.GLFWwindow, key: c_int, _: c_int, action: c_int, _: c_int) callconv(.c) void {
    if (action != gl.GLFW_PRESS) return;
    const app = App.fromWindow(win);
    if (pressedKey(key)) |k| app.state.keyPressed(k);
    if (app.state.quit) gl.glfwSetWindowShouldClose(win, gl.GLFW_TRUE);
}

fn onMouseButton(win: ?*gl.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.c) void {
    const b: controls.Button = switch (button) {
        gl.GLFW_MOUSE_BUTTON_LEFT => .left,
        gl.GLFW_MOUSE_BUTTON_RIGHT => .right,
        gl.GLFW_MOUSE_BUTTON_MIDDLE => .middle,
        else => return,
    };
    const modifier = mods & (gl.GLFW_MOD_SHIFT | gl.GLFW_MOD_CONTROL) != 0;
    App.fromWindow(win).state.mouseButton(b, action == gl.GLFW_PRESS, modifier);
}

fn onCursor(win: ?*gl.GLFWwindow, x: f64, y: f64) callconv(.c) void {
    const app = App.fromWindow(win);
    app.state.cursorMoved(x, y, app.windowHeight());
}

fn onScroll(win: ?*gl.GLFWwindow, _: f64, dy: f64) callconv(.c) void {
    App.fromWindow(win).state.scroll(dy);
}

fn onGlfwError(code: c_int, msg: [*c]const u8) callconv(.c) void {
    std.log.err("GLFW error {d}: {s}", .{ code, msg });
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const opts = parseOptions(args) catch {
        std.debug.print("invalid arguments\n\n{s}", .{usage});
        std.process.exit(2);
    };
    if (opts.help) {
        std.debug.print("{s}", .{usage});
        return;
    }

    var atlas = try slughorn.Atlas.init();
    defer atlas.deinit();
    shapes.registerAll(atlas) catch {
        std.log.err("slughorn: {s}", .{atlas.lastError()});
        return error.SlughornFailure;
    };
    atlas.build() catch {
        std.log.err("slughorn build: {s}", .{atlas.lastError()});
        return error.SlughornFailure;
    };

    _ = gl.glfwSetErrorCallback(onGlfwError);
    if (gl.glfwInit() == gl.GLFW_FALSE) return error.GlfwInit;
    defer gl.glfwTerminate();

    gl.glfwWindowHint(gl.GLFW_CONTEXT_VERSION_MAJOR, 3);
    gl.glfwWindowHint(gl.GLFW_CONTEXT_VERSION_MINOR, 3);
    gl.glfwWindowHint(gl.GLFW_OPENGL_PROFILE, gl.GLFW_OPENGL_CORE_PROFILE);
    gl.glfwWindowHint(gl.GLFW_OPENGL_FORWARD_COMPAT, gl.GLFW_TRUE);
    const window = gl.glfwCreateWindow(@intCast(opts.width), @intCast(opts.height), "vector-feedback", null, null) orelse
        return error.WindowCreation;
    defer gl.glfwDestroyWindow(window);
    gl.glfwMakeContextCurrent(window);
    gl.glfwSwapInterval(@intFromBool(opts.vsync));

    std.log.info("OpenGL {s} on {s}", .{ gl.glGetString(gl.GL_VERSION), gl.glGetString(gl.GL_RENDERER) });

    var app: App = .{
        .gpa = gpa,
        .window = window,
        .renderer = try Renderer.init(gpa, atlas),
        .table = geometry.ShapeTable.load(atlas),
        .state = .{ .vsync = opts.vsync, .seed = opts.seed, .show_help = opts.show_help },
        .vsync_applied = opts.vsync,
    };
    defer {
        app.renderer.deinit();
        app.seed_batch.deinit(gpa);
        app.hud_batch.deinit(gpa);
    }

    if (opts.tail) |t| app.state.params.tail = t;

    gl.glfwSetWindowUserPointer(window, &app);
    _ = gl.glfwSetKeyCallback(window, onKey);
    _ = gl.glfwSetMouseButtonCallback(window, onMouseButton);
    _ = gl.glfwSetCursorPosCallback(window, onCursor);
    _ = gl.glfwSetScrollCallback(window, onScroll);
    var cx: f64 = 0;
    var cy: f64 = 0;
    gl.glfwGetCursorPos(window, &cx, &cy);
    app.state.cursor = .{ cx, cy };
    app.last_time = gl.glfwGetTime();

    if (!opts.selftest) std.debug.print("vector-feedback: press F1 for controls, Esc to quit\n", .{});

    while (gl.glfwWindowShouldClose(window) == gl.GLFW_FALSE) {
        gl.glfwPollEvents();
        try app.step();
        if (opts.frames) |n| if (app.frame >= n) break;
    }

    if (opts.screenshot) |path| try writeScreenshot(&app, init.io, path);
    if (opts.selftest) try selftest(&app);
}

fn writeScreenshot(app: *App, io: std.Io, path: []const u8) !void {
    const size = app.framebufferSize();
    const rgba = try app.gpa.alloc(u8, @as(usize, size[0]) * size[1] * 4);
    defer app.gpa.free(rgba);
    app.renderer.readPixels(.screen, size[0], size[1], rgba);

    var header: [32]u8 = undefined;
    const head = try std.fmt.bufPrint(&header, "P6\n{d} {d}\n255\n", .{ size[0], size[1] });
    const ppm = try app.gpa.alloc(u8, head.len + @as(usize, size[0]) * size[1] * 3);
    defer app.gpa.free(ppm);
    @memcpy(ppm[0..head.len], head);
    var o: usize = head.len;
    // GL rows are bottom-up; PPM is top-down.
    var row = size[1];
    while (row > 0) {
        row -= 1;
        for (0..size[0]) |x| {
            const i = (@as(usize, row) * size[0] + x) * 4;
            @memcpy(ppm[o..][0..3], rgba[i..][0..3]);
            o += 3;
        }
    }
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = ppm });
    std.log.info("wrote {s} ({d}x{d})", .{ path, size[0], size[1] });
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

/// Checks, on the live GL context, that vector shapes render, the HUD is visible, the
/// feedback image persists without a seed, and a zero tail extinguishes it.
fn selftest(app: *App) !void {
    const size = app.framebufferSize();
    const w = size[0];
    const h = size[1];
    const buf = try app.gpa.alloc(u8, @as(usize, w) * h * 4);
    defer app.gpa.free(buf);
    var failures: u32 = 0;

    app.renderer.readPixels(.screen, w, h, buf);
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
    try app.step();
    app.renderer.readPixels(.feedback, w, h, buf);
    const echoed = litFraction(buf, w, 0, 0, w, h, 8);
    failures += check("feedback persists without a seed", echoed > seeded * 0.5 and echoed > 0.01, echoed);

    // Moving the picture plane must move the echo.
    const before = try app.gpa.dupe(u8, buf);
    defer app.gpa.free(before);
    app.state.plane.pan(0.5, 0);
    try app.step();
    app.renderer.readPixels(.feedback, w, h, buf);
    var changed: usize = 0;
    for (0..buf.len / 4) |i| {
        if (@abs(@as(i16, buf[i * 4]) - before[i * 4]) > 8) changed += 1;
    }
    const moved = @as(f64, @floatFromInt(changed)) / @as(f64, @floatFromInt(@as(usize, w) * h));
    failures += check("panning the plane moves the image", moved > 0.005, moved);

    app.state.params.tail = 0;
    try app.step();
    try app.step();
    app.renderer.readPixels(.feedback, w, h, buf);
    const extinguished = litFraction(buf, w, 0, 0, w, h, 2);
    failures += check("zero tail clears the loop", extinguished < 0.001, extinguished);

    if (failures > 0) {
        std.log.err("selftest: {d} check(s) failed", .{failures});
        return error.SelftestFailed;
    }
    std.log.info("selftest: all checks passed ({d}x{d}, {d:.1} fps)", .{ w, h, app.counter.average });
}

fn check(name: []const u8, ok: bool, value: anytype) u32 {
    if (ok) {
        std.log.info("PASS {s} ({d:.4})", .{ name, value });
        return 0;
    }
    std.log.err("FAIL {s} ({d:.4})", .{ name, value });
    return 1;
}

test parseOptions {
    const o = try parseOptions(&.{ "x", "--frames", "5", "--no-vsync", "--screenshot", "a.ppm" });
    try std.testing.expectEqual(@as(?u64, 5), o.frames);
    try std.testing.expect(!o.vsync);
    try std.testing.expectEqualStrings("a.ppm", o.screenshot.?);
    try std.testing.expectEqual(@as(?u64, 120), (try parseOptions(&.{ "x", "--selftest" })).frames);
    try std.testing.expectError(error.InvalidArguments, parseOptions(&.{ "x", "--bogus" }));
    const p = try parseOptions(&.{ "x", "--seed", "spiral", "--tail", "2" });
    try std.testing.expectEqual(controls.Seed.spiral, p.seed);
    try std.testing.expectEqual(feedback.max_tail, p.tail.?);
    try std.testing.expectError(error.InvalidArguments, parseOptions(&.{ "x", "--seed", "cube" }));
}
