//! GLSL sources. The Slug coverage solver is adapted from slughorn's
//! example/slughorn-example-glfw.cpp (MIT, Copyright (c) 2026 AlphaPixel LLC), which in
//! turn implements Eric Lengyel's Slug algorithm.

pub const version = "#version 330 core\n";

/// Vector shapes in pixel space. Prefix with `#define TEX_WIDTH <log2 atlas width>`.
pub const slug_vert =
    \\layout(location = 0) in vec2 a_pos;
    \\layout(location = 1) in vec4 a_color;
    \\layout(location = 2) in vec2 a_em;
    \\layout(location = 3) in vec4 a_bandTransform;
    \\layout(location = 4) in vec4 a_shapeData;
    \\
    \\uniform mat4 u_mvp;
    \\
    \\out vec2 v_em;
    \\out vec4 v_color;
    \\flat out vec4 v_bandTransform;
    \\flat out vec4 v_shapeData;
    \\
    \\void main() {
    \\    v_em = a_em;
    \\    v_color = a_color;
    \\    v_bandTransform = a_bandTransform;
    \\    v_shapeData = a_shapeData;
    \\    gl_Position = u_mvp * vec4(a_pos, 0.0, 1.0);
    \\}
;

pub const slug_frag =
    \\in vec2 v_em;
    \\in vec4 v_color;
    \\flat in vec4 v_bandTransform;
    \\flat in vec4 v_shapeData;
    \\
    \\uniform sampler2D u_curveTexture;
    \\uniform usampler2D u_bandTexture;
    \\
    \\out vec4 fragColor;
    \\
    \\#define SLUG_INDIRECTION_SIZE 32
    \\
    \\uint slug_CalcRootCode(float y1, float y2, float y3) {
    \\    uint i1 = floatBitsToUint(y1) >> 31u;
    \\    uint i2 = floatBitsToUint(y2) >> 30u;
    \\    uint i3 = floatBitsToUint(y3) >> 29u;
    \\    uint shift = (i2 & 2u) | (i1 & ~2u);
    \\    shift = (i3 & 4u) | (shift & ~4u);
    \\    return ((0x2E74u >> shift) & 0x0101u);
    \\}
    \\
    \\vec2 slug_SolveRoots(float a, float b, float c) {
    \\    float disc = b * b - a * c;
    \\    float d = sqrt(max(disc, 0.0));
    \\    float q = b >= 0.0 ? b + d : b - d;
    \\    float tFar = q / a;
    \\    float tNear = disc > 0.0 ? c / q : tFar;
    \\    return b >= 0.0 ? vec2(tNear, tFar) : vec2(tFar, tNear);
    \\}
    \\
    \\vec2 slug_SolveHorizPoly(vec4 p12, vec2 p3) {
    \\    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    \\    vec2 b = p12.xy - p12.zw;
    \\    float rb = 0.5 / b.y;
    \\    vec2 t = slug_SolveRoots(a.y, b.y, p12.y);
    \\    float t1 = t.x;
    \\    float t2 = t.y;
    \\    if(abs(a.y) < 1.0 / 65536.0) { t1 = p12.y * rb; t2 = t1; }
    \\    return vec2((a.x * t1 - b.x * 2.0) * t1 + p12.x, (a.x * t2 - b.x * 2.0) * t2 + p12.x);
    \\}
    \\
    \\vec2 slug_SolveVertPoly(vec4 p12, vec2 p3) {
    \\    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    \\    vec2 b = p12.xy - p12.zw;
    \\    float rb = 0.5 / b.x;
    \\    vec2 t = slug_SolveRoots(a.x, b.x, p12.x);
    \\    float t1 = t.x;
    \\    float t2 = t.y;
    \\    if(abs(a.x) < 1.0 / 65536.0) { t1 = p12.x * rb; t2 = t1; }
    \\    return vec2((a.y * t1 - b.y * 2.0) * t1 + p12.y, (a.y * t2 - b.y * 2.0) * t2 + p12.y);
    \\}
    \\
    \\ivec2 slug_Wrap(ivec2 loc, int offset) {
    \\    ivec2 r = ivec2(loc.x + offset, loc.y);
    \\    r.y += r.x >> TEX_WIDTH;
    \\    r.x &= (1 << TEX_WIDTH) - 1;
    \\    return r;
    \\}
    \\
    \\float slug_CalcCoverage(float xcov, float ycov, float xwgt, float ywgt) {
    \\    float coverage = max(
    \\        abs(xcov * xwgt + ycov * ywgt) / max(xwgt + ywgt, 1.0 / 65536.0),
    \\        min(abs(xcov), abs(ycov)));
    \\    return clamp(coverage, 0.0, 1.0);
    \\}
    \\
    \\float slug_Render(vec2 rc, vec4 bandTransform, ivec2 glyphLoc, ivec2 bandMax) {
    \\    vec2 pixelsPerEm = 1.0 / fwidth(rc);
    \\
    \\    int qY = clamp(int(rc.y * bandTransform.y + bandTransform.w), 0, SLUG_INDIRECTION_SIZE - 1);
    \\    int qX = clamp(int(rc.x * bandTransform.x + bandTransform.z), 0, SLUG_INDIRECTION_SIZE - 1);
    \\    int bandY = int(texelFetch(u_bandTexture, ivec2(glyphLoc.x + qY, glyphLoc.y), 0).r);
    \\    int bandX = int(texelFetch(u_bandTexture, ivec2(glyphLoc.x + SLUG_INDIRECTION_SIZE + qX, glyphLoc.y), 0).r);
    \\
    \\    float xcov = 0.0, xwgt = 0.0;
    \\    uvec2 hband = texelFetch(u_bandTexture, ivec2(glyphLoc.x + 2 * SLUG_INDIRECTION_SIZE + bandY, glyphLoc.y), 0).xy;
    \\    for(int ci = 0; ci < int(hband.x); ci++) {
    \\        ivec2 curveLoc = ivec2(texelFetch(u_bandTexture, slug_Wrap(glyphLoc, int(hband.y) + ci), 0).xy);
    \\        vec4 p12 = texelFetch(u_curveTexture, curveLoc, 0) - vec4(rc, rc);
    \\        vec2 p3 = texelFetch(u_curveTexture, slug_Wrap(curveLoc, 1), 0).xy - rc;
    \\        if(max(max(p12.x, p12.z), p3.x) * pixelsPerEm.x < -0.5) break;
    \\        uint code = slug_CalcRootCode(p12.y, p12.w, p3.y);
    \\        if(code != 0u) {
    \\            vec2 r = slug_SolveHorizPoly(p12, p3) * pixelsPerEm.x;
    \\            if((code & 1u) != 0u) { xcov += clamp(r.x + 0.5, 0.0, 1.0); xwgt = max(xwgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0)); }
    \\            if(code > 1u) { xcov -= clamp(r.y + 0.5, 0.0, 1.0); xwgt = max(xwgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0)); }
    \\        }
    \\    }
    \\
    \\    float ycov = 0.0, ywgt = 0.0;
    \\    uvec2 vband = texelFetch(u_bandTexture, ivec2(glyphLoc.x + 2 * SLUG_INDIRECTION_SIZE + bandMax.y + 1 + bandX, glyphLoc.y), 0).xy;
    \\    for(int ci = 0; ci < int(vband.x); ci++) {
    \\        ivec2 curveLoc = ivec2(texelFetch(u_bandTexture, slug_Wrap(glyphLoc, int(vband.y) + ci), 0).xy);
    \\        vec4 p12 = texelFetch(u_curveTexture, curveLoc, 0) - vec4(rc, rc);
    \\        vec2 p3 = texelFetch(u_curveTexture, slug_Wrap(curveLoc, 1), 0).xy - rc;
    \\        if(max(max(p12.y, p12.w), p3.y) * pixelsPerEm.y < -0.5) break;
    \\        uint code = slug_CalcRootCode(p12.x, p12.z, p3.x);
    \\        if(code != 0u) {
    \\            vec2 r = slug_SolveVertPoly(p12, p3) * pixelsPerEm.y;
    \\            if((code & 1u) != 0u) { ycov -= clamp(r.x + 0.5, 0.0, 1.0); ywgt = max(ywgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0)); }
    \\            if(code > 1u) { ycov += clamp(r.y + 0.5, 0.0, 1.0); ywgt = max(ywgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0)); }
    \\        }
    \\    }
    \\
    \\    return slug_CalcCoverage(xcov, ycov, xwgt, ywgt);
    \\}
    \\
    \\void main() {
    \\    float fill = slug_Render(v_em, v_bandTransform, ivec2(v_shapeData.xy), ivec2(v_shapeData.zw));
    \\    if(fill < 0.001) discard;
    \\    fragColor = vec4(v_color.rgb, fill * v_color.a);
    \\}
;

/// The picture plane: previous frame textured onto a quad seen by the virtual camera.
pub const plane_vert =
    \\layout(location = 0) in vec2 a_pos;
    \\layout(location = 1) in vec2 a_uv;
    \\uniform mat4 u_mvp;
    \\out vec2 v_uv;
    \\void main() {
    \\    v_uv = a_uv;
    \\    gl_Position = u_mvp * vec4(a_pos, 0.0, 1.0);
    \\}
;

pub const plane_frag =
    \\in vec2 v_uv;
    \\uniform sampler2D u_prev;
    \\uniform float u_gain;
    \\uniform float u_hue;
    \\uniform float u_border;
    \\out vec4 fragColor;
    \\
    \\// Rotate a colour around the grey axis (Rodrigues' formula).
    \\vec3 hueRotate(vec3 c, float a) {
    \\    const vec3 k = vec3(0.57735027);
    \\    float ca = cos(a);
    \\    return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
    \\}
    \\
    \\void main() {
    \\    vec3 c = max(hueRotate(texture(u_prev, v_uv).rgb, u_hue), 0.0) * u_gain;
    \\    if(u_border > 0.0) {
    \\        vec2 d = min(v_uv, 1.0 - v_uv);
    \\        float edge = min(d.x, d.y);
    \\        float aa = fwidth(edge);
    \\        c = mix(vec3(0.85), c, smoothstep(u_border - aa, u_border + aa, edge));
    \\    }
    \\    fragColor = vec4(c, 1.0);
    \\}
;

/// Copies a texture to the whole viewport (fullscreen triangle, no vertex buffer).
pub const present_vert =
    \\out vec2 v_uv;
    \\void main() {
    \\    vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
    \\    v_uv = p;
    \\    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
    \\}
;

pub const present_frag =
    \\in vec2 v_uv;
    \\uniform sampler2D u_tex;
    \\out vec4 fragColor;
    \\void main() {
    \\    fragColor = vec4(texture(u_tex, v_uv).rgb, 1.0);
    \\}
;
