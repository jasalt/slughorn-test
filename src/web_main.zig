//! WebAssembly entry point: a WebGL2 front end around the shared App. The page script
//! (web/vector-feedback.js) owns the canvas and event listeners and calls these exports.
const std = @import("std");
const slughorn = @import("slughorn.zig");
const shapes = @import("shapes.zig");
const controls = @import("controls.zig");
const keymap = @import("keymap.zig");
const selftest = @import("selftest.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;

const env = struct {
    extern "env" fn now() f64;
    extern "env" fn canvasWidth() u32;
    extern "env" fn canvasHeight() u32;
    /// Canvas height in CSS pixels, the unit pointer events are reported in.
    extern "env" fn cssHeight() f64;
    extern "env" fn setCanvasSize(w: u32, h: u32) void;
    extern "env" fn log(level: u32, ptr: [*]const u8, len: usize) void;
};

pub const std_options: std.Options = .{ .logFn = logToConsole };

fn logToConsole(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = scope;
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, format, args) catch buf[0..];
    env.log(@intFromEnum(level), msg.ptr, msg.len);
}

const gpa = std.heap.c_allocator;

var atlas: ?slughorn.Atlas = null;
var app: ?App = null;
var keys_down: [keymap.code.count]bool = @splat(false);

const Platform = struct {
    pub fn isDown(_: Platform, code: c_int) bool {
        return code >= 0 and code < keys_down.len and keys_down[@intCast(code)];
    }

    pub fn frame(_: *Platform) app_mod.Frame {
        return .{
            .now = env.now(),
            .size = .{ env.canvasWidth(), env.canvasHeight() },
            .window_height = env.cssHeight(),
            .held = keymap.heldKeys(Platform{}),
        };
    }

    /// The browser composites when the animation-frame callback returns.
    pub fn present(_: *Platform) void {
        _ = app.?.presented(env.now());
    }

    pub fn resize(_: *Platform, w: u32, h: u32) void {
        env.setCanvasSize(w, h);
    }
};

/// Builds the slughorn atlas and GPU resources. Returns 0 on success.
export fn vf_init() i32 {
    init() catch |err| {
        std.log.err("init failed: {s}", .{@errorName(err)});
        return -1;
    };
    return 0;
}

fn init() !void {
    var a = try slughorn.Atlas.init();
    errdefer a.deinit();
    shapes.registerAll(a) catch {
        std.log.err("slughorn: {s}", .{a.lastError()});
        return error.SlughornFailure;
    };
    a.build() catch {
        std.log.err("slughorn build: {s}", .{a.lastError()});
        return error.SlughornFailure;
    };
    atlas = a;
    app = try App.init(gpa, a);
}

/// Renders one animation frame. Returns 0 on success.
export fn vf_frame() i32 {
    const a = if (app) |*a| a else return -1;
    var p: Platform = .{};
    a.render(p.frame()) catch |err| {
        std.log.err("frame failed: {s}", .{@errorName(err)});
        return -1;
    };
    p.present();
    return 0;
}

export fn vf_key(code: i32, down: i32) void {
    if (code >= 0 and code < keys_down.len) keys_down[@intCast(code)] = down != 0;
    if (down == 0) return;
    if (keymap.pressed(code)) |k| app.?.state.keyPressed(k);
}

/// `button`: 0 left, 1 middle, 2 right (DOM numbering).
export fn vf_mouse_button(button: i32, down: i32, modifier: i32) void {
    const b: controls.Button = switch (button) {
        0 => .left,
        1 => .middle,
        2 => .right,
        else => return,
    };
    app.?.state.mouseButton(b, down != 0, modifier != 0);
}

export fn vf_cursor(x: f64, y: f64) void {
    app.?.state.cursorMoved(x, y, env.cssHeight());
}

export fn vf_scroll(dy: f64) void {
    app.?.state.scroll(dy);
}

/// Runs the shared selftest on the live WebGL context. Returns the number of failures
/// as 0 (pass) or 1 (fail); details go to the log.
export fn vf_selftest() i32 {
    var p: Platform = .{};
    selftest.run(&app.?, &p) catch return 1;
    return 0;
}

var state_json: [512]u8 = undefined;
var state_json_len: usize = 0;

/// Serialises the control state for the page script (testing and debugging). Returns a
/// pointer to the JSON text; its length is returned by vf_state_len().
export fn vf_state() [*]const u8 {
    const a = &app.?;
    const s = &a.state;
    const p = s.plane;
    const json = std.fmt.bufPrint(&state_json,
        \\{{"frame":{d},"fps":{d},"seed":"{s}","help":{},"hud":{},"paused":{},"tail":{d},"hue":{d},"pan_x":{d},"pan_y":{d},"roll":{d},"yaw":{d},"pitch":{d},"zoom":{d}}}
    , .{
        a.frame,          a.counter.average,  s.seed.label(),   s.show_help,
        s.show_hud,       s.paused,           s.params.tail,    s.params.hue_shift,
        p.pan_x,          p.pan_y,            p.roll,           p.yaw,
        p.pitch,          p.zoom,
    }) catch unreachable;
    state_json_len = json.len;
    return &state_json;
}

export fn vf_state_len() usize {
    return state_json_len;
}
