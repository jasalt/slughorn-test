//! vector-feedback: a video-feedback device built on slughorn GPU vector graphics.
//!
//! The previous frame is shown on a picture plane in front of a virtual camera; moving
//! that plane (pan, roll, tilt, zoom) with the mouse or keyboard sculpts the recursive
//! image, while slughorn-rendered vector shapes keep feeding new light into the loop.
const std = @import("std");
const gl = @import("gl_c");
const slughorn = @import("slughorn.zig");
const shapes = @import("shapes.zig");
const controls = @import("controls.zig");
const feedback = @import("feedback.zig");
const keymap = @import("keymap.zig");
const selftest = @import("selftest.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;

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

/// GLFW front end: window, input callbacks and buffer swaps around the shared App.
const Platform = struct {
    window: *gl.GLFWwindow,
    app: *App,

    fn fromWindow(win: ?*gl.GLFWwindow) *Platform {
        return @ptrCast(@alignCast(gl.glfwGetWindowUserPointer(win).?));
    }

    fn windowHeight(self: *const Platform) f64 {
        var w: c_int = 0;
        var h: c_int = 0;
        gl.glfwGetWindowSize(self.window, &w, &h);
        return @floatFromInt(h);
    }

    pub fn isDown(self: Platform, key: c_int) bool {
        return gl.glfwGetKey(self.window, key) == gl.GLFW_PRESS;
    }

    pub fn frame(self: *Platform) app_mod.Frame {
        var w: c_int = 0;
        var h: c_int = 0;
        gl.glfwGetFramebufferSize(self.window, &w, &h);
        return .{
            .now = gl.glfwGetTime(),
            .size = .{ @intCast(@max(w, 1)), @intCast(@max(h, 1)) },
            .window_height = self.windowHeight(),
            .held = keymap.heldKeys(self.*),
        };
    }

    pub fn present(self: *Platform) void {
        gl.glfwSwapBuffers(self.window);
        gl.glfwPollEvents();
        if (self.app.presented(gl.glfwGetTime())) {
            var buf: [96]u8 = undefined;
            const title = std.fmt.bufPrintSentinel(&buf, "vector-feedback  {d:.1} fps", .{self.app.counter.average}, 0) catch unreachable;
            gl.glfwSetWindowTitle(self.window, title.ptr);
        }
    }

    pub fn resize(self: *Platform, w: u32, h: u32) void {
        gl.glfwSetWindowSize(self.window, @intCast(w), @intCast(h));
        gl.glfwPollEvents();
    }
};

fn onKey(win: ?*gl.GLFWwindow, key: c_int, _: c_int, action: c_int, _: c_int) callconv(.c) void {
    if (action != gl.GLFW_PRESS) return;
    const app = Platform.fromWindow(win).app;
    if (keymap.pressed(key)) |k| app.state.keyPressed(k);
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
    Platform.fromWindow(win).app.state.mouseButton(b, action == gl.GLFW_PRESS, modifier);
}

fn onCursor(win: ?*gl.GLFWwindow, x: f64, y: f64) callconv(.c) void {
    const p = Platform.fromWindow(win);
    p.app.state.cursorMoved(x, y, p.windowHeight());
}

fn onScroll(win: ?*gl.GLFWwindow, _: f64, dy: f64) callconv(.c) void {
    Platform.fromWindow(win).app.state.scroll(dy);
}

fn onGlfwError(code: c_int, msg: [*c]const u8) callconv(.c) void {
    std.log.err("GLFW error {d}: {s}", .{ code, msg });
}

comptime {
    // keymap.zig hard-codes GLFW's key numbers so the web build can share it.
    std.debug.assert(keymap.code.left == gl.GLFW_KEY_LEFT);
    std.debug.assert(keymap.code.f1 == gl.GLFW_KEY_F1);
    std.debug.assert(keymap.code.kp_add == gl.GLFW_KEY_KP_ADD);
    std.debug.assert(keymap.code.letter('Q') == gl.GLFW_KEY_Q);
    std.debug.assert(keymap.code.right_bracket == gl.GLFW_KEY_RIGHT_BRACKET);
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
    var vsync_applied = opts.vsync;

    std.log.info("OpenGL {s} on {s}", .{ gl.glGetString(gl.GL_VERSION), gl.glGetString(gl.GL_RENDERER) });

    var app = try App.init(gpa, atlas);
    defer app.deinit();
    app.state.vsync = opts.vsync;
    app.state.seed = opts.seed;
    app.state.show_help = opts.show_help;
    if (opts.tail) |t| app.state.params.tail = t;

    var platform: Platform = .{ .window = window, .app = &app };
    gl.glfwSetWindowUserPointer(window, &platform);
    _ = gl.glfwSetKeyCallback(window, onKey);
    _ = gl.glfwSetMouseButtonCallback(window, onMouseButton);
    _ = gl.glfwSetCursorPosCallback(window, onCursor);
    _ = gl.glfwSetScrollCallback(window, onScroll);
    var cx: f64 = 0;
    var cy: f64 = 0;
    gl.glfwGetCursorPos(window, &cx, &cy);
    app.state.cursor = .{ cx, cy };

    if (!opts.selftest) std.debug.print("vector-feedback: press F1 for controls, Esc to quit\n", .{});

    while (gl.glfwWindowShouldClose(window) == gl.GLFW_FALSE) {
        if (app.state.vsync != vsync_applied) {
            gl.glfwSwapInterval(@intFromBool(app.state.vsync));
            vsync_applied = app.state.vsync;
        }
        try app.render(platform.frame());
        if (opts.frames) |n| if (app.frame >= n) break;
        platform.present();
    }

    // The final frame is still in the back buffer here, unpresented.
    if (opts.screenshot) |path| try writeScreenshot(&app, init.io, path);
    if (opts.selftest) try selftest.run(&app, &platform);
}

fn writeScreenshot(app: *App, io: std.Io, path: []const u8) !void {
    const size = app.size;
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
