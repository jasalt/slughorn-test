//! OpenGL 3.3 core renderer: a ping-pong pair of float framebuffers forms the feedback
//! loop; each frame re-draws the previous image on the picture plane, adds the vector
//! seed on top, then presents the result and the HUD to the window.
const std = @import("std");
const gl = @import("gl_c");
const slughorn = @import("slughorn.zig");
const geometry = @import("geometry.zig");
const shaders = @import("shaders.zig");
const Mat4 = @import("math.zig").Mat4;

pub const Error = error{ ShaderCompile, ProgramLink, IncompleteFramebuffer, UnsupportedAtlas, OutOfMemory };

pub const PlaneUniforms = struct {
    mvp: Mat4,
    gain: f32,
    hue: f32,
    /// Border width in plane UV units; 0 disables it.
    border: f32,
};

pub const Target = enum { screen, feedback };

const Program = struct {
    id: gl.GLuint,

    fn init(gpa: std.mem.Allocator, prefix: []const u8, vert: []const u8, frag: []const u8) Error!Program {
        const vs = try compile(gpa, gl.GL_VERTEX_SHADER, prefix, vert);
        defer gl.glDeleteShader(vs);
        const fs = try compile(gpa, gl.GL_FRAGMENT_SHADER, prefix, frag);
        defer gl.glDeleteShader(fs);

        const id = gl.glCreateProgram();
        gl.glAttachShader(id, vs);
        gl.glAttachShader(id, fs);
        gl.glLinkProgram(id);
        var ok: gl.GLint = 0;
        gl.glGetProgramiv(id, gl.GL_LINK_STATUS, &ok);
        if (ok == 0) {
            var log: [2048]u8 = undefined;
            var len: gl.GLsizei = 0;
            gl.glGetProgramInfoLog(id, log.len, &len, &log);
            std.log.err("program link failed:\n{s}", .{log[0..@intCast(len)]});
            return error.ProgramLink;
        }
        return .{ .id = id };
    }

    fn compile(gpa: std.mem.Allocator, kind: gl.GLenum, prefix: []const u8, body: []const u8) Error!gl.GLuint {
        const src = try std.mem.concat(gpa, u8, &.{ shaders.version, prefix, body });
        defer gpa.free(src);
        const id = gl.glCreateShader(kind);
        const ptr: [*c]const u8 = src.ptr;
        const len: gl.GLint = @intCast(src.len);
        gl.glShaderSource(id, 1, &ptr, &len);
        gl.glCompileShader(id);
        var ok: gl.GLint = 0;
        gl.glGetShaderiv(id, gl.GL_COMPILE_STATUS, &ok);
        if (ok == 0) {
            var log: [2048]u8 = undefined;
            var log_len: gl.GLsizei = 0;
            gl.glGetShaderInfoLog(id, log.len, &log_len, &log);
            std.log.err("shader compile failed:\n{s}", .{log[0..@intCast(log_len)]});
            gl.glDeleteShader(id);
            return error.ShaderCompile;
        }
        return id;
    }

    fn uniform(self: Program, name: [*:0]const u8) gl.GLint {
        return gl.glGetUniformLocation(self.id, name);
    }

    fn deinit(self: Program) void {
        gl.glDeleteProgram(self.id);
    }
};

pub const Renderer = struct {
    gpa: std.mem.Allocator,

    slug: Program,
    slug_mvp: gl.GLint,
    plane: Program,
    plane_mvp: gl.GLint,
    plane_gain: gl.GLint,
    plane_hue: gl.GLint,
    plane_border: gl.GLint,
    present: Program,

    curve_tex: gl.GLuint,
    band_tex: gl.GLuint,

    slug_vao: gl.GLuint,
    slug_vbo: gl.GLuint,
    plane_vao: gl.GLuint,
    plane_vbo: gl.GLuint,
    empty_vao: gl.GLuint,

    fbos: [2]gl.GLuint = .{ 0, 0 },
    color: [2]gl.GLuint = .{ 0, 0 },
    /// RGBA8 copy target for reading the float feedback buffer back as bytes
    /// (WebGL2 cannot read float attachments as UNSIGNED_BYTE).
    readback_fbo: gl.GLuint = 0,
    readback_tex: gl.GLuint = 0,
    /// Index of the buffer holding the most recent feedback frame.
    current: u1 = 0,
    size: [2]u32 = .{ 0, 0 },

    pub fn init(gpa: std.mem.Allocator, atlas: slughorn.Atlas) Error!Renderer {
        const curves = atlas.curveTexture();
        const bands = atlas.bandTexture();
        // The shader wraps both textures with one shift, so widths must match and be 2^n.
        if (curves.width != bands.width or !std.math.isPowerOfTwo(curves.width) or
            curves.format != .rgba32f or bands.format != .rg16ui) return error.UnsupportedAtlas;

        var prefix_buf: [64]u8 = undefined;
        const prefix = std.fmt.bufPrint(&prefix_buf, "#define TEX_WIDTH {d}\n", .{std.math.log2_int(u32, curves.width)}) catch unreachable;

        const slug = try Program.init(gpa, prefix, shaders.slug_vert, shaders.slug_frag);
        const plane = try Program.init(gpa, "", shaders.plane_vert, shaders.plane_frag);
        const present = try Program.init(gpa, "", shaders.present_vert, shaders.present_frag);

        gl.glUseProgram(slug.id);
        gl.glUniform1i(slug.uniform("u_curveTexture"), 0);
        gl.glUniform1i(slug.uniform("u_bandTexture"), 1);
        gl.glUseProgram(plane.id);
        gl.glUniform1i(plane.uniform("u_prev"), 0);
        gl.glUseProgram(present.id);
        gl.glUniform1i(present.uniform("u_tex"), 0);
        gl.glUseProgram(0);

        var self: Renderer = .{
            .gpa = gpa,
            .slug = slug,
            .slug_mvp = slug.uniform("u_mvp"),
            .plane = plane,
            .plane_mvp = plane.uniform("u_mvp"),
            .plane_gain = plane.uniform("u_gain"),
            .plane_hue = plane.uniform("u_hue"),
            .plane_border = plane.uniform("u_border"),
            .present = present,
            .curve_tex = uploadAtlasTexture(curves, gl.GL_RGBA32F, gl.GL_RGBA, gl.GL_FLOAT),
            .band_tex = uploadAtlasTexture(bands, gl.GL_RG16UI, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT),
            .slug_vao = 0,
            .slug_vbo = 0,
            .plane_vao = 0,
            .plane_vbo = 0,
            .empty_vao = 0,
        };

        gl.glGenVertexArrays(1, &self.slug_vao);
        gl.glGenBuffers(1, &self.slug_vbo);
        gl.glBindVertexArray(self.slug_vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.slug_vbo);
        const V = geometry.Vertex;
        attrib(0, 2, @sizeOf(V), @offsetOf(V, "pos"));
        attrib(1, 4, @sizeOf(V), @offsetOf(V, "color"));
        attrib(2, 2, @sizeOf(V), @offsetOf(V, "em"));
        attrib(3, 4, @sizeOf(V), @offsetOf(V, "band_transform"));
        attrib(4, 4, @sizeOf(V), @offsetOf(V, "shape_data"));

        gl.glGenVertexArrays(1, &self.plane_vao);
        gl.glGenBuffers(1, &self.plane_vbo);
        gl.glBindVertexArray(self.plane_vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.plane_vbo);
        attrib(0, 2, 4 * @sizeOf(f32), 0);
        attrib(1, 2, 4 * @sizeOf(f32), 2 * @sizeOf(f32));

        gl.glGenVertexArrays(1, &self.empty_vao);
        gl.glBindVertexArray(0);
        return self;
    }

    pub fn deinit(self: *Renderer) void {
        self.releaseTargets();
        gl.glDeleteTextures(1, &self.curve_tex);
        gl.glDeleteTextures(1, &self.band_tex);
        const vaos = [_]gl.GLuint{ self.slug_vao, self.plane_vao, self.empty_vao };
        gl.glDeleteVertexArrays(vaos.len, &vaos);
        const vbos = [_]gl.GLuint{ self.slug_vbo, self.plane_vbo };
        gl.glDeleteBuffers(vbos.len, &vbos);
        self.slug.deinit();
        self.plane.deinit();
        self.present.deinit();
    }

    /// (Re)creates the feedback buffers when the framebuffer size changes.
    pub fn resize(self: *Renderer, width: u32, height: u32) Error!void {
        if (self.size[0] == width and self.size[1] == height) return;
        self.releaseTargets();
        self.size = .{ width, height };
        gl.glGenTextures(2, &self.color);
        gl.glGenFramebuffers(2, &self.fbos);
        for (self.color, self.fbos) |tex, fbo| {
            // Float storage lets faint trails keep decaying instead of sticking at 8-bit steps.
            try attachTarget(fbo, tex, gl.GL_RGBA16F, gl.GL_FLOAT, width, height);
        }
        gl.glGenTextures(1, &self.readback_tex);
        gl.glGenFramebuffers(1, &self.readback_fbo);
        try attachTarget(self.readback_fbo, self.readback_tex, gl.GL_RGBA8, gl.GL_UNSIGNED_BYTE, width, height);
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0);
        self.clearFeedback();
    }

    // The plane quad's UVs span exactly [0, 1], so edge clamping only affects the
    // bilinear fringe; everything outside the plane is cleared to black each frame.
    fn attachTarget(fbo: gl.GLuint, tex: gl.GLuint, internal: gl.GLint, kind: gl.GLenum, width: u32, height: u32) Error!void {
        gl.glBindTexture(gl.GL_TEXTURE_2D, tex);
        gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, internal, @intCast(width), @intCast(height), 0, gl.GL_RGBA, kind, null);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
        gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, tex, 0);
        if (gl.glCheckFramebufferStatus(gl.GL_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE) return error.IncompleteFramebuffer;
    }

    pub fn clearFeedback(self: *Renderer) void {
        gl.glClearColor(0, 0, 0, 1);
        for (self.fbos) |fbo| {
            gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
            gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        }
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0);
    }

    /// Advances the feedback loop by one frame: previous image through the picture
    /// plane, then `seed` vector shapes (pixel coordinates) on top.
    pub fn feedbackPass(self: *Renderer, plane: PlaneUniforms, seed: []const geometry.Vertex) void {
        const prev = self.current;
        const next = prev ^ 1;
        const w: f32 = @floatFromInt(self.size[0]);
        const h: f32 = @floatFromInt(self.size[1]);

        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, self.fbos[next]);
        gl.glViewport(0, 0, @intCast(self.size[0]), @intCast(self.size[1]));
        gl.glClearColor(0, 0, 0, 1);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        gl.glDisable(gl.GL_BLEND);

        const aspect = w / h;
        const quad = [_]f32{
            -aspect, -1, 0, 0,
            aspect,  -1, 1, 0,
            aspect,  1,  1, 1,
            -aspect, -1, 0, 0,
            aspect,  1,  1, 1,
            -aspect, 1,  0, 1,
        };
        gl.glUseProgram(self.plane.id);
        gl.glUniformMatrix4fv(self.plane_mvp, 1, gl.GL_FALSE, &plane.mvp.m);
        gl.glUniform1f(self.plane_gain, plane.gain);
        gl.glUniform1f(self.plane_hue, plane.hue);
        gl.glUniform1f(self.plane_border, plane.border);
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.color[prev]);
        gl.glBindVertexArray(self.plane_vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.plane_vbo);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(quad)), &quad, gl.GL_STREAM_DRAW);
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 6);

        self.drawVectors(seed, w, h);
        self.current = next;
    }

    /// Copies the current feedback frame to the window and draws `overlay` (the HUD) on top.
    pub fn presentPass(self: *Renderer, width: u32, height: u32, overlay: []const geometry.Vertex) void {
        self.copyFeedback(0, width, height);
        self.drawVectors(overlay, @floatFromInt(width), @floatFromInt(height));
    }

    fn copyFeedback(self: *Renderer, fbo: gl.GLuint, width: u32, height: u32) void {
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
        gl.glViewport(0, 0, @intCast(width), @intCast(height));
        gl.glDisable(gl.GL_BLEND);
        gl.glUseProgram(self.present.id);
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.color[self.current]);
        gl.glBindVertexArray(self.empty_vao);
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 3);
    }

    fn drawVectors(self: *Renderer, vertices: []const geometry.Vertex, w: f32, h: f32) void {
        if (vertices.len == 0) return;
        gl.glEnable(gl.GL_BLEND);
        gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);
        gl.glUseProgram(self.slug.id);
        const mvp = Mat4.ortho(0, w, 0, h, -1, 1);
        gl.glUniformMatrix4fv(self.slug_mvp, 1, gl.GL_FALSE, &mvp.m);
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.curve_tex);
        gl.glActiveTexture(gl.GL_TEXTURE1);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.band_tex);
        gl.glBindVertexArray(self.slug_vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.slug_vbo);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(vertices.len * @sizeOf(geometry.Vertex)), vertices.ptr, gl.GL_STREAM_DRAW);
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, @intCast(vertices.len));
        gl.glActiveTexture(gl.GL_TEXTURE0);
    }

    /// Reads back RGBA8 pixels (bottom row first) of the window or the feedback buffer.
    pub fn readPixels(self: *Renderer, target: Target, width: u32, height: u32, out: []u8) void {
        std.debug.assert(out.len >= @as(usize, width) * height * 4);
        if (target == .feedback) self.copyFeedback(self.readback_fbo, self.size[0], self.size[1]);
        gl.glBindFramebuffer(gl.GL_READ_FRAMEBUFFER, switch (target) {
            .screen => 0,
            .feedback => self.readback_fbo,
        });
        gl.glPixelStorei(gl.GL_PACK_ALIGNMENT, 1);
        gl.glReadPixels(0, 0, @intCast(width), @intCast(height), gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, out.ptr);
        gl.glBindFramebuffer(gl.GL_READ_FRAMEBUFFER, 0);
    }

    fn releaseTargets(self: *Renderer) void {
        if (self.fbos[0] != 0) {
            gl.glDeleteFramebuffers(2, &self.fbos);
            gl.glDeleteTextures(2, &self.color);
            gl.glDeleteFramebuffers(1, &self.readback_fbo);
            gl.glDeleteTextures(1, &self.readback_tex);
        }
        self.fbos = .{ 0, 0 };
        self.color = .{ 0, 0 };
        self.readback_fbo = 0;
        self.readback_tex = 0;
        self.size = .{ 0, 0 };
    }
};

fn attrib(index: gl.GLuint, components: gl.GLint, stride: usize, offset: usize) void {
    gl.glEnableVertexAttribArray(index);
    gl.glVertexAttribPointer(index, components, gl.GL_FLOAT, gl.GL_FALSE, @intCast(stride), @ptrFromInt(offset));
}

fn uploadAtlasTexture(t: slughorn.Texture, internal: gl.GLint, format: gl.GLenum, kind: gl.GLenum) gl.GLuint {
    var tex: gl.GLuint = 0;
    gl.glGenTextures(1, &tex);
    gl.glBindTexture(gl.GL_TEXTURE_2D, tex);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
    gl.glPixelStorei(gl.GL_UNPACK_ALIGNMENT, 1);
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, internal, @intCast(t.width), @intCast(t.height), 0, format, kind, t.bytes.ptr);
    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);
    return tex;
}
