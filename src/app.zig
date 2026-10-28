//! Platform-independent application core shared by the native (GLFW) and web (WebGL2)
//! front ends: owns the renderer and per-frame scene building.
const std = @import("std");
const slughorn = @import("slughorn.zig");
const geometry = @import("geometry.zig");
const controls = @import("controls.zig");
const scene = @import("scene.zig");
const fps = @import("fps.zig");
const Renderer = @import("renderer.zig").Renderer;

/// What the platform reports for one frame.
pub const Frame = struct {
    /// Seconds on a monotonic clock.
    now: f64,
    /// Drawable size in physical pixels.
    size: [2]u32,
    /// Height of the window in the units cursor positions are reported in.
    window_height: f64,
    held: std.EnumSet(controls.Key) = .empty,
};

pub const App = struct {
    gpa: std.mem.Allocator,
    renderer: Renderer,
    table: geometry.ShapeTable,
    state: controls.State = .{},
    counter: fps.Counter = .{},
    seed_batch: geometry.Batch = .{},
    hud_batch: geometry.Batch = .{},
    /// Seed animation clock; stops while paused.
    seed_time: f32 = 0,
    last_time: ?f64 = null,
    frame: u64 = 0,
    /// Drawable size of the last rendered frame.
    size: [2]u32 = .{ 0, 0 },

    /// `atlas` must be built; its textures are copied to the GPU.
    pub fn init(gpa: std.mem.Allocator, atlas: slughorn.Atlas) !App {
        return .{
            .gpa = gpa,
            .renderer = try Renderer.init(gpa, atlas),
            .table = geometry.ShapeTable.load(atlas),
        };
    }

    pub fn deinit(self: *App) void {
        self.renderer.deinit();
        self.seed_batch.deinit(self.gpa);
        self.hud_batch.deinit(self.gpa);
    }

    /// Renders one frame to the default framebuffer (the caller presents it).
    pub fn render(self: *App, f: Frame) !void {
        const dt: f32 = if (self.last_time) |last| @floatCast(std.math.clamp(f.now - last, 0, 0.1)) else 0;
        self.last_time = f.now;

        var it = f.held.iterator();
        while (it.next()) |k| self.state.keyHeld(k, dt);
        if (!self.state.paused) self.seed_time += dt;

        const size: [2]u32 = .{ @max(f.size[0], 1), @max(f.size[1], 1) };
        self.size = size;
        try self.renderer.resize(size[0], size[1]);
        if (self.state.clear_requested) {
            self.renderer.clearFeedback();
            self.state.clear_requested = false;
        }
        const w: f32 = @floatFromInt(size[0]);
        const h: f32 = @floatFromInt(size[1]);

        var center = [2]f32{ w / 2, h / 2 };
        if (self.state.follow_cursor and f.window_height > 0) {
            // Cursor is in window coordinates (y down); the drawable may be HiDPI-scaled.
            const scale: f32 = @floatCast(@as(f64, h) / f.window_height);
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
        self.frame += 1;
    }

    /// Call after the frame is presented. Returns true when the FPS average changed.
    pub fn presented(self: *App, now: f64) bool {
        return self.counter.tick(now);
    }
};
