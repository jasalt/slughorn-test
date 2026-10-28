//! WebGL2 stand-in for the translated GL headers (`gl_c`) in the wasm build. It exposes the
//! subset of the OpenGL 3.3 API the renderer uses, with C-compatible signatures, and forwards
//! to the JS binding in web/vector-feedback.js (import module "gl"). GL object names are
//! integer handles into JS-side tables.
const std = @import("std");

pub const GLuint = c_uint;
pub const GLint = c_int;
pub const GLenum = c_uint;
pub const GLsizei = c_int;
pub const GLboolean = u8;
pub const GLfloat = f32;
pub const GLbitfield = c_uint;
pub const GLsizeiptr = isize;

pub const GL_FALSE = 0;
pub const GL_TRUE = 1;
pub const GL_TRIANGLES = 0x0004;
pub const GL_SRC_ALPHA = 0x0302;
pub const GL_ONE_MINUS_SRC_ALPHA = 0x0303;
pub const GL_BLEND = 0x0BE2;
pub const GL_UNPACK_ALIGNMENT = 0x0CF5;
pub const GL_PACK_ALIGNMENT = 0x0D05;
pub const GL_TEXTURE_2D = 0x0DE1;
pub const GL_UNSIGNED_BYTE = 0x1401;
pub const GL_UNSIGNED_SHORT = 0x1403;
pub const GL_FLOAT = 0x1406;
pub const GL_RGBA = 0x1908;
pub const GL_NEAREST = 0x2600;
pub const GL_LINEAR = 0x2601;
pub const GL_TEXTURE_MAG_FILTER = 0x2800;
pub const GL_TEXTURE_MIN_FILTER = 0x2801;
pub const GL_TEXTURE_WRAP_S = 0x2802;
pub const GL_TEXTURE_WRAP_T = 0x2803;
pub const GL_RGBA8 = 0x8058;
pub const GL_CLAMP_TO_EDGE = 0x812F;
pub const GL_RG_INTEGER = 0x8228;
pub const GL_RG16UI = 0x823A;
pub const GL_TEXTURE0 = 0x84C0;
pub const GL_TEXTURE1 = 0x84C1;
pub const GL_RGBA32F = 0x8814;
pub const GL_RGBA16F = 0x881A;
pub const GL_ARRAY_BUFFER = 0x8892;
pub const GL_STREAM_DRAW = 0x88E0;
pub const GL_FRAGMENT_SHADER = 0x8B30;
pub const GL_VERTEX_SHADER = 0x8B31;
pub const GL_COMPILE_STATUS = 0x8B81;
pub const GL_LINK_STATUS = 0x8B82;
pub const GL_READ_FRAMEBUFFER = 0x8CA8;
pub const GL_FRAMEBUFFER_COMPLETE = 0x8CD5;
pub const GL_COLOR_ATTACHMENT0 = 0x8CE0;
pub const GL_FRAMEBUFFER = 0x8D40;
pub const GL_COLOR_BUFFER_BIT = 0x00004000;

const js = struct {
    extern "gl" fn createBuffer() GLuint;
    extern "gl" fn createTexture() GLuint;
    extern "gl" fn createFramebuffer() GLuint;
    extern "gl" fn createVertexArray() GLuint;
    extern "gl" fn deleteBuffer(id: GLuint) void;
    extern "gl" fn deleteTexture(id: GLuint) void;
    extern "gl" fn deleteFramebuffer(id: GLuint) void;
    extern "gl" fn deleteVertexArray(id: GLuint) void;
    extern "gl" fn createShader(kind: GLenum) GLuint;
    extern "gl" fn deleteShader(id: GLuint) void;
    extern "gl" fn shaderSource(id: GLuint, ptr: [*]const u8, len: usize) void;
    extern "gl" fn compileShader(id: GLuint) void;
    extern "gl" fn getShaderParameter(id: GLuint, pname: GLenum) GLint;
    extern "gl" fn getShaderInfoLog(id: GLuint, buf: [*]u8, cap: usize) usize;
    extern "gl" fn createProgram() GLuint;
    extern "gl" fn deleteProgram(id: GLuint) void;
    extern "gl" fn attachShader(program: GLuint, shader: GLuint) void;
    extern "gl" fn linkProgram(id: GLuint) void;
    extern "gl" fn getProgramParameter(id: GLuint, pname: GLenum) GLint;
    extern "gl" fn getProgramInfoLog(id: GLuint, buf: [*]u8, cap: usize) usize;
    extern "gl" fn useProgram(id: GLuint) void;
    extern "gl" fn getUniformLocation(program: GLuint, ptr: [*]const u8, len: usize) GLint;
    extern "gl" fn uniform1i(loc: GLint, v: GLint) void;
    extern "gl" fn uniform1f(loc: GLint, v: f32) void;
    extern "gl" fn uniformMatrix4fv(loc: GLint, ptr: [*]const f32) void;
    extern "gl" fn bindBuffer(target: GLenum, id: GLuint) void;
    extern "gl" fn bufferData(target: GLenum, ptr: ?[*]const u8, len: usize, usage: GLenum) void;
    extern "gl" fn bindVertexArray(id: GLuint) void;
    extern "gl" fn enableVertexAttribArray(index: GLuint) void;
    extern "gl" fn vertexAttribPointer(index: GLuint, size: GLint, kind: GLenum, normalized: GLboolean, stride: GLsizei, offset: usize) void;
    extern "gl" fn bindTexture(target: GLenum, id: GLuint) void;
    extern "gl" fn activeTexture(unit: GLenum) void;
    extern "gl" fn texParameteri(target: GLenum, pname: GLenum, v: GLint) void;
    extern "gl" fn texImage2D(target: GLenum, level: GLint, internal: GLint, w: GLsizei, h: GLsizei, format: GLenum, kind: GLenum, ptr: ?[*]const u8, len: usize) void;
    extern "gl" fn pixelStorei(pname: GLenum, v: GLint) void;
    extern "gl" fn bindFramebuffer(target: GLenum, id: GLuint) void;
    extern "gl" fn framebufferTexture2D(target: GLenum, attachment: GLenum, textarget: GLenum, tex: GLuint, level: GLint) void;
    extern "gl" fn checkFramebufferStatus(target: GLenum) GLenum;
    extern "gl" fn readPixels(x: GLint, y: GLint, w: GLsizei, h: GLsizei, format: GLenum, kind: GLenum, ptr: [*]u8, len: usize) void;
    extern "gl" fn viewport(x: GLint, y: GLint, w: GLsizei, h: GLsizei) void;
    extern "gl" fn clearColor(r: f32, g: f32, b: f32, a: f32) void;
    extern "gl" fn clear(mask: GLbitfield) void;
    extern "gl" fn enable(cap: GLenum) void;
    extern "gl" fn disable(cap: GLenum) void;
    extern "gl" fn blendFunc(src: GLenum, dst: GLenum) void;
    extern "gl" fn drawArrays(mode: GLenum, first: GLint, count: GLsizei) void;
};

fn count(n: GLsizei) usize {
    return @intCast(n);
}

pub fn glGenBuffers(n: GLsizei, ids: [*c]GLuint) void {
    for (0..count(n)) |i| ids[i] = js.createBuffer();
}
pub fn glGenTextures(n: GLsizei, ids: [*c]GLuint) void {
    for (0..count(n)) |i| ids[i] = js.createTexture();
}
pub fn glGenFramebuffers(n: GLsizei, ids: [*c]GLuint) void {
    for (0..count(n)) |i| ids[i] = js.createFramebuffer();
}
pub fn glGenVertexArrays(n: GLsizei, ids: [*c]GLuint) void {
    for (0..count(n)) |i| ids[i] = js.createVertexArray();
}
pub fn glDeleteBuffers(n: GLsizei, ids: [*c]const GLuint) void {
    for (0..count(n)) |i| js.deleteBuffer(ids[i]);
}
pub fn glDeleteTextures(n: GLsizei, ids: [*c]const GLuint) void {
    for (0..count(n)) |i| js.deleteTexture(ids[i]);
}
pub fn glDeleteFramebuffers(n: GLsizei, ids: [*c]const GLuint) void {
    for (0..count(n)) |i| js.deleteFramebuffer(ids[i]);
}
pub fn glDeleteVertexArrays(n: GLsizei, ids: [*c]const GLuint) void {
    for (0..count(n)) |i| js.deleteVertexArray(ids[i]);
}

pub const glCreateShader = js.createShader;
pub const glDeleteShader = js.deleteShader;
pub const glCompileShader = js.compileShader;
pub const glCreateProgram = js.createProgram;
pub const glDeleteProgram = js.deleteProgram;
pub const glAttachShader = js.attachShader;
pub const glLinkProgram = js.linkProgram;
pub const glUseProgram = js.useProgram;
pub const glUniform1i = js.uniform1i;
pub const glUniform1f = js.uniform1f;
pub const glBindBuffer = js.bindBuffer;
pub const glBindVertexArray = js.bindVertexArray;
pub const glEnableVertexAttribArray = js.enableVertexAttribArray;
pub const glBindTexture = js.bindTexture;
pub const glActiveTexture = js.activeTexture;
pub const glTexParameteri = js.texParameteri;
pub const glPixelStorei = js.pixelStorei;
pub const glBindFramebuffer = js.bindFramebuffer;
pub const glFramebufferTexture2D = js.framebufferTexture2D;
pub const glCheckFramebufferStatus = js.checkFramebufferStatus;
pub const glViewport = js.viewport;
pub const glClearColor = js.clearColor;
pub const glClear = js.clear;
pub const glEnable = js.enable;
pub const glDisable = js.disable;
pub const glBlendFunc = js.blendFunc;
pub const glDrawArrays = js.drawArrays;

pub fn glShaderSource(id: GLuint, n: GLsizei, strings: [*c]const [*c]const u8, lengths: [*c]const GLint) void {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.heap.c_allocator);
    for (0..count(n)) |i| {
        const s = strings[i];
        const len: usize = if (lengths != null and lengths[i] >= 0) @intCast(lengths[i]) else std.mem.len(s);
        buf.appendSlice(std.heap.c_allocator, s[0..len]) catch @panic("OOM");
    }
    js.shaderSource(id, buf.items.ptr, buf.items.len);
}

pub fn glGetShaderiv(id: GLuint, pname: GLenum, out: [*c]GLint) void {
    out.* = js.getShaderParameter(id, pname);
}

pub fn glGetProgramiv(id: GLuint, pname: GLenum, out: [*c]GLint) void {
    out.* = js.getProgramParameter(id, pname);
}

pub fn glGetShaderInfoLog(id: GLuint, cap: GLsizei, len: [*c]GLsizei, buf: [*c]u8) void {
    const n = js.getShaderInfoLog(id, buf, count(cap));
    if (len != null) len.* = @intCast(n);
}

pub fn glGetProgramInfoLog(id: GLuint, cap: GLsizei, len: [*c]GLsizei, buf: [*c]u8) void {
    const n = js.getProgramInfoLog(id, buf, count(cap));
    if (len != null) len.* = @intCast(n);
}

pub fn glGetUniformLocation(program: GLuint, name: [*c]const u8) GLint {
    return js.getUniformLocation(program, name, std.mem.len(name));
}

pub fn glUniformMatrix4fv(loc: GLint, n: GLsizei, transpose: GLboolean, value: [*c]const f32) void {
    std.debug.assert(n == 1 and transpose == GL_FALSE);
    js.uniformMatrix4fv(loc, value);
}

pub fn glBufferData(target: GLenum, size: GLsizeiptr, data: ?*const anyopaque, usage: GLenum) void {
    js.bufferData(target, @ptrCast(data), @intCast(size), usage);
}

pub fn glVertexAttribPointer(index: GLuint, size: GLint, kind: GLenum, normalized: GLboolean, stride: GLsizei, offset: ?*const anyopaque) void {
    js.vertexAttribPointer(index, size, kind, normalized, stride, @intFromPtr(offset));
}

/// Bytes per texel for the format/type pairs the renderer uploads or reads.
fn texelBytes(format: GLenum, kind: GLenum) usize {
    const components: usize = switch (format) {
        GL_RGBA => 4,
        GL_RG_INTEGER => 2,
        else => unreachable,
    };
    const size: usize = switch (kind) {
        GL_FLOAT => 4,
        GL_UNSIGNED_SHORT => 2,
        GL_UNSIGNED_BYTE => 1,
        else => unreachable,
    };
    return components * size;
}

pub fn glTexImage2D(target: GLenum, level: GLint, internal: GLint, w: GLsizei, h: GLsizei, border: GLint, format: GLenum, kind: GLenum, pixels: ?*const anyopaque) void {
    std.debug.assert(border == 0);
    const len = count(w) * count(h) * texelBytes(format, kind);
    js.texImage2D(target, level, internal, w, h, format, kind, @ptrCast(pixels), if (pixels == null) 0 else len);
}

pub fn glReadPixels(x: GLint, y: GLint, w: GLsizei, h: GLsizei, format: GLenum, kind: GLenum, pixels: ?*anyopaque) void {
    js.readPixels(x, y, w, h, format, kind, @ptrCast(pixels.?), count(w) * count(h) * texelBytes(format, kind));
}
